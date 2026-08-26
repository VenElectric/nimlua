import std/[strutils,json,tables]
import lvalue, ltypes,lerror

proc parseBaseN(s: string, base: int): (bool, int64) =
  var idx = 0
  var sign: int64 = 1

  if idx < s.len and s[idx] == '-':
    sign = -1
    inc idx
  elif idx < s.len and s[idx] == '+':
    inc idx

  if idx >= s.len: return (false, 0)

  var res: int64 = 0
  for i in idx ..< s.len:
    let c = s[i]
    var digit: int
    if c in '0'..'9': digit = ord(c) - ord('0')
    elif c in 'a'..'z': digit = ord(c) - ord('a') + 10
    elif c in 'A'..'Z': digit = ord(c) - ord('A') + 10
    else: return (false, 0)

    if digit >= base: return (false, 0)
    res = res * base + digit

  return (true, res * sign)

proc luaUToNumber*(val: LuaValue, base: int = 10): LuaValue =
  if base < 2 or base > 36:
    raise newException(ValueError, "bad argument #2 to 'tonumber' (base out of range)")

  if base == 10:
    case val.kind
    of ltNumber:
      return val
    of ltString:
      let s = val.sval.strip()
      if s.len == 0: return newLuaNil()

      # 1. Try Hexadecimal Integer (0x...)
      let lower = s.toLowerAscii()
      if lower.startsWith("0x") or lower.startsWith("+0x") or lower.startsWith("-0x"):
        let cleanHex = lower.replace("+", "")
        var isNeg = cleanHex.startsWith("-")
        let hexDigits = if isNeg: cleanHex[3..^1] else: cleanHex[2..^1]
        let (ok, res) = parseBaseN(hexDigits, 16)
        if ok:
          return newLuaNumber(if isNeg: -res.float64 else: res.float64)
        return newLuaNil()

      # 2. Try Standard Base-10 Integer
      try:
        return newLuaNumber(parseBiggestInt(s).float64)
      except ValueError:
        discard

      # 3. Try Base-10 Float (e.g. 3.14, 1e10)
      try:
        return newLuaNumber(parseFloat(s).float64)
      except ValueError:
        return newLuaNil()
    else:
      return newLuaNil()
  else:
    # Non-10 base only accepts string inputs (or numbers converted to string without base prefixes)
    if not isString(val) and not isNumber(val):
      return newLuaNil()

    let strVal = if isString(val): val.sval else: $val
    let s = strVal.strip()
    let (ok, res) = parseBaseN(s, base)
    if ok:
      return newLuaNumber(res.float64)
    else:
      return newLuaNil()

method toJsonExt*(v: LuaUserData): JsonNode {.base.} = newJNull()

proc `%`*(v:LuaValue): JsonNode
proc `%`*(v:LuaUserData): JsonNode = toJsonExt(v)

proc allKeysArePositiveIntegers(v: LuaTable): bool =
  for k in v.keys:
    if not isInteger(k) or k.ival < 1: return false
  return true

proc maxIntKey(v: LuaTable): int =
  result = 0
  for k in v.keys:
    if isInteger(k) and k.ival > 0 and int(k.ival) > result:
      result = int(k.ival)

const MaxArraySparsity = 2   # tune to taste: allows the array to be up to
                              # this many times "wider" than its real entry
                              # count before giving up and falling back to
                              # an object -- this is the actual size-cap
                              # the earlier message described, done properly.

proc `%`*(v: LuaTable): JsonNode =
  let n = maxIntKey(v)
  if n > 0 and allKeysArePositiveIntegers(v) and n <= v.len * MaxArraySparsity:
    result = newJArray()
    for i in 1 .. n:
      let key = newLuaInteger(int64(i))
      if v.hasKey(key): result.add(%v[key])
      else: result.add(newJNull())
  else:
    result = newJObject()
    for k, val in v.pairs:
      result[$k] = %val
  
  
proc `%`*(v:LuaValue): JsonNode = 
  case v.kind
  of ltNumber: %v.nval
  of ltBool: %v.bval
  of ltInteger: %v.ival
  of ltString: %v.sval
  of ltTable: %v.tval
  of ltClosure,ltNativeFn,ltNativeFnVM,ltNil,ltThread: newJNull()
  of ltUserData: %v.ud

proc toLua*(n:JsonNode): LuaValue =
  case n.kind
  of JNull: return newLuaNil()
  of JBool: return newLuaBool(n.getBool())
  of JInt: return newLuaInteger(n.getBiggestInt())
  of JFloat: return newLuaNumber(n.getFloat().float64)
  of JString: return newLuaString(n.getStr())
  of JObject:
    result = newLuaTable()
    for k,v in n.pairs:
      result.tval[newLuaString(k)] = toLua(v)
  of JArray: 
    result = newLuaTable()
    var i = 1
    for item in n.items:
      result.tval[newLuaInteger(i)] = toLua(item)
      inc(i)

# bad argument #1 to 'remove' (table expected)
# Invalid # of arguments to 'sin'. Expected one argument.
proc moduleArgKindErrorFmt*(pos:int,fnName,kind:string): string = "bad argument #" & $pos & " to '" & fnName & "' (" & kind & " expected)"
proc moduleArgKindsErrorFmt*(pos:int,fnName:string,kinds:openArray[string]): string = "bad argument #" & $pos & " to '" & fnName & "' (" & kinds.join(",") & " expected)"
proc moduleArgNumErrorFmt*(fnName,numArgs:string): string = "invalid # of arguments to '" & fnName & "'. Expected " & numArgs & "."
