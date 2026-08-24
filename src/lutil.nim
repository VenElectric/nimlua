import std/[strutils]
import lvalue, ltypes

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
# bad argument #1 to 'remove' (table expected)
# Invalid # of arguments to 'sin'. Expected one argument.
proc moduleArgKindErrorFmt*(pos:int,fnName,kind:string): string = "bad argument #" & $pos & " to '" & fnName & "' (" & kind & " expected)"
proc moduleArgKindsErrorFmt*(pos:int,fnName:string,kinds:openArray[string]): string = "bad argument #" & $pos & " to '" & fnName & "' (" & kinds.join(",") & " expected)"
proc moduleArgNumErrorFmt*(fnName,numArgs:string): string = "invalid # of arguments to '" & fnName & "'. Expected " & numArgs & "."