import std/tables
import ../ltypes, ../lvalue, ../lerror

proc luaSetAdd(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 2:
    raise newException(LuaRuntimeError, "bad arguments to 'add' (set and value expected)")
  if isLuaNil(args[1]):
    raise newException(LuaRuntimeError, "cannot add nil to a set")
  if not isSet(args[0]):
    raise newException(LuaRuntimeError,"bad argument #1 to 'add' (set exepcted)")
  args[0].tval[args[1]] = newLuaBool(true)
  return @[args[0]]   # returns self, so s:add(1):add(2):add(3) chains

proc luaSetRemove(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 2:
    raise newException(LuaRuntimeError, "bad arguments to 'remove' (set and value expected)")
  if not isSet(args[0]):
    raise newException(LuaRuntimeError,"bad argument #1 to 'remove' (set exepcted)")
  args[0].tval.del(args[1])
  return @[args[0]]

proc luaSetContains(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 2:
    raise newException(LuaRuntimeError, "bad arguments to 'contains' (set and value expected)")
  if not isSet(args[0]):
    raise newException(LuaRuntimeError,"bad argument #1 to 'contains' (set exepcted)")
  return @[newLuaBool(args[0].tval.hasKey(args[1]))]

proc luaSetUnion(args: varargs[LuaValue]): seq[LuaValue] =
  if not isSet(args[0]):
    raise newException(LuaRuntimeError,"bad argument #1 to '|' (set exepcted)")
  if not isSet(args[1]):
    raise newException(LuaRuntimeError,"bad argument #2 to '|' (set exepcted)")
  let s = newLuaTable()
  s.mt = args[0].mt
  for k in args[0].tval.keys: s.tval[k] = newLuaBool(true)
  for k in args[1].tval.keys: s.tval[k] = newLuaBool(true)
  return @[s]

proc luaSetIntersect(args: varargs[LuaValue]): seq[LuaValue] =
  if not isSet(args[0]):
    raise newException(LuaRuntimeError,"bad argument #1 to '&' (set exepcted)")
  if not isSet(args[1]):
    raise newException(LuaRuntimeError,"bad argument #2 to '&' (set exepcted)")
  let s = newLuaTable()
  s.mt = args[0].mt
  for k in args[0].tval.keys:
    if args[1].tval.hasKey(k): s.tval[k] = newLuaBool(true)
  return @[s]

proc luaSetDifference(args: varargs[LuaValue]): seq[LuaValue] =
  if not isSet(args[0]):
    raise newException(LuaRuntimeError,"bad argument #1 to '-' (set exepcted)")
  if not isSet(args[1]):
    raise newException(LuaRuntimeError,"bad argument #2 to '-' (set exepcted)")
  let s = newLuaTable()
  s.mt = args[0].mt
  for k in args[0].tval.keys:
    if not args[1].tval.hasKey(k): s.tval[k] = newLuaBool(true)
  return @[s]

proc luaSetSymDiff(args: varargs[LuaValue]): seq[LuaValue] =
  if not isSet(args[0]):
    raise newException(LuaRuntimeError,"bad argument #1 to '~' (set exepcted)")
  if not isSet(args[1]):
    raise newException(LuaRuntimeError,"bad argument #2 to '~' (set exepcted)")
  let s = newLuaTable()
  s.mt = args[0].mt
  for k in args[0].tval.keys:
    if not args[1].tval.hasKey(k): s.tval[k] = newLuaBool(true)
  for k in args[1].tval.keys:
    if not args[0].tval.hasKey(k): s.tval[k] = newLuaBool(true)
  return @[s]

proc setIsSubset(l, r: LuaValue): bool =
  for k in l.tval.keys:
    if not r.tval.hasKey(k): return false
  return true

proc luaSetLe(args: varargs[LuaValue]): seq[LuaValue] =
  if not isSet(args[0]):
    raise newException(LuaRuntimeError,"bad argument #1 to '<=' (set exepcted)")
  if not isSet(args[1]):
    raise newException(LuaRuntimeError,"bad argument #2 to '<=' (set exepcted)")
  return @[newLuaBool(setIsSubset(args[0], args[1]))]

proc luaSetLt(args: varargs[LuaValue]): seq[LuaValue] =
  if not isSet(args[0]):
    raise newException(LuaRuntimeError,"bad argument #1 to '<' (set exepcted)")
  if not isSet(args[1]):
    raise newException(LuaRuntimeError,"bad argument #2 to '<' (set exepcted)")
  return @[newLuaBool(setIsSubset(args[0], args[1]) and args[0].tval.len != args[1].tval.len)]

proc luaSetEq(args: varargs[LuaValue]): seq[LuaValue] =
  if not isSet(args[0]):
    raise newException(LuaRuntimeError,"bad argument #1 to '==' (set exepcted)")
  if not isSet(args[1]):
    raise newException(LuaRuntimeError,"bad argument #2 to '==' (set exepcted)")
  if args[0].tval.len != args[1].tval.len: return @[newLuaBool(false)]
  return @[newLuaBool(setIsSubset(args[0], args[1]))]

proc newSetLib*(): LuaValue =
  let SetMethods = newLuaTable()
  SetMethods.tval[newLuaString("add")] = newNimFn(luaSetAdd)
  SetMethods.tval[newLuaString("remove")] = newNimFn(luaSetRemove)
  SetMethods.tval[newLuaString("contains")] = newNimFn(luaSetContains)

  let setMT = newLuaTable()
  setMT.tval[MTINDEX] = SetMethods
  setMT.tval[MTBOR] = newNimFn(luaSetUnion)
  setMT.tval[MTBAND] = newNimFn(luaSetIntersect)
  setMT.tval[MTSUB] = newNimFn(luaSetDifference)
  setMT.tval[MTBXOR] = newNimFn(luaSetSymDiff)
  setMT.tval[MTEQ] = newNimFn(luaSetEq)
  setMT.tval[MTLE] = newNimFn(luaSetLe)
  setMT.tval[MTLT] = newNimFn(luaSetLt)
  setMT.tval[MTTYPE] = newLuaString("set")

  let luaSetNew = proc(args: varargs[LuaValue]): seq[LuaValue] =
    let s = newLuaTable()
    s.mt = setMT
    for v in args:
      if v.kind == ltNil:
        raise newException(LuaRuntimeError, "cannot add nil to a set")
      s.tval[v] = newLuaBool(true)
    return @[s]

  result = newLuaTable()
  result.tval[newLuaString("new")] = newNimFn(luaSetNew)