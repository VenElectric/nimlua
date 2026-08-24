import std/[tables,unicode]
import ../ltypes,../lvalue,../lerror,../lutil


proc getStringArg(args: varargs[LuaValue], fnName,numArgs: string): string =
  # Argument count/type problems are still programmer errors -- raise, unchanged.
  if len(args) == 0:
    raise newException(LuaRuntimeError, moduleArgNumErrorFmt(fnName, numArgs))
  if not isString(args[0]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(1, fnName, "string"))
  return getString(args[0])

proc luaUniChar(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) == 0:
    raise newException(LuaRuntimeError, moduleArgNumErrorFmt("char", "1 or more"))
  var s: string
  for i, arg in args:
    if not isNumber(arg):
      raise newException(LuaRuntimeError, moduleArgKindErrorFmt(i + 1, "char", "number"))
    let code = intVal(arg)
    if code < 0 or code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF):
      raise newException(LuaRuntimeError, "bad argument #" & $(i + 1) & " to 'char' (value out of range)")
    s.add(Rune(code))
  return @[newLuaString(s)]

proc uPosRelAt(pos: int64, len: int): int64 =
  if pos >= 0: return pos
  elif (-pos) > int64(len): return 0
  else: return int64(len) + pos + 1

proc luaUniLen(args: varargs[LuaValue]): seq[LuaValue] =
  let s = getStringArg(args, "len","1 to 3")
  let slen = s.len

  var iArg: int64 = 1
  if len(args) >= 2:
    if not isNumber(args[1]):
      raise newException(LuaRuntimeError, moduleArgKindErrorFmt(2, "len", "number"))
    iArg = intVal(args[1])
  var jArg: int64 = -1
  if len(args) >= 3:
    if not isNumber(args[2]):
      raise newException(LuaRuntimeError, moduleArgKindErrorFmt(3, "len", "number"))
    jArg = intVal(args[2])

  let posi = uPosRelAt(iArg, slen)
  let posj = uPosRelAt(jArg, slen)
  if posi < 1 or posi > int64(slen) + 1:
    raise newException(LuaRuntimeError, "bad argument #2 to 'len' (initial position out of bounds)")
  if posj > int64(slen):
    raise newException(LuaRuntimeError, "bad argument #3 to 'len' (final position out of bounds)")

  let badAt = validateUtf8(s)
  if badAt != -1:
    return @[newLuaNil(), newLuaInteger(badAt + 1)]

  var byteIdx = int(posi) - 1
  let byteEnd = int(posj) - 1
  var count = 0
  while byteIdx <= byteEnd:
    byteIdx += runeLenAt(s, byteIdx)
    inc count
  return @[newLuaInteger(count), newLuaNil()]

proc luaUniValid(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) == 0:
    raise newException(LuaRuntimeError, moduleArgNumErrorFmt("valid", "1"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(1, "valid", "string"))

  let badAt = validateUtf8(getString(args[0]))
  if badAt == -1:
    return @[newLuaNil()]
  return @[newLuaInteger(badAt + 1)]

proc luaUniUpper(args: varargs[LuaValue]): seq[LuaValue] =
  let s = getStringArg(args, "upper","1")
  let badAt = validateUtf8(s)
  if badAt != -1:
    return @[newLuaNil(), newLuaInteger(badAt + 1)]
  return @[newLuaString(toUpper(s)), newLuaNil()]

proc luaUniLower(args: varargs[LuaValue]): seq[LuaValue] =
  let s = getStringArg(args, "lower","1")
  let badAt = validateUtf8(s)
  if badAt != -1:
    return @[newLuaNil(), newLuaInteger(badAt + 1)]
  return @[newLuaString(toLower(s)), newLuaNil()]

proc luaUniReverse(args: varargs[LuaValue]): seq[LuaValue] =
  let s = getStringArg(args, "reverse","1")
  let badAt = validateUtf8(s)
  if badAt != -1:
    return @[newLuaNil(), newLuaInteger(badAt + 1)]
  return @[newLuaString(reversed(s)), newLuaNil()]

proc luaUniCodepoint(args: varargs[LuaValue]): seq[LuaValue] =
  let s = getStringArg(args, "codepoint","1 to 3")
  let slen = s.len

  var iArg: int64 = 1
  if len(args) >= 2:
    if not isNumber(args[1]):
      raise newException(LuaRuntimeError, moduleArgKindErrorFmt(2, "codepoint", "number"))
    iArg = intVal(args[1])

  let posi = uPosRelAt(iArg, slen)
  if posi < 1 or posi > int64(slen):
    raise newException(LuaRuntimeError, "bad argument #2 to 'codepoint' (out of bounds)")

  var jArg: int64 = posi   # default j = the ALREADY-RESOLVED i, per real Lua's own source
  if len(args) >= 3:
    if not isNumber(args[2]):
      raise newException(LuaRuntimeError, moduleArgKindErrorFmt(3, "codepoint", "number"))
    jArg = intVal(args[2])

  let posj = uPosRelAt(jArg, slen)
  if posj > int64(slen):
    raise newException(LuaRuntimeError, "bad argument #3 to 'codepoint' (out of bounds)")

  let badAt = validateUtf8(s)
  if badAt != -1:
    return @[newLuaNil(), newLuaInteger(badAt + 1)]

  result = @[]
  var byteIdx = int(posi) - 1
  let byteEnd = int(posj) - 1
  while byteIdx <= byteEnd:
    var r: Rune
    fastRuneAt(s, byteIdx, r)   # decodes into r AND advances byteIdx past this character
    result.add(newLuaInteger(int(r)))

proc luaUniSub(args: varargs[LuaValue]): seq[LuaValue] =
  let s = getStringArg(args, "sub","1 to 3")

  let badAt = validateUtf8(s)
  if badAt != -1:
    return @[newLuaNil(), newLuaInteger(badAt + 1)]

  let runes = toRunes(s)
  let rlen = runes.len

  var iArg: int64 = 1
  if len(args) >= 2:
    if not isNumber(args[1]):
      raise newException(LuaRuntimeError, moduleArgKindErrorFmt(2, "sub", "number"))
    iArg = intVal(args[1])
  var jArg: int64 = -1
  if len(args) >= 3:
    if not isNumber(args[2]):
      raise newException(LuaRuntimeError, moduleArgKindErrorFmt(3, "sub", "number"))
    jArg = intVal(args[2])

  # Same negative-position resolution as len/codepoint (uPosRelAt), but
  # against the CHARACTER count, then CLAMPED rather than bounds-checked --
  # matching string.sub's own forgiving contract exactly.
  var i = uPosRelAt(iArg, rlen)
  if i < 1: i = 1

  var j = uPosRelAt(jArg, rlen)
  if j > int64(rlen): j = int64(rlen)

  if i > j:
    return @[newLuaString(""), newLuaNil()]

  var resultStr = ""
  for idx in (int(i) - 1) .. (int(j) - 1):
    resultStr.add($runes[idx])

  return @[newLuaString(resultStr), newLuaNil()]

proc isContinuationByte(s: string, i: int): bool =
  (uint8(s[i]) and 0xC0'u8) == 0x80'u8

proc luaUniOffset(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 2:
    raise newException(LuaRuntimeError, moduleArgNumErrorFmt("offset", "2 or 3"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(1, "offset", "string"))
  if not isNumber(args[1]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(2, "offset", "number"))

  let s = getString(args[0])
  let slen = s.len
  var n = intVal(args[1])

  # Default for i depends on the SIGN of n -- not a fixed default like len/codepoint.
  var iArg: int64 = if n >= 0: 1 else: int64(slen) + 1
  if len(args) >= 3:
    if not isNumber(args[2]):
      raise newException(LuaRuntimeError, moduleArgKindErrorFmt(3, "offset", "number"))
    iArg = intVal(args[2])

  var posi = uPosRelAt(iArg, slen)
  if posi < 1 or posi > int64(slen) + 1:
    raise newException(LuaRuntimeError, "bad argument #3 to 'offset' (position out of bounds)")

  var byteIdx = int(posi) - 1   # 0-based

  if n == 0:
    # Snap back to the start of whatever character contains byteIdx.
    while byteIdx > 0 and isContinuationByte(s, byteIdx):
      dec byteIdx
  elif n > 0:
    if byteIdx < slen and isContinuationByte(s, byteIdx):
      raise newException(LuaRuntimeError, "initial position is a continuation byte")
    n -= 1   # the starting character itself counts as the first
    while n > 0 and byteIdx < slen:
      inc byteIdx
      while byteIdx < slen and isContinuationByte(s, byteIdx):
        inc byteIdx
      n -= 1
    if n != 0:
      return @[newLuaNil()]
  else:
    if byteIdx < slen and isContinuationByte(s, byteIdx):
      raise newException(LuaRuntimeError, "initial position is a continuation byte")
    while n < 0 and byteIdx > 0:
      dec byteIdx
      while byteIdx > 0 and isContinuationByte(s, byteIdx):
        dec byteIdx
      n += 1
    if n != 0:
      return @[newLuaNil()]

  return @[newLuaInteger(byteIdx + 1)]

proc luaUniCodes(args: varargs[LuaValue]): seq[LuaValue] =
  let s = getStringArg(args, "codes", "1")

  let badAt = validateUtf8(s)
  if badAt != -1:
    raise newException(LuaRuntimeError, "invalid UTF-8 code at byte " & $(badAt + 1))

  let slen = s.len
  var byteIdx = 0   # captured by the closure below -- own, independent state per call

  let iterFn = proc(iterArgs: varargs[LuaValue]): seq[LuaValue] =
    if byteIdx >= slen:
      return @[newLuaNil()]   # signals "stop" to the generic-for loop
    let startPos = byteIdx
    var r: Rune
    fastRuneAt(s, byteIdx, r)   # decodes r AND advances byteIdx past this character
    return @[newLuaInteger(startPos + 1), newLuaInteger(int(r))]

  return @[newNimFn(iterFn), newLuaNil(), newLuaNil()]

proc validateCodepoint(args: varargs[LuaValue], fnName: string): int64 =
  if len(args) == 0:
    raise newException(LuaRuntimeError, moduleArgNumErrorFmt(fnName, "1"))
  if not isNumber(args[0]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(1, fnName, "number"))
  result = intVal(args[0])
  if result < 0 or result > 0x10FFFF or (result >= 0xD800 and result <= 0xDFFF):
    raise newException(LuaRuntimeError, "bad argument #1 to '" & fnName & "' (value out of range)")

proc luaUniIsAlpha(args: varargs[LuaValue]): seq[LuaValue] =
  return @[newLuaBool(isAlpha(Rune(validateCodepoint(args, "isAlpha"))))]

proc luaUniIsSpace(args: varargs[LuaValue]): seq[LuaValue] =
  let cp = validateCodepoint(args, "isSpace")
  return @[newLuaBool(isSpace($Rune(cp)))]

proc luaUniIsUpper(args: varargs[LuaValue]): seq[LuaValue] =
  return @[newLuaBool(isUpper(Rune(validateCodepoint(args, "isUpper"))))]

proc luaUniIsLower(args: varargs[LuaValue]): seq[LuaValue] =
  return @[newLuaBool(isLower(Rune(validateCodepoint(args, "isLower"))))]

proc newUnicodeLib*(): LuaValue = 
  result = newLuaTable()
  result.tval[newLuaString("char")] = newNimFn(luaUniChar)
  result.tval[newLuaString("len")] = newNimFn(luaUniLen)
  result.tval[newLuaString("valid")] = newNimFn(luaUniValid)
  result.tval[newLuaString("upper")] = newNimFn(luaUniUpper)
  result.tval[newLuaString("lower")] = newNimFn(luaUniLower)
  result.tval[newLuaString("reverse")] = newNimFn(luaUniReverse)
  result.tval[newLuaString("codepoint")] = newNimFn(luaUniCodepoint)
  result.tval[newLuaString("sub")] = newNimFn(luaUniSub)
  result.tval[newLuaString("offset")] = newNimFn(luaUniOffset)
  result.tval[newLuaString("codes")] = newNimFn(luaUniCodes)
  result.tval[newLuaString("isalpha")] = newNimFn(luaUniIsAlpha)
  result.tval[newLuaString("isspace")] = newNimFn(luaUniIsSpace)
  result.tval[newLuaString("isupper")] = newNimFn(luaUniIsUpper)
  result.tval[newLuaString("islower")] = newNimFn(luaUniIsLower)
  