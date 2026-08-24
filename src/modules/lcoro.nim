import std/tables
import ../ltypes, ../lvalue, ../lerror, ../lvm

  # the nestedRunDepth value AT WHICH this coroutine's own
                       # top-level run() call executes -- yield() compares
                       # against this to detect a C-call-boundary violation

proc asCoroutine(v: LuaValue): LuaCoroutine =
  if not isUserData(v) or v.ud.isNil or not (v.ud of LuaCoroutine):
    raise newException(LuaRuntimeError, "bad argument (coroutine expected)")
  return LuaCoroutine(v.ud)

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
  let co = LuaCoroutine(vm.currentCoroutine)
  if vm.nestedRunDepth != co.ownRunDepth:
    raise newException(LuaRuntimeError, "attempt to yield across a C-call boundary")
  vm.yieldValues = @args
  vm.yieldRequested = true
  return @[]

proc luaCoroutineResume*(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 1:
    raise newException(LuaRuntimeError, "bad argument #1 to 'resume' (coroutine expected)")
  let co = asCoroutine(args[0])
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
    LuaCoroutine(prevCoroutine).status = csNormal   # alive, but suspended because it resumed something else

  vm.currentCoroutine = co
  co.status = csRunning
  vm.frames = co.frames
  vm.stack = co.stack
  vm.yieldRequested = false
  co.ownRunDepth = vm.nestedRunDepth + 1

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
  if not prevCoroutine.isNil: LuaCoroutine(prevCoroutine).status = csRunning

  if errored:
    return @[newLuaBool(false), newLuaString(errMsg)]
  result = @[newLuaBool(true)]
  result.add(results)

proc newCoroutineLib*(): LuaValue =
  let CoroutineMethods = newLuaTable()
  CoroutineMethods.tval[newLuaString("resume")] = newNimFnVM(luaCoroutineResume)
  CoroutineMethods.tval[newLuaString("status")] = newNimFn(luaCoroutineStatus)

  let coroutineMT = newLuaTable()
  coroutineMT.tval[MTINDEX] = CoroutineMethods
  coroutineMT.tval[MTTYPE] = newLuaString("thread")   # matches real Lua's type() naming

  let luaCoroutineCreate = proc(args: varargs[LuaValue]): seq[LuaValue] =
    if args.len < 1 or not isCallable(args[0]):
      raise newException(LuaRuntimeError, "bad argument #1 to 'create' (function expected)")
    let co = LuaCoroutine(fn: args[0], status: csSuspended, hasStarted: false,
                          frames: @[], stack: LuaStack(values: @[]))
    let wrapped = newUserData(co)
    wrapped.mt = coroutineMT
    return @[wrapped]

  result = newLuaTable()
  result.tval[newLuaString("create")] = newNimFn(luaCoroutineCreate)
  result.tval[newLuaString("resume")] = newNimFnVM(luaCoroutineResume)
  result.tval[newLuaString("yield")] = newNimFnVM(luaCoroutineYield)
  result.tval[newLuaString("status")] = newNimFn(luaCoroutineStatus)