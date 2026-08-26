import std/[tables,logging]
import ../ltypes, ../lvalue, ../lerror, ../lvm


proc asCoroutine(v: LuaValue): LuaCoroutine =
  if not isCoroutine(v):
    raise newException(LuaRuntimeError, "bad argument (coroutine expected)")
  return getCoroutine(v)

proc canYieldNow(vm: VM): bool =
  if vm.currentCoroutine.isNil: return false
  return vm.nestedRunDepth == getCoroutine(vm.currentCoroutine).ownRunDepth

proc coroutineIsYieldable(vm: VM, co: LuaCoroutine): bool =
  case co.status
  of csSuspended: true   # only reachable via a successful yield (or never started) --
                          # either way, definitionally sitting at a valid yield point
  of csNormal: false     # paused inside its OWN call to resume() -- a real C-call boundary
  of csDead: false
  of csRunning:
    # Only meaningful if co IS the currently active coroutine -- ask the live question.
    not vm.currentCoroutine.isNil and getCoroutine(vm.currentCoroutine) == co and canYieldNow(vm)

proc luaCoroutineIsYieldable*(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 1:
    return @[newLuaBool(canYieldNow(vm))]   # no argument -- ask about wherever we currently are
  let co = asCoroutine(args[0])
  return @[newLuaBool(coroutineIsYieldable(vm, co))]

proc luaCoroutineStatus*(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 1:
    raise newException(LuaRuntimeError, "bad argument #1 to 'status' (coroutine expected)")
  let co = asCoroutine(args[0])
  let s = case co.status
    of csSuspended: "suspended"
    of csRunning: "running"
    of csNormal: "normal"
    of csDead: "dead"
  return @[newLuaString(s)]

proc luaCoroutineYield*(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if vm.currentCoroutine.isNil:
    raise newException(LuaRuntimeError, "attempt to yield from outside a coroutine")
  let co = getCoroutine(vm.currentCoroutine)
  if vm.nestedRunDepth != co.ownRunDepth:
    raise newException(LuaRuntimeError, "attempt to yield across a C-call boundary")
  vm.yieldValues = @args
  vm.yieldRequested = true
  return @[]

proc luaCoroutineResume*(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 1:
    raise newException(LuaRuntimeError, "bad argument #1 to 'resume' (coroutine expected)")
  let coVal = args[0]
  let co = asCoroutine(coVal)
  let resumeArgs = if args.len > 1: args[1 .. ^1] else: @[]

  if co.status == csDead:
    return @[newLuaBool(false), newLuaString("cannot resume dead coroutine")]
  if co.status in {csRunning, csNormal}:
    return @[newLuaBool(false), newLuaString("cannot resume non-suspended coroutine")]

  # Save whoever is CURRENTLY active -- the main thread, or another coroutine
  # that resumed this one. Since LuaStack is a ref, this is just remembering
  # WHICH object vm.stack pointed at -- no copying involved. Nim's own
  # recursion handles nested resume-inside-resume correctly: each call to
  # luaCoroutineResume has its own local prevFrames/prevStack, so coroutine A
  # resuming coroutine B "just works" without any special-casing.
  let prevCoroutine = vm.currentCoroutine
  let prevFrames = vm.frames
  let prevStack = vm.stack
  if not prevCoroutine.isNil:
    getCoroutine(prevCoroutine).status = csNormal

  co.status = csRunning
  co.ownRunDepth = vm.nestedRunDepth + 1
  vm.currentCoroutine = coVal
  vm.frames = co.frames
  vm.stack = co.stack
  vm.yieldRequested = false
  
  if not co.hasStarted:
    co.hasStarted = true
    vm.stack.add(co.fn)
    for a in resumeArgs: vm.stack.add(a)
    vm.performCall(resumeArgs.len)
  else:
    # Continuing after a previous yield: these args become what yield()
    # appears to "return" inside the coroutine -- delivered via the SAME
    # opAdjust instruction that was already sitting, unexecuted, right
    # after yield's own opCall when we suspended. No new mechanism needed.
    for a in resumeArgs: vm.stack.add(a)
    vm.lastReturnCount = resumeArgs.len

  var results: seq[LuaValue] = @[]
  var errored = false
  var errMsg = ""
  try:
    discard vm.run(0)
    if vm.yieldRequested:
      co.status = csSuspended
      results = vm.yieldValues
      vm.yieldRequested = false
    else:
      co.status = csDead
      let n = vm.lastReturnCount
      results = newSeq[LuaValue](n)
      for i in countdown(n - 1, 0): results[i] = vm.pop()
  except LuaRuntimeError as e:
    co.status = csDead
    errored = true
    errMsg = e.msg

  co.frames = vm.frames
  co.stack = vm.stack
  vm.currentCoroutine = prevCoroutine
  vm.frames = prevFrames
  vm.stack = prevStack
  if not prevCoroutine.isNil: getCoroutine(prevCoroutine).status = csRunning

  if errored:
    return @[newLuaBool(false), newLuaString(errMsg)]
  result = @[newLuaBool(true)]
  result.add(results)

proc luaCoroutineCreate(args: varargs[LuaValue]): seq[LuaValue] =
    if args.len < 1 or not isCallable(args[0]):
      raise newException(LuaRuntimeError, "bad argument #1 to 'create' (function expected)")
    
    return @[newLuaCoroutine(args[0])]

proc luaCoroutineWrap(args: varargs[LuaValue]): seq[LuaValue] = 
    if args.len < 1 or not isCallable(args[0]):
      raise newException(LuaRuntimeError, "bad argument #1 to 'wrap' (function expected)")
    let co = luaCoroutineCreate(args[0])[0]
    let wrapped = proc(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
      let results = luaCoroutineResume(vm, @[co] & @args)
      if truthy(results[0]):
       return results[1 .. ^1]   # strip the leading success boolean
      else:
       let errVal = results[1]
       vm.lastError = errVal
       let msgStr = if isString(errVal): errVal.sval else: $errVal
       raise newException(LuaRuntimeError, msgStr)
    return @[newNimFnVM(wrapped)]

proc luaCoroutineRunning(vm: var VM,args: varargs[LuaValue]): seq[LuaValue] = 
    let co = vm.currentCoroutine
    if isNil(co):
      return @[newLuaNil(),newLuaBool(true)]
    else:
      return @[co,newLuaBool(false)]

proc luaCoroutineClose*(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 1:
    raise newException(LuaRuntimeError, "bad argument #1 to 'close' (coroutine expected)")
  let co = asCoroutine(args[0])

  if co.status == csRunning:
    raise newException(LuaRuntimeError, "cannot close a running coroutine")
  if co.status == csNormal:
    raise newException(LuaRuntimeError, "cannot close a normal coroutine")

  var errored = false
  var errVal = newLuaNil()

  if co.frames.len > 0:
    # Swap onto the coroutine's own stack/frames to run its handlers --
    # same save/restore shape resume() uses.
    let prevFrames = vm.frames
    let prevStack = vm.stack
    vm.frames = co.frames
    vm.stack = co.stack

    try:
      # Innermost frame first; within a frame, reverse declaration order --
      # matching how emitScopeCleanup unwinds, so nested resources release
      # inside-out.
      for fi in countdown(co.frames.high, 0):
        let f = co.frames[fi]
        for si in countdown(f.toClose.high, 0):
          if f.toClose[si].closed: continue
          f.toClose[si].closed = true

          let idx = f.slotBase + f.toClose[si].slot
          if idx >= vm.stack.values.len: continue
          let val = vm.stack[idx]
          if val.kind in {ltTable, ltUserData} and not isNil(val.mt) and
             val.mt.tval.hasKey(MTCLOSE):
            let handler = val.mt.tval[MTCLOSE]
            if handler.kind in {ltClosure, ltNativeFn, ltNativeFnVM}:
              try:
                let stopDepth = vm.frames.len
                vm.stack.values.add(handler)
                vm.stack.values.add(val)
                vm.stack.values.add(newLuaNil())
                vm.performCall(2)
                discard vm.run(stopDepth)
                vm.lastReturnCount = 0
              except LuaRuntimeError as e:
                # Keeps the LAST error if several handlers fail. Real Lua's
                # exact behavior here is unverified -- documented choice.
                errored = true
                errVal = if not isNil(vm.lastError): vm.lastError
                         else: newLuaString(e.msg)
    finally:
      vm.frames = prevFrames
      vm.stack = prevStack

  co.status = csDead
  co.frames = @[]
  co.stack = LuaStack(values: @[])

  if errored:
    return @[newLuaBool(false), errVal]
  return @[newLuaBool(true)]

proc newCoroutineLib*(): LuaValue =
    
  
  result = newLuaTable()
  result.tval[newLuaString("create")] = newNimFn(luaCoroutineCreate)
  result.tval[newLuaString("resume")] = newNimFnVM(luaCoroutineResume)
  result.tval[newLuaString("yield")] = newNimFnVM(luaCoroutineYield)
  result.tval[newLuaString("status")] = newNimFn(luaCoroutineStatus)
  result.tval[newLuaString("wrap")] = newNimFn(luaCoroutineWrap)
  result.tval[newLuaString("isyieldable")] = newNimFnVM(luaCoroutineIsYieldable)
  result.tval[newLuaString("running")] = newNimFnVM(luaCoroutineRunning)
  result.tval[newLuaString("close")] = newNimFnVM(luaCoroutineClose)