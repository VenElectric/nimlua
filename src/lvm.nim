import std/[tables, strutils, logging, math, bitops, sets]
import lvalue, lerror, ltypes, lcompiler

const MaxIndexDepth = 500

type BinopProc = proc(vm: var VM, l, r: LuaValue): LuaValue
type UnopProc = proc(vm: var VM, r: LuaValue): LuaValue

proc run*(vm: var VM, stopDepth: int = 0): int
proc adjustResults*(vm: var VM, want: int)

proc newVM*(): VM =
  # We pre-allocate a reasonable stack size to avoid constant memory reallocations
  VM(stack: LuaStack(values:newSeqOfCap[LuaValue](256)))

proc push*(vm: var VM, value: LuaValue) =
  vm.stack.values.add(value)

proc pop*(vm: var VM): LuaValue =
  return vm.stack.values.pop()

proc peek*(vm: VM, distance: int): LuaValue = vm.stack[vm.stack.values.len - 1 - distance]

proc chunk(cf: CallFrame): Chunk = cf.closure.fn.chunk

# We define a helper macro or proc to read a byte and advance the IP
proc readByte(vm: var VM): uint8 =
  let frameIp = vm.frames[^1].ip
  result = vm.frames[^1].chunk().code[frameIp]
  inc(vm.frames[^1].ip)

proc readShort(vm: var VM): uint16 =
  let frameIp = vm.frames[^1].ip
  let highByte = uint16(vm.frames[^1].chunk.code[frameIp])
  let lowByte = uint16(vm.frames[^1].chunk.code[frameIp + 1])
  vm.frames[^1].ip += 2
  return (highByte shl 8) or lowByte

proc performCall*(vm: var VM, argCount: int) =
  let fnIndex = vm.stack.values.len - argCount - 1
  let callee = vm.stack[fnIndex]
  if callee.kind == ltClosure:
    let luaFn = callee.fnVal

    var varargTable = newLuaTable()
    if luaFn.fn.isVararg:
      let extraCount = max(0, argCount - luaFn.fn.arity)
      for i in 0 ..< extraCount:
        # Grab extra args off the stack (Lua tables are conventionally 1-indexed)
        let argVal = vm.stack[fnIndex + 1 + luaFn.fn.arity + i]
        varargTable.tval[newLuaNumber(float64(i + 1))] = argVal

    if argCount > luaFn.fn.arity:
      # Trim excess arguments off the stack so slotBase stays perfectly aligned
      vm.stack.values.setLen(fnIndex + 1 + luaFn.fn.arity)
    elif argCount < luaFn.fn.arity:
      # Pad missing named arguments with nil
      let missing = luaFn.fn.arity - argCount
      for _ in 0 ..< missing: vm.push(newLuaNil())

    let newFrame = CallFrame(
      closure: luaFn,
      ip: 0,
      slotBase: fnIndex,
      vararg: varargTable
    )
    vm.frames.add(newFrame)

  elif callee.kind == ltNativeFn:
    var args = newSeq[LuaValue](argCount)
    for i in countdown(argCount - 1, 0): args[i] = vm.pop()
    discard vm.pop()
    let results = callee.nativeFn(args)
    for r in results: vm.push(r)
    vm.lastReturnCount = results.len
  elif callee.kind == ltNativeFnVM:
    var args = newSeq[LuaValue](argCount)
    for i in countdown(argCount - 1, 0): args[i] = vm.pop()
    discard vm.pop()
    let results = callee.nativeFnVM(vm, args)
    for r in results: vm.push(r)
    vm.lastReturnCount = results.len
  else:
    raise newException(LuaRuntimeError, "Attempt to call a non-function value!")

proc doReturn(vm: var VM, frame: CallFrame, n: int, stopDepth: int): bool =
  discard vm.frames.pop()
  var results = newSeq[LuaValue](n)
  for i in countdown(n - 1, 0): results[i] = vm.pop()
  vm.closeUpvalues(frame.slotBase)
  vm.lastReturnCount = n
  vm.stack.values.setLen(frame.slotBase)
  for r in results: vm.stack.values.add(r)
  return vm.frames.len == stopDepth

proc traceInstruction(vm: VM, ip: int, opName: OpCode) =
  if not vm.traceExecution: return

  # 1. Format the stack state
  var stackDump = "["
  for i, val in vm.stack.values:
    debug "Kind: ", val.kind
    stackDump.add($val)
    if i < vm.stack.values.high: stackDump.add(", ")
  stackDump.add("]")

  # 2. Log the IP, OpCode, and Stack
  debug "IP: ", align($ip, 4), " | OP: ", align($opName, 12), " | Stack: ", stackDump

proc callMetamethod*(vm: var VM, handler: LuaValue, wantResults: int,
    args: varargs[LuaValue]): seq[LuaValue] =
  if handler.kind notin {ltClosure, ltNativeFn, ltNativeFnVM}:
    raise newException(LuaRuntimeError, "attempt to call a " & $handler.kind & " value")
  let stopDepth = vm.frames.len
  vm.push(handler)
  for a in args: vm.push(a)
  vm.performCall(args.len)
  discard vm.run(stopDepth)
  vm.adjustResults(wantResults)
  result = newSeq[LuaValue](wantResults)
  for i in countdown(wantResults - 1, 0): result[i] = vm.pop()

template binop(vm: var VM, bop: BinopProc): untyped =
  let r = vm.pop()
  let l = vm.pop()
  vm.push(bop(vm, l, r))

proc arithFallback(vm: var VM, mtKey: LuaValue, opName: string, l,
    r: LuaValue): LuaValue =
  var handler: LuaValue = nil
  if l.kind in {ltTable, ltUserData} and not isNil(l.mt) and l.mt.tval.hasKey(mtKey):
    handler = l.mt.tval[mtKey]
  elif r.kind in {ltTable, ltUserData} and not isNil(r.mt) and r.mt.tval.hasKey(mtKey):
    handler = r.mt.tval[mtKey]

  if handler == nil:
    raise newException(LuaRuntimeError, "Cannot perform '" & opName & "' on " &
        $l.kind & " and " & $r.kind)

  let results = vm.callMetamethod(handler, 1, l, r)
  return results[0]

proc unaryFallback(vm: var VM, mtKey: LuaValue, opName: string,
    r: LuaValue): LuaValue =
  if r.kind in {ltTable, ltUserData} and not isNil(r.mt) and r.mt.tval.hasKey(mtKey):
    return vm.callMetamethod(r.mt.tval[mtKey], 1, r)[0]
  raise newException(LuaRuntimeError, "Cannot perform '" & opName & "' on " & $r.kind)

proc luaAdd(vm: var VM, l, r: LuaValue): LuaValue =
  if isInteger(l) and isInteger(r):
    return newLuaInteger(l.ival + r.ival)
  elif isNumber(l) and isNumber(r):
    return newLuaNumber(numVal(l) + numVal(r))
  else:
    return vm.arithFallback(MTADD, "+", l, r)

proc luaDiv(vm: var VM, l, r: LuaValue): LuaValue =
  if isNumber(l) and isNumber(r):
    return newLuaNumber(numVal(l) / numVal(r))
  else:
    return vm.arithFallback(MTDIV, "/", l, r)

proc luaSub(vm: var VM, l, r: LuaValue): LuaValue =
  if isInteger(l) and isInteger(r):
    return newLuaInteger(l.ival - r.ival)
  elif isNumber(l) and isNumber(r):
    return newLuaNumber(numVal(l) - numVal(r))
  else:
    return vm.arithFallback(MTSUB, "-", l, r)

proc luaMul(vm: var VM, l, r: LuaValue): LuaValue =
  if isInteger(l) and isInteger(r):
    return newLuaInteger(l.ival * r.ival)
  elif isNumber(l) and isNumber(r):
    return newLuaNumber(numVal(l) * numVal(r))
  else:
    return vm.arithFallback(MTMUL, "*", l, r)

proc floorDivInt(l, r: int64): int64 =
  result = l div r
  if (l mod r != 0) and ((l < 0) != (r < 0)): dec result

proc luaFloorDiv(vm: var VM, l, r: LuaValue): LuaValue =
  if isInteger(l) and isInteger(r):
    if r.ival == 0: raise newException(LuaRuntimeError, "attempt to perform 'n//0'")
    return newLuaInteger(floorDivInt(l.ival, r.ival))
  elif isNumber(l) and isNumber(r):
    return newLuaNumber(floor(numVal(l) / numVal(r)))
  else:
    return vm.arithFallback(MTIDIV, "//", l, r)

proc luaModInt(l, r: int64): int64 =
  result = l mod r
  if result != 0 and ((result < 0) != (r < 0)): result += r

proc luaModFloat(l, r: float64): float64 = l - floor(l / r) * r

proc luaMod(vm: var VM, l, r: LuaValue): LuaValue =
  if isInteger(l) and isInteger(r):
    return newLuaInteger(luaModInt(l.ival, r.ival))
  elif isNumber(l) and isNumber(r):
    return newLuaNumber(luaModFloat(numVal(l), numVal(r)))
  else:
    return vm.arithFallback(MTMOD, "%", l, r)

proc luaPow(vm: var VM, l, r: LuaValue): LuaValue =
  if isNumber(l) and isNumber(r):
    return newLuaNumber(pow(numVal(l), numVal(r)))
  else:
    return vm.arithFallback(MTPOW, "^", l, r)

proc luaBitAnd(vm: var VM, l, r: LuaValue): LuaValue =
  if isNumber(l) and isNumber(r):
    return newLuaInteger(bitAnd(intVal(l), intVal(r)))
  else:
    return vm.arithFallback(MTBAND, "&", l, r)

proc luaBitOr(vm: var VM, l, r: LuaValue): LuaValue =
  if isNumber(l) and isNumber(r):
    return newLuaInteger(bitOr(intVal(l), intVal(r)))
  else:
    return vm.arithFallback(MTBOR, "|", l, r)

proc luaBitXor(vm: var VM, l, r: LuaValue): LuaValue =
  if isNumber(l) and isNumber(r):
    return newLuaInteger(bitXor(intVal(l), intVal(r)))
  else:
    return vm.arithFallback(MTBXOR, "~", l, r)

proc luaBitNot(vm: var VM, r: LuaValue): LuaValue =
  if isNumber(r):
    return newLuaInteger(bitNot(intVal(r)))
  else: return vm.unaryFallback(MTBNOT, "~", r)

proc luaShr(vm: var VM, l, r: LuaValue): LuaValue =
  if isNumber(l) and isNumber(r):
    return newLuaInteger(intVal(l) shr intVal(r))
  else:
    return vm.arithFallback(MTSHR, ">>", l, r)

proc luaShl(vm: var VM, l, r: LuaValue): LuaValue =
  if isNumber(l) and isNumber(r):
    return newLuaInteger(intVal(l) shl intVal(r))
  else:
    return vm.arithFallback(MTSHL, "<<", l, r)

proc `not`(r: LuaValue): LuaValue = newLuaBool(not truthy(r))

proc compareFallback(vm: var VM, mtKey: LuaValue, opName: string, l,
    r: LuaValue): LuaValue =
  var handler: LuaValue = nil
  if l.kind in {ltTable, ltUserData} and not isNil(l.mt) and l.mt.tval.hasKey(mtKey):
    handler = l.mt.tval[mtKey]
  elif r.kind in {ltTable, ltUserData} and not isNil(r.mt) and r.mt.tval.hasKey(mtKey):
    handler = r.mt.tval[mtKey]

  if handler == nil:
    raise newException(LuaRuntimeError, "Cannot perform '" & opName & "' on " &
        $l.kind & " and " & $r.kind)

  return newLuaBool(truthy(vm.callMetamethod(handler, 1, l, r)[0]))

proc luaLess*(vm: var VM, l, r: LuaValue): LuaValue =
  if isNumber(l) and isNumber(r):
    return newLuaBool(numVal(l) < numVal(r))
  elif isString(l) and isString(r):
    return newLuaBool(l.sval < r.sval)
  else:
    return vm.compareFallback(MTLT, "<", l, r)

proc luaLessEqual(vm: var VM, l, r: LuaValue): LuaValue =
  if isNumber(l) and isNumber(r):
    return newLuaBool(numVal(l) <= numVal(r))
  elif isString(l) and isString(r):
    return newLuaBool(l.sval <= r.sval)
  else:
    return vm.compareFallback(MTLE, "<=", l, r)

proc luaGreater(vm: var VM, l, r: LuaValue): LuaValue =
  try:
    return not luaLessEqual(vm, l, r)
  except LuaRuntimeError:
    raise newException(LuaRuntimeError, "Cannot perform '>' on " & $l.kind &
        " and " & $r.kind)

proc luaGreaterEqual(vm: var VM, l, r: LuaValue): LuaValue =
  try:
    return not luaLess(vm, l, r)
  except LuaRuntimeError:
    raise newException(LuaRuntimeError, "Cannot perform '>=' on " & $l.kind &
        " and " & $r.kind)

proc luaEquals(vm: var VM, l, r: LuaValue): LuaValue =
  if l == r: return newLuaBool(true)
  if (l.kind == ltTable and r.kind == ltTable) or (l.kind == ltUserData and
      r.kind == ltUserData):
    var handler: LuaValue = nil
    if not isNil(l.mt) and l.mt.tval.hasKey(MTEQ): handler = l.mt.tval[MTEQ]
    elif not isNil(r.mt) and r.mt.tval.hasKey(MTEQ): handler = r.mt.tval[MTEQ]
    if not isNil(handler):
      return newLuaBool(truthy(vm.callMetamethod(handler, 1, l, r)[0]))
  return newLuaBool(false)

proc luaNotEquals(vm: var VM, l, r: LuaValue): LuaValue = not luaEquals(vm, l, r)

proc luaConcat(vm: var VM) =
  let r = vm.pop()
  let l = vm.pop()
  if (isString(l) or isNumber(l)) and (isString(r) or isNumber(r)):
    let lStr = if isString(l): l.sval else: $l
    let rStr = if isString(r): r.sval else: $r
    vm.push(newLuaString(lStr & rStr))
  else:
    var handler: LuaValue = nil
    if l.kind in {ltTable, ltUserData} and not isNil(l.mt) and l.mt.tval.hasKey(MTCONCAT):
      handler = l.mt.tval[MTCONCAT]
    elif r.kind in {ltTable, ltUserData} and not isNil(r.mt) and r.mt.tval.hasKey(MTCONCAT):
      handler = r.mt.tval[MTCONCAT]
    if handler == nil:
      raise newException(LuaRuntimeError, "Cannot perform '..' on " & $l.kind & " and " & $r.kind)
    vm.push(vm.callMetamethod(handler, 1, l, r)[0])

proc adjustResults*(vm: var VM, want: int) =
  let have = vm.lastReturnCount
  if have > want:
    vm.stack.values.setLen(vm.stack.values.len - (have - want))
  elif have < want:
    for i in 0 ..< (want - have): vm.push(newLuaNil())
  vm.lastReturnCount = want

proc luaIndexGet*(vm: var VM, tblVal, key: LuaValue): LuaValue =
  if tblVal.kind == ltTable:
    if tblVal.tval.hasKey(key):
      return tblVal.tval[key]
  elif tblVal.kind != ltUserData:
    raise newException(LuaRuntimeError, "Attempt to index a " & $tblVal.kind & " value")

  if not isNil(tblVal.mt):
    let idxKey = newLuaString("__index")
    if tblVal.mt.tval.hasKey(idxKey):
      if vm.metaDepth >= MaxIndexDepth:
        raise newException(LuaRuntimeError, "'__index' chain too long; possible loop")
      let handler = tblVal.mt.tval[idxKey]
      case handler.kind
      of ltTable:
        inc(vm.metaDepth)
        try:
          return vm.luaIndexGet(handler, key)
        finally:
          dec(vm.metaDepth)
      of ltClosure, ltNativeFn, ltNativeFnVM:
        inc(vm.metaDepth)
        try:
          let stopDepth = vm.frames.len
          vm.push(handler)
          vm.push(tblVal)
          vm.push(key)
          vm.performCall(2)
          discard vm.run(stopDepth)
          vm.adjustResults(1)
          return vm.pop()
        finally:
          dec(vm.metaDepth)
      else:
        raise newException(LuaRuntimeError, "__index must be a table or function")

  if tblVal.kind == ltUserData:
    raise newException(LuaRuntimeError, "Attempt to index a userdata value")
  return newLuaNil()

proc luaIndexSet*(vm: var VM, tblVal, key, val: LuaValue) =
  if tblVal.kind == ltTable:
    if tblVal.tval.hasKey(key):
      if isLuaNil(val): tblVal.tval.del(key)
      else: tblVal.tval[key] = val
      return
  elif tblVal.kind != ltUserData:
    raise newException(LuaRuntimeError, "Attempt to index a " & $tblVal.kind & " value")

  if not isNil(tblVal.mt):
    if tblVal.mt.tval.hasKey(MTNEWINDEX):
      if vm.metaDepth >= MaxIndexDepth:
        raise newException(LuaRuntimeError, "'__newindex' chain too long; possible loop")
      let handler = tblVal.mt.tval[MTNEWINDEX]
      case handler.kind
      of ltTable:
        inc(vm.metaDepth)
        try:
          vm.luaIndexSet(handler, key, val)
        finally:
          dec(vm.metaDepth)
        return
      of ltClosure, ltNativeFn, ltNativeFnVM:
        inc(vm.metaDepth)
        try:
          let stopDepth = vm.frames.len
          vm.push(handler)
          vm.push(tblVal)
          vm.push(key)
          vm.push(val)
          vm.performCall(3)
          discard vm.run(stopDepth)
          vm.adjustResults(0)
        finally:
          dec(vm.metaDepth)
        return
      else:
        raise newException(LuaRuntimeError, "__newindex must be a table or function")

  if tblVal.kind == ltUserData:
    raise newException(LuaRuntimeError, "Attempt to index a userdata value")
  if not isLuaNil(val):
    tblVal.tval[key] = val

proc run*(vm: var VM, stopDepth: int = 0): int =
  inc(vm.nestedRunDepth)
  try:
    while vm.frames.len > stopDepth:
      var frame = vm.frames[^1]
      let instruction = OpCode(vm.readByte())

      vm.traceInstruction(frame.ip, instruction)
      case instruction
      of opPop:
        discard vm.pop()
      of opConstant:
        let constIndex = vm.readByte()
        let val = frame.chunk.constants[constIndex]
        vm.push(val)
      of opAdd:
        vm.binop(luaAdd)
      of opSubtract:
        vm.binop(luaSub)
      of opMultiply:
        vm.binop(luaMul)
      of opDivide:
        vm.binop(luaDiv)
      of opFloorDiv:
        vm.binop(luaFloorDiv)
      of opModulo:
        vm.binop(luaMod)
      of opExponent:
        vm.binop(luaPow)
      of opBitAnd:
        vm.binop(luaBitAnd)
      of opBitOr:
        vm.binop(luaBitOr)
      of opBitXor:
        vm.binop(luaBitXor)
      of opShl:
        vm.binop(luaShl)
      of opShr:
        vm.binop(luaShr)
      of opEquals:
        vm.binop(luaEquals)
      of opNotEqual:
        vm.binop(luaNotEquals)
      of opLess:
        vm.binop(luaLess)
      of opLessEqual:
        vm.binop(luaLessEqual)
      of opGreater:
        vm.binop(luaGreater)
      of opGreaterEqual:
        vm.binop(luaGreaterEqual)
      of opConcat:
        vm.luaConcat()
      of opNot:
        vm.push(not vm.pop())
      of opNegate:
        let r = vm.pop()
        if isInteger(r):
          vm.push(newLuaInteger(-r.ival))
        elif isNumber(r):
          vm.push(newLuaNumber(-numVal(r)))
        else:
          vm.push(vm.unaryFallback(MTNEG, "-", r))
      of opBitNot:
        let r = vm.pop()
        vm.push(vm.luaBitNot(r))
      of opLen:
        let r = vm.pop()
        if r.kind in {ltTable, ltUserData} and not isNil(r.mt) and
            r.mt.tval.hasKey(MTLEN):
          vm.push(vm.callMetamethod(r.mt.tval[MTLEN], 1, r)[0])
        elif isTable(r):
          vm.push(newLuaInteger(len(r.tval)))
        elif isString(r):
          vm.push(newLuaInteger(len(r.sval)))
        else:
          vm.push(vm.unaryFallback(MTLEN, "#", r))
      of opGetLocal:
        let slot = vm.readByte()
        vm.push(vm.stack[frame.slotBase + int(slot)])
      of opSetLocal:
        let slot = vm.readByte()
        let idx = frame.slotBase + int(slot)
        let val = vm.pop()
        if idx >= vm.stack.values.len:
          vm.stack.values.add(val) # first time this slot is created
        else:
          vm.stack[idx] = val
      of opMarkGlobalConst:
        let nameIdx = vm.readByte()
        let name = frame.chunk.constants[nameIdx]
        vm.globalConsts.incl(name.sval)
      of opNewTable:
        vm.stack.values.add(newLuaTable())
      of opGetTable:
        let key = vm.pop()
        let tblVal = vm.pop()
        vm.push(vm.luaIndexGet(tblVal, key))
      of opSetTable:
        let val = vm.pop()
        let key = vm.pop()
        let tblVal = vm.stack.values[^1]
        if tblVal.kind notin {ltTable, ltUserData}:
          raise newException(LuaRuntimeError, "Attempt to index a " &
              $tblVal.kind & " value")
        if key.kind == ltNil:
          raise newException(LuaRuntimeError, "Table index is nil")
        vm.luaIndexSet(tblVal, key, val)
      of opCall:
       let argCount = int(vm.readByte())
       vm.performCall(argCount)
       if vm.yieldRequested: return 0
      of opCallSpread:
       let prefixCount = int(vm.readByte())
       vm.performCall(prefixCount + vm.lastReturnCount)
       if vm.yieldRequested: return 0
      of opReturn:
        if vm.doReturn(frame, int(vm.readByte()), stopDepth): return 0
      of opReturnSpread:
        let prefixCount = int(vm.readByte())
        if vm.doReturn(frame, prefixCount + vm.lastReturnCount,
            stopDepth): return 0
      of opJumpIfFalse:
        let offset = vm.readShort()
        let conditionVal = vm.peek(0) # Look at top of stack WITHOUT popping it
        let isTruthy = not (conditionVal.kind == ltNil or (conditionVal.kind ==
            ltBool and conditionVal.bval == false))
        if not isTruthy:
          # If it's false, we take the jump!
          let frameCount = vm.frames.len
          vm.frames[frameCount - 1].ip += int(offset)
      of opJump:
        let offset = vm.readShort()
        let frameCount = vm.frames.len
        vm.frames[frameCount - 1].ip += int(offset)
      of opGetUpvalue:
       let slot = vm.readByte()
       let uv = frame.closure.upvalues[int(slot)]
       if uv.isOpen: vm.push(uv.stack[uv.location])
       else: vm.push(uv.closed)
      of opSetUpvalue:
       let slot = vm.readByte()
       let uv = frame.closure.upvalues[int(slot)]
       let val = vm.pop()
       if uv.isOpen: uv.stack.values[uv.location] = val
       else: uv.closed = val
      of opClosure:
        let constIdx = vm.readByte()
        # Retrieve the function prototype/template from the constant pool
        let protoVal = frame.chunk.constants[int(constIdx)]
        let protoClosure = protoVal.fnVal # Assumes ltClosure holds closureVal

        # Create a new runtime closure instance sharing the function prototype
        var runtimeClosure = LuaClosure(fn: protoClosure.fn, upvalues: @[])

        # Read the upvalue metadata emitted right after opClosure in the bytecode
        let upvalueCount = protoClosure.upvalues.len
        for i in 0 ..< upvalueCount:
          let isLocal = vm.readByte()
          let index = vm.readByte()

          if isLocal == 1:
            # Capture a local variable from the current stack frame
            let location = frame.slotBase + int(index)
            runtimeClosure.upvalues.add(vm.captureUpvalue(location))
          else:
            # Pass down an existing upvalue from the enclosing closure
            runtimeClosure.upvalues.add(frame.closure.upvalues[int(index)])

        vm.push(wrapLuaClosure(runtimeClosure))
      of opCloseUpvalue:
        vm.closeUpvalues(vm.stack.values.high)
        discard vm.pop()
      of opCloseValue:
        let slot = int(vm.readByte())
        let idx = frame.slotBase + slot
        let val = vm.stack[idx]

        if val.kind in {ltTable, ltUserData} and not isNil(val.mt):
          if val.mt.tval.hasKey(MTCLOSE):
            let handler = val.mt.tval[MTCLOSE]
            if handler.kind in {ltClosure, ltNativeFn, ltNativeFnVM}:
              let stopDepth = vm.frames.len
              vm.stack.values.add(handler)
              vm.stack.values.add(val)
              vm.stack.values.add(newLuaNil())
              vm.performCall(2)
              discard vm.run(stopDepth)
              vm.lastReturnCount = 0
        vm.stack.values.setLen(idx)
      of opVararg:
        vm.push(frame.vararg)
      of opSpreadVararg:
        let startIdx = int(vm.readByte())
        let tbl = vm.peek(0)
        if tbl.kind != ltTable:
          raise newException(LuaRuntimeError, "opSpreadVararg: expected table under construction")
        let count = frame.vararg.tval.len
        for i in 1 .. count:
          let val = frame.vararg.tval[newLuaNumber(float64(i))]
          tbl.tval[newLuaNumber(float64(startIdx + i - 1))] = val
      of opSpreadVarargValues:
        let count = frame.vararg.tval.len
        for i in 1 .. count:
          vm.push(frame.vararg.tval[newLuaNumber(float64(i))])
        vm.lastReturnCount = count
      of opLoop:
        let offset = vm.readShort()
        frame.ip -= int(offset)
      of opAdjust:
        vm.adjustResults(int(vm.readByte()))
      of opGetMethod:
        let nameIdx = vm.readByte()
        let nameVal = frame.chunk.constants[nameIdx]
        let receiver = vm.pop()
        let methodFn = vm.luaIndexGet(receiver, nameVal)
        vm.push(methodFn)
        vm.push(receiver)
  finally:
    dec(vm.nestedRunDepth)
