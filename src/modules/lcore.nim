import std/[tables, sugar, streams]
from strutils import parseFloat, parseInt
import ../ltypes
import ../lvalue
import ../lutil
import ../lerror
import ../lvm

proc luaRawGet*(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) != 2:
    raise newException(LuaRuntimeError, "Incorrect number of arguments to 'rawget'. (table and key expected)")
  let tab = args[0]
  let index = args[1]
  if not isTable(tab):
    raise newException(LuaRuntimeError, "Bad argument #1 to 'rawget'. (table expected)")
  return @[tab.tval.getOrDefault(index, newLuaNil())]

proc luaRawSet*(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) != 3:
    raise newException(LuaRuntimeError, "Incorrect number of arguments to 'rawset'. (table, key, and value expected)")
  let tab = args[0]
  let index = args[1]
  let value = args[2]
  if not isTable(tab):
    raise newException(LuaRuntimeError, "Bad argument #1 to 'rawset'. (table expected)")
  if index.kind == ltNil:
    raise newException(LuaRuntimeError, "table index is nil")
  if isLuaNil(value):
    tab.tval.del(index)
  else:
    tab.tval[index] = value
  return @[tab]

proc luaRawEqual*(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) != 2:
    raise newException(LuaRuntimeError, "Incorrect number of arguments to 'rawEqual'. Two values expected.")
  return @[newLuaBool(args[0] == args[1])]

proc luaRawLen*(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) != 1:
    raise newException(LuaRuntimeError, "Incorrect number of arguments to 'rawlen'. One value expected.")
  let v = args[0]
  result = @[]
  if isString(v): result.add(newLuaInteger(len(v.sval)))
  elif isTable(v): result.add(newLuaInteger(len(v.tval)))
  else:
    raise newException(LuaRuntimeError, "Bad argument #1 to 'rawlen'. (table or string expected)")

proc luaRawType*(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) != 1:
    raise newException(LuaRuntimeError, "Incorrect number of arguments to 'rawlen'. One value expected.")
  let v = args[0]
  result = @[newLuaString($v.kind)]

proc luaSetMetatable*(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 1 or not (isTable(args[0]) or isUserData(args[0])):
    raise newException(LuaRuntimeError, "Bad argument #1 to 'setmetatable'. (table expected)")
  let t = args[0]
  if len(args) < 2 or args[1].kind == ltNil:
    t.mt = nil
  elif args[1].kind == ltTable:
    t.mt = args[1]
  else:
    raise newException(LuaRuntimeError, "Bad argument #2 to 'setmetatable' (nil or table expected)")
  return @[t]

proc luaGetMetatable*(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 1 or not (isTable(args[0]) or isUserData(args[0])):
    raise newException(LuaRuntimeError, "Bad argument #1 to 'getmetatable'. (table expected)")
  if isNil(args[0].mt): return @[newLuaNil()]
  return @[args[0].mt]

proc luaPrint*(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  for i, arg in args:
    vm.output.write($arg)
    if i < args.high: vm.output.write("\t")
  vm.output.write("\n")
  return @[newLuaNil()]

proc luaNext*(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 1 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'next' (table expected)")

  let tbl = args[0]
  let key = if args.len > 1: args[1] else: newLuaNil()

  if key.kind == ltNil:
    for k, v in tbl.tval.pairs:
      return @[k, v] # Return BOTH key and value
    return @[newLuaNil()]

  var foundCurrent = false
  for k, v in tbl.tval.pairs:
    if foundCurrent:
      return @[k, v]

    # Using the overloaded `==` from lvalue.nim[cite: 33]
    if k == key:
      foundCurrent = true

  return @[newLuaNil()]

proc luaPairs*(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 1 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'pairs' (table expected)")
  let t = args[0]
  if not isNil(t.mt) and t.mt.tval.hasKey(MTPAIRS):
    let handler = t.mt.tval[MTPAIRS]
    return vm.callMetamethod(handler, 3, t) # __pairs must produce (iterator, state, control)
  return @[newNimFn(luaNext), t, newLuaNil()]


proc luaINext(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 2 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "inext expected a table and an index")

  let tbl = args[0]
  let currentIdx = args[1].nval
  let nextIdx = currentIdx + 1.0
  let nextKey = newLuaNumber(nextIdx)

  if tbl.tval.hasKey(nextKey):
    return @[nextKey, tbl.tval[nextKey]]

  return @[newLuaNil()]

proc luaIPairs*(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 1 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'ipairs' (table expected)")

  # Return the iterator, the state (the table), and the initial control var (0.0)
  return @[newNimFn(luaINext), args[0], newLuaNumber(0.0)]



proc luaToNumber*(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len == 0:
    return @[newLuaNil()]

  var base = 10
  if args.len >= 2 and not isLuaNil(args[1]):
    if isNumber(args[1]):
      base = args[1].nval.int64
    elif isString(args[1]):
      try:
        base = parseInt(args[1].sval)
      except ValueError:
        raise newException(ValueError, "bad argument #2 to 'tonumber' (number expected)")

  return @[luaUToNumber(args[0], base)]

proc luaToString*(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len == 0:
    raise newException(LuaRuntimeError, "Invalid # of arguments to 'tostring'. Expected one argument.")
  return @[newLuaString($args[0])]

proc luaType*(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len == 0:
    raise newException(LuaRuntimeError, "Invalid # of arguments to 'type'. Expected one argument.")
  let v = args[0]
  if not isNil(v.mt) and hasMetaKey(v, MTTYPE) and isString(v.mt.tval[MTTYPE]):
    return @[v.mt.tval[MTTYPE]]
  return @[newLuaString($v.kind)]

proc luaSelect*(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 2:
    raise newException(LuaRuntimeError, "Invalid # of arguments to 'select'. Expected at least two arguments.")

  let arg1 = args[0]
  if not isNumber(arg1) and not isString(arg1):
    raise newException(LuaRuntimeError, "bad argument #1 to 'select' (number expected)")

  let n = arg1.nval.int64
  if n == 0:
    raise newException(LuaRuntimeError, "bad argument #1 to 'select' (number expected)")

  result = collect(newSeq):
    for i in countup(1, args.len-1):
      args[i]

proc luaError*(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  let msgVal = if args.len >= 1: args[0] else: newLuaNil()
  vm.lastError = msgVal
  let msgStr = if msgVal.kind == ltString: msgVal.sval else: $msgVal
  raise newException(LuaRuntimeError, msgStr)

proc luaAssert*(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 1:
    raise newException(LuaRuntimeError, "bad argument #1 to 'assert' (value expected)")
  if not truthy(args[0]):
    let msgVal = if args.len >= 2: args[1] else: newLuaString("assertion failed!")
    vm.lastError = msgVal
    let msgStr = if msgVal.kind == ltString: msgVal.sval else: $msgVal
    raise newException(LuaRuntimeError, msgStr)
  result = @[]
  for a in args: result.add(a)

proc luaPCall*(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 1:
    raise newException(LuaRuntimeError, "bad argument #1 to 'pcall' (value expected)")
  let fn = args[0]
  let callArgs = if args.len > 1: args[1..^1] else: @[]
  let stopDepth = vm.frames.len
  let stackBase = vm.stack.len
  let savedError = vm.lastError # <-- 1. snapshot whatever was ambient before THIS pcall
  try: # <-- 2. new outer try, wrapping everything below
    vm.lastError = nil
    try:
      vm.push(fn)
      for a in callArgs: vm.push(a)
      vm.performCall(callArgs.len)
      discard vm.run(stopDepth)
      let n = vm.lastReturnCount
      var results = newSeq[LuaValue](n)
      for i in countdown(n - 1, 0): results[i] = vm.pop()
      result = @[newLuaBool(true)]
      result.add(results)
    except LuaRuntimeError as e:
      vm.frames.setLen(stopDepth)
      vm.stack.setLen(stackBase)
      let errVal = if vm.lastError != nil: vm.lastError else: newLuaString(e.msg)
      result = @[newLuaBool(false), errVal]
  finally:
    vm.lastError = savedError # <-- 3. always restore, success or failure

proc luaXPCall*(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 2:
    raise newException(LuaRuntimeError, "bad argument #2 to 'xpcall' (value expected)")
  let fn = args[0]
  let handler = args[1]
  let callArgs = if args.len > 2: args[2..^1] else: @[]
  let stopDepth = vm.frames.len
  let stackBase = vm.stack.len
  let savedError = vm.lastError
  try:
    vm.lastError = nil
    try:
      vm.push(fn)
      for a in callArgs: vm.push(a)
      vm.performCall(callArgs.len)
      discard vm.run(stopDepth)
      let n = vm.lastReturnCount
      var results = newSeq[LuaValue](n)
      for i in countdown(n - 1, 0): results[i] = vm.pop()
      result = @[newLuaBool(true)]
      result.add(results)
    except LuaRuntimeError as e:
      vm.frames.setLen(stopDepth)
      vm.stack.setLen(stackBase)
      let errVal = if not isNil(vm.lastError): vm.lastError else: newLuaString(e.msg)
      let handlerResults = vm.callMetamethod(handler, 1, errVal)
      result = @[newLuaBool(false), handlerResults[0]]
  finally:
    vm.lastError = savedError

proc registerGC*(vm: var VM) =
  let GCOption = newLuaEnum(["collect", "count", "stop", "restart"])

  let luaCollectGarbage = proc(args: varargs[LuaValue]): seq[LuaValue] =
    var optName = "collect" # collectgarbage() with no args defaults to "collect", matching real Lua
    if args.len >= 1:
      if not isInteger(args[0]) or not GCOption.tval.hasKey(args[0]):
        raise newException(LuaRuntimeError, "bad argument #1 to 'collectgarbage' (GCOption.xxx expected)")
      optName = GCOption.tval[args[0]].sval # reverse lookup: int -> name string

    when defined(gcOrc):
      case optName
      of "collect":
        GC_fullCollect()
        return @[newLuaInteger(0)]
      of "count":
        return @[newLuaNumber(float64(getOccupiedMem()) / 1024.0)]
      of "stop":
        GC_disableOrc()
        return @[newLuaInteger(0)]
      of "restart":
        GC_enableOrc()
        return @[newLuaInteger(0)]
      else:
        raise newException(LuaRuntimeError, "collectgarbage option not supported")
    else:
      raise newException(LuaRuntimeError, "collectgarbage is not supported under this build's memory manager")

  vm.globals["GCOption"] = GCOption
  vm.globals["collectgarbage"] = newNimFn(luaCollectGarbage)

proc newTypeKindLib*(vm: var VM) =
  let backing = newLuaTable() # hidden -- never exposed to Lua directly

  let typeKindIndex = proc(args: varargs[LuaValue]): seq[LuaValue] =
    let key = args[1]
    if backing.tval.hasKey(key): return @[backing.tval[key]]
    return @[newLuaNil()]

  let typeKindNewindex = proc(args: varargs[LuaValue]): seq[LuaValue] =
    let key = args[1]
    if backing.tval.hasKey(key):
      raise newException(LuaRuntimeError, "type '" & $key & "' is already registered")
    backing.tval[key] = args[2]
    return @[]

  let TypeKind = newLuaTable()
  let mt = newLuaTable()
  mt.tval[MTINDEX] = newNimFn(typeKindIndex)
  mt.tval[MTNEWINDEX] = newNimFn(typeKindNewindex)
  TypeKind.mt = mt

  vm.globals["TypeKind"] = TypeKind
