from strutils import join
import std/[tables,sugar,sequtils]
import lvalue,lerror

proc allKeysNumbers(v:LuaTable): bool = 
  let s = collect(newSeq):
    for k in v.keys:
      k
  return all(s,proc(x:LuaValue): bool = isNumber(x))

proc allValuesOfKind(v:LuaTable,kinds:set[LuaKind]): bool =
  let s = collect(newSeq):
    for v in v.values:
      v
  return all(s,proc(x:LuaValue): bool = x.kind in kinds)

proc tableToSeq(v:LuaTable): seq[LuaValue] =
  for val in v.values:
    result.add val

proc luaToStr(v: LuaValue): string =
  case v.kind
  of ltString: v.sval
  of ltNumber: $v.nval
  else: raise newException(LuaRuntimeError, "invalid value (" & $v.kind & ") in table for 'concat'")

proc tableConcat(args: varargs[LuaValue]): LuaValue =
  if len(args) < 1 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "Cannot use concat on a non-table value.")
  let tab = args[0]

  var sep = ""
  if len(args) >= 2:
    if not isString(args[1]) and not isNumber(args[1]):
      raise newException(LuaRuntimeError, "Bad argument for sep: string or number expected, but got: " & $args[1].kind)
    sep = luaToStr(args[1])

  var start = 1
  var endPos = len(tab.tval)
  if len(args) >= 3 and isNumber(args[2]): start = args[2].nval.int
  if len(args) >= 4 and isNumber(args[3]): endPos = args[3].nval.int

  var items: seq[string] = @[]
  for i in start .. endPos:
    let key = newLuaNumber(float64(i))
    if not tab.tval.hasKey(key):
      raise newException(LuaRuntimeError, "invalid value (nil) at index " & $i & " in table for 'concat'")
    items.add(luaToStr(tab.tval[key]))

  return newLuaString(items.join(sep))

proc tableInsert(args: varargs[LuaValue]): LuaValue =
  if len(args) < 2 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "Can not use insert on a non-table value")
  let tab = args[0]
  let n = len(tab.tval)

  if len(args) == 2:
    tab.tval[newLuaNumber(float64(n + 1))] = args[1]
  elif len(args) == 3:
    if not isNumber(args[1]):
      raise newException(LuaRuntimeError, "Bad argument #2 to 'insert': number expected")
    let pos = args[1].nval.int
    for i in countdown(n, pos):
      tab.tval[newLuaNumber(float64(i + 1))] = tab.tval[newLuaNumber(float64(i))]
    tab.tval[newLuaNumber(float64(pos))] = args[2]
  else:
    raise newException(LuaRuntimeError, "Wrong number of arguments to insert")

  return newLuaNil()

proc tableMove(args:varargs[LuaValue]): LuaValue = discard

proc tablePack(args:varargs[LuaValue]): LuaValue =
  result = newLuaTable()
  for i, v in args:
    result.tval[newLuaNumber(float64(i + 1))] = v
  result.tval[newLuaString("n")] = newLuaNumber(float64(args.len))

proc tableRemove(args:varargs[LuaValue]): LuaValue = discard

proc tableSort(args:varargs[LuaValue]): LuaValue = discard

proc tableUnpack(args:varargs[LuaValue]): LuaValue = discard

proc newTabLib*(): LuaValue = 
  result = newLuaTable()
  result.tval[newLuaString("pack")] = newNimFn(tablePack)
  result.tval[newLuaString("insert")] = newNimFn(tableInsert)
  result.tval[newLuaString("concat")] = newNimFn(tableConcat)

proc luaIndexGet*(tblVal, key: LuaValue): LuaValue =
  if tblVal.kind != ltTable:
    raise newException(LuaRuntimeError, "Attempt to index a " & $tblVal.kind & " value")

  if tblVal.tval.hasKey(key):
    return tblVal.tval[key]

  if not isNil(tblVal.mt):
    let idxKey = newLuaString("__index")
    if tblVal.mt.tval.hasKey(idxKey):
      let handler = tblVal.mt.tval[idxKey]
      case handler.kind
      of ltTable: return luaIndexGet(handler, key)   # keep following the chain
      of ltClosure, ltNativeFn:
        raise newException(LuaRuntimeError, "__index as a function is not yet supported")
      else:
        raise newException(LuaRuntimeError, "__index must be a table or function")

  return newLuaNil()

proc luaIndexSet*(tblVal, key, val: LuaValue) =
  if tblVal.tval.hasKey(key):
    tblVal.tval[key] = val
    return

  if not isNil(tblVal.mt):
    let nidxKey = newLuaString("__newindex")
    if tblVal.mt.tval.hasKey(nidxKey):
      let handler = tblVal.mt.tval[nidxKey]
      case handler.kind
      of ltTable:
        luaIndexSet(handler, key, val)   # redo the assignment on the __newindex table
        return
      of ltClosure, ltNativeFn:
        raise newException(LuaRuntimeError, "__newindex as a function is not yet supported")
      else:
        raise newException(LuaRuntimeError, "__newindex must be a table or function")

  tblVal.tval[key] = val