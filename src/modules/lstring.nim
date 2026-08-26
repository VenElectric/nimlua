import std/[tables,strutils,sugar]
import ../lvalue,../ltypes,../lerror,../lutil,lmatch,../lvm
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

proc luaStrSplit(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) == 0:
    raise newException(LuaRuntimeError,moduleArgNumErrorFmt("split","1"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError,moduleArgKindErrorFmt(1,"split","string"))
  let str = getString(args[0])
  var sep = ","
  if len(args) == 2 and isString(args[1]):
    sep = getString(args[1])
  for s in split(str,sep):
    result.add(newLuaString(s))

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
  let plain = len(args) >= 4 and truthy(args[3])   # restored -- no longer hardcoded

  let startIdx = resolveFindInit(initArg, s.len)
  if startIdx == -1:
    return @[newLuaNil()]

  if plain:
    let foundIdx = s.find(pat, startIdx)
    if foundIdx == -1: return @[newLuaNil()]
    return @[newLuaInteger(foundIdx + 1), newLuaInteger(foundIdx + pat.len)]

  let (found, ms, mStart, mEnd) = findMatch(pat, s, startIdx)
  if not found: return @[newLuaNil()]
  result = @[newLuaInteger(mStart + 1), newLuaInteger(mEnd)]
  result.add(capturesToLua(ms))

proc luaStrMatch*(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 2:
    raise newException(LuaRuntimeError, moduleArgNumErrorFmt("match", "at least 2"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(1, "match", "string"))
  if not isString(args[1]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(2, "match", "string"))

  let s = getString(args[0])
  let pat = getString(args[1])
  let initArg = if len(args) >= 3 and isNumber(args[2]): intVal(args[2]) else: 1'i64
  let startIdx = resolveFindInit(initArg, s.len)
  if startIdx == -1:
    return @[newLuaNil()]

  let (found, ms, mStart, mEnd) = findMatch(pat, s, startIdx)
  if not found: return @[newLuaNil()]

  let caps = capturesToLua(ms)
  if caps.len == 0:
    return @[newLuaString(s[mStart ..< mEnd])]
  return caps

proc luaStrGmatch*(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 2:
    raise newException(LuaRuntimeError, moduleArgNumErrorFmt("gmatch", "2 or 3"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(1, "gmatch", "string"))
  if not isString(args[1]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(2, "gmatch", "string"))

  let s = getString(args[0])
  let pat = getString(args[1])
  let initArg = if len(args) >= 3 and isNumber(args[2]): intVal(args[2]) else: 1'i64
  var searchPos = resolveFindInit(initArg, s.len)
  if searchPos == -1: searchPos = s.len + 1   # past the end -- iterator reports "done" immediately

  let iterFn = proc(iterArgs: varargs[LuaValue]): seq[LuaValue] =
    if searchPos > s.len:
      return @[newLuaNil()]
    let (found, ms, mStart, mEnd) = findMatch(pat, s, searchPos)
    if not found:
      searchPos = s.len + 1   # stop any future calls from re-searching
      return @[newLuaNil()]

    # Guarantee forward progress: an empty match (mEnd == mStart) would
    # otherwise be re-found at this exact same position on every subsequent call.
    searchPos = if mEnd > mStart: mEnd else: mEnd + 1

    let caps = capturesToLua(ms)
    if caps.len == 0:
      return @[newLuaString(s[mStart ..< mEnd])]
    return caps

  return @[newNimFn(iterFn), newLuaNil(), newLuaNil()]

proc expandReplacement(repl: string, ms: MatchState, wholeMatch: string): string =
  result = ""
  var i = 0
  while i < repl.len:
    if repl[i] == '%' and i + 1 < repl.len:
      let c = repl[i + 1]
      if c == '%':
        result.add('%')
      elif c == '0':
        result.add(wholeMatch)
      elif c in '1'..'9':
        let idx = ord(c) - ord('1')
        if ms.captures.len == 0 and idx == 0:
          result.add(wholeMatch)   # no captures -- %1 falls back to the whole match
        elif idx < ms.captures.len:
          let cap = ms.captures[idx]
          if cap.len == CapPosition:
            result.add($(cap.start + 1))
          else:
            result.add(ms.subject[cap.start ..< cap.start + cap.len])
        else:
          raise newException(LuaRuntimeError, "invalid capture index %" & $c)
      else:
        raise newException(LuaRuntimeError, "invalid use of '%' in replacement string")
      i += 2
    else:
      result.add(repl[i])
      inc i

proc luaStrGsub*(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 3:
    raise newException(LuaRuntimeError, moduleArgNumErrorFmt("gsub", "3 or 4"))
  if not isString(args[0]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(1, "gsub", "string"))
  if not isString(args[1]):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(2, "gsub", "string"))
  let replArg = args[2]
  if not (isString(replArg) or isTable(replArg) or isCallable(replArg)):
    raise newException(LuaRuntimeError, moduleArgKindErrorFmt(3, "gsub", "string, table, or function"))

  let s = getString(args[0])
  let pat = getString(args[1])
  let maxN = if len(args) >= 4 and isNumber(args[3]): int(intVal(args[3])) else: int.high

  var output = ""
  var searchPos = 0
  var count = 0

  while searchPos <= s.len and count < maxN:
    let (found, ms, mStart, mEnd) = findMatch(pat, s, searchPos)
    if not found: break

    output.add(s[searchPos ..< mStart])   # whatever was skipped to reach this match
    let wholeMatch = s[mStart ..< mEnd]
    let capVals = capturesToLua(ms)
    # No explicit captures -> the whole match plays capture #1's role,
    # same convention find/match/gmatch already use via capturesToLua.
    let callArgs = if capVals.len == 0: @[newLuaString(wholeMatch)] else: capVals

    if isString(replArg):
      output.add(expandReplacement(replArg.sval, ms, wholeMatch))
    elif isTable(replArg):
      # Table replacement only ever uses the FIRST capture (or whole match) as a key --
      # unlike function replacement, which gets every capture as a separate argument.
      let key = callArgs[0]
      if replArg.tval.hasKey(key) and truthy(replArg.tval[key]):
        let val = replArg.tval[key]
        if not isString(val):
          raise newException(LuaRuntimeError, "invalid replacement value (a " & $val.kind & ")")
        output.add(val.sval)
      else:
        output.add(wholeMatch)   # nil/false/absent -> keep the original text
    else:   # function
      let results = vm.callMetamethod(replArg, 1, callArgs)
      if not truthy(results[0]):
        output.add(wholeMatch)   # nil/false return -> keep the original text
      else:
        if not isString(results[0]):
          raise newException(LuaRuntimeError, "invalid replacement value (a " & $results[0].kind & ")")
        output.add(results[0].sval)

    inc count

    # Same forward-progress guarantee gmatch needed: a zero-length match
    # must still copy over the one character it's sitting on and step past
    # it, or the next iteration would find the identical match forever.
    if mEnd == mStart:
      if mStart < s.len: output.add(s[mStart])
      searchPos = mStart + 1
    else:
      searchPos = mEnd

  if searchPos <= s.len:
    output.add(s[searchPos ..< s.len])   # whatever's left after the last match (or no match at all)

  return @[newLuaString(output), newLuaInteger(count)]

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
  result.tval[newLuaString("match")] = newNimFn(luaStrMatch)
  result.tval[newLuaString("gmatch")] = newNimFn(luaStrGmatch)
  result.tval[newLuaString("gsub")] = newNimFnVM(luaStrGSub)
  result.tval[newLuaString("split")] = newNimFn(luaStrSplit)
  


