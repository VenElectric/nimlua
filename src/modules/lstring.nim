import std/[tables,strutils,sugar]
import ../lvalue,../ltypes,../lerror,../lutil
from algorithm import reverse

const REPEATLIMIT = 4 * 1024 * 1024

proc resolveByteIndex(pos: int64, len: int): int =
  # Converts a Lua-style 1-based (or negative, counting from the end)
  # position into a clamped, 0-based Nim index.
  var i = pos
  if i < 0: i = int64(len) + i + 1
  if i < 1: i = 1
  if i > int64(len): i = int64(len)
  return int(i) - 1

proc luaStrByte(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 1 or len(args) > 3:
    raise newException(LuaRuntimeError, moduleArgNumErrorFmt("byte", "1, 2, or 3"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(1, "byte", "string"))
  let str = getString(args[0])

  if str.len == 0:
    return @[]   # matches real Lua: string.byte("") returns nothing at all

  let sPos = if len(args) >= 2: intVal(args[1]) else: 1'i64
  let ePos = if len(args) >= 3: intVal(args[2]) else: sPos

  let startIdx = resolveByteIndex(sPos, str.len)
  let endIdx = resolveByteIndex(ePos, str.len)

  result = @[]
  if startIdx > endIdx: return result   # an empty range is valid, not an error
  for i in countup(startIdx, endIdx):
    result.add(newLuaInteger(int64(str[i])))

proc luaStrChar(args: varargs[LuaValue]): seq[LuaValue] = 
  var s: string
  for i, a in args:
    if not isNumber(a):
      raise newException(LuaRuntimeError, moduleArgKindErrorFmt(i + 1, "char", "number"))
    let code = intVal(a)
    if code < 0 or code > 255:
      raise newException(LuaRuntimeError, "bad argument #" & $(i + 1) & " to 'char' (value out of range)")
    s.add(char(code))
  return @[newLuaString(s)]

proc luaStrLen(args: varargs[LuaValue]): seq[LuaValue] =  
  if len(args) != 1:
    raise newException(LuaRuntimeError,moduleArgNumErrorFmt("len","1"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError,moduleArgKindErrorFmt(1,"len","string"))
  return @[newLuaInteger(len(getString(args[0])))]

proc luaStrLower(args: varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,moduleArgNumErrorFmt("lower","1"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError,moduleArgKindErrorFmt(1,"lower","string"))
  return @[newLuaString(toLowerAscii(getString(args[0])))]

proc luaStrRep(args: varargs[LuaValue]): seq[LuaValue] = 
  if len(args) < 2 or len(args) > 3:
    raise newException(LuaRuntimeError, moduleArgNumErrorFmt("rep", "2 or 3"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(1, "rep", "string"))
  if not isNumber(args[1]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(2, "rep", "number"))

  let str = getString(args[0])
  let times = int(intVal(args[1]))
  if times <= 0:
    return @[newLuaString("")]

  var sep = ""
  if len(args) == 3 and isString(args[2]):
    sep = getString(args[2])

  # Check BEFORE multiplying -- times * str.len could itself overflow for a
  # deliberately huge `times`, but division is always safe regardless of size.
  if str.len > 0 and times > REPEATLIMIT div str.len:
    raise newException(LuaRuntimeError, "resulting string too large")

  let strTotal = str.len * times          # safe now: bounded by the check above
  let sepTotal = sep.len * (times - 1)    # (times - 1) separators between pieces
  if strTotal + sepTotal > REPEATLIMIT:
    raise newException(LuaRuntimeError, "resulting string too large")

  var s = newStringOfCap(strTotal + sepTotal)
  for i in 1 .. times:
    if i > 1: s.add(sep)
    s.add(str)
  return @[newLuaString(s)]

proc luaStrReverse(args: varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,moduleArgNumErrorFmt("reverse","1"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError,moduleArgKindErrorFmt(1,"reverse","string"))
  var str = getString(args[0])
  reverse(str)
  return @[newLuaString(str)]

proc luaStrUpper(args: varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,moduleArgNumErrorFmt("upper","1"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError,moduleArgKindErrorFmt(1,"upper","string"))
  return @[newLuaString(toUpperAscii(getString(args[0])))]  

proc resolveFindInit(initArg: int64, len: int): int =
  # returns a 0-based Nim start index, or -1 meaning "no match is possible"
  var i = initArg
  if i < 0:
    i = int64(len) + i + 1
    if i < 1: i = 1
  elif i == 0:
    i = 1
  if i > int64(len) + 1:
    return -1
  return int(i) - 1

proc luaStrFind*(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 2:
    raise newException(LuaRuntimeError, moduleArgNumErrorFmt("find", "at least 2"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(1, "find", "string"))
  if not isString(args[1]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(2, "find", "string"))

  let s = getString(args[0])
  let pat = getString(args[1])
  let initArg = if len(args) >= 3 and isNumber(args[2]): intVal(args[2]) else: 1'i64
  let plain = true #len(args) >= 4 and truthy(args[3])

  let startIdx = resolveFindInit(initArg, s.len)
  if startIdx == -1:
    return @[newLuaNil()]

  if not plain:
    raise newException(LuaRuntimeError, "pattern matching is not yet supported in 'find'")

  let foundIdx = s.find(pat, startIdx)   # std/strutils: -1 if not found
  if foundIdx == -1:
    return @[newLuaNil()]
  return @[newLuaInteger(foundIdx + 1), newLuaInteger(foundIdx + pat.len)]

proc newStringLib*(): LuaValue = 
  result = newLuaTable()
  result.tval[newLuaString("byte")] = newNimFn(luaStrByte)
  result.tval[newLuaString("char")] = newNimFn(luaStrChar)
  result.tval[newLuaString("len")] = newNimFn(luaStrLen)
  result.tval[newLuaString("lower")] = newNimFn(luaStrLower)
  result.tval[newLuaString("rep")] = newNimFn(luaStrRep)
  result.tval[newLuaString("reverse")] = newNimFn(luaStrReverse)
  result.tval[newLuaString("upper")] = newNimFn(luaStrUpper)
  result.tval[newLuaString("find")] = newNimFn(luaStrFind)
  


