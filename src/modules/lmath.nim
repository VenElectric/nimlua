import std/[tables,math,sugar,random]
import ../ltypes, ../lvalue, ../lerror


proc luaAbs(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,"Invalid # of arguments to 'abs'. Expected one argument.")
  let num = args[0]
  if not isNumber(num):
    raise newException(LuaRuntimeError,"Invalid argument at position 1 for 'abs'. (expected number)")
  let res = if isFloat(num): newLuaNumber(abs(num.nval)) else: newLuaInteger(abs(num.ival))
  return @[res]

proc luaArccos(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,"Invalid # of arguments to 'arccos'. Expected one argument.")
  let num = args[0]
  if not isNumber(num):
    raise newException(LuaRuntimeError,"Invalid argument at position 1 for 'arccos'. (expected number)")
  
  return @[newLuaNumber(arccos(num.numVal))]

proc luaArcsin(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,"Invalid # of arguments to 'arcsin'. Expected one argument.")
  let num = args[0]
  if not isNumber(num):
    raise newException(LuaRuntimeError,"Invalid argument at position 1 for 'arcsin'. (expected number)")
  return @[newLuaNumber(arcsin(num.numVal))]

proc luaArctan(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,"Invalid # of arguments to 'arctan'. Expected one argument.")
  let num = args[0]
  if not isNumber(num):
    raise newException(LuaRuntimeError,"Invalid argument at position 1 for 'arctan'. (expected number)")
  return @[newLuaNumber(arctan(num.numVal))]

proc luaCeil(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,"Invalid # of arguments to 'ceil'. Expected one argument.")
  let num = args[0]
  if not isNumber(num):
    raise newException(LuaRuntimeError,"Invalid argument at position 1 for 'ceil'. (expected number)")
  return @[newLuaInteger(int64(ceil(num.numVal)))]

proc luaCos(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,"Invalid # of arguments to 'cos'. Expected one argument.")
  let num = args[0]
  if not isNumber(num):
    raise newException(LuaRuntimeError,"Invalid argument at position 1 for 'cos'. (expected number)")
  return @[newLuaNumber(cos(num.numVal))]

proc luaDeg(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,"Invalid # of arguments to 'deg'. Expected one argument.")
  let num = args[0]
  if not isNumber(num):
    raise newException(LuaRuntimeError,"Invalid argument at position 1 for 'deg'. (expected number)")
  return @[newLuaNumber(radToDeg(num.numVal))]

proc luaExp(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,"Invalid # of arguments to 'exp'. Expected one argument.")
  let num = args[0]
  if not isNumber(num):
    raise newException(LuaRuntimeError,"Invalid argument at position 1 for 'exp'. (expected number)")
  return @[newLuaNumber(exp(num.numVal))]

proc luaFloor(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,"Invalid # of arguments to 'floor'. Expected one argument.")
  let num = args[0]
  if not isNumber(num):
    raise newException(LuaRuntimeError,"Invalid argument at position 1 for 'floor'. (expected number)")
  return @[newLuaInteger(int64(floor(num.numVal)))]

proc luaFmod(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) != 2:
    raise newException(LuaRuntimeError, "wrong number of arguments to 'fmod'")
  let l = args[0]
  let r = args[1]
  if not isNumber(l):
    raise newException(LuaRuntimeError, "bad argument #1 to 'fmod' (number expected)")
  if not isNumber(r):
    raise newException(LuaRuntimeError, "bad argument #2 to 'fmod' (number expected)")

  if isInteger(l) and isInteger(r):
    if r.ival == 0:
      raise newException(LuaRuntimeError, "bad argument #2 to 'fmod' (zero)")
    return @[newLuaInteger(l.ival mod r.ival)]
  else:
    return @[newLuaNumber(floorMod(numVal(l), numVal(r)))]

proc luaFrexp(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,"Invalid # of arguments to 'frexp'. Expected one argument.")
  let num = args[0]
  if not isNumber(num):
    raise newException(LuaRuntimeError,"Invalid argument at position 1 for 'frexp'. (expected number)")
  let (a,b) = frexp(num.numVal)
  return @[newLuaNumber(a),newLuaInteger(b)]

proc luaLdexp(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) != 2:
    raise newException(LuaRuntimeError, "wrong number of arguments to 'ldexp'")
  let m = args[0]
  let e = args[1]
  if not isNumber(m):
    raise newException(LuaRuntimeError, "bad argument #1 to 'ldexp' (number expected)")
  if not isNumber(e):
    raise newException(LuaRuntimeError, "bad argument #2 to 'ldexp' (number expected)")
  return @[newLuaNumber(numVal(m) * pow(2.0, numVal(e)))]

proc luaLog(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 1 or len(args) > 2:
    raise newException(LuaRuntimeError, "wrong number of arguments to 'log'")
  let x = args[0]
  if not isNumber(x):
    raise newException(LuaRuntimeError, "bad argument #1 to 'log' (number expected)")

  if len(args) == 1:
    return @[newLuaNumber(ln(numVal(x)))]

  let base = args[1]
  if not isNumber(base):
    raise newException(LuaRuntimeError, "bad argument #2 to 'log' (number expected)")
  let b = numVal(base)

  if b == 2.0: return @[newLuaNumber(log2(numVal(x)))]
  elif b == 10.0: return @[newLuaNumber(log10(numVal(x)))]
  else: return @[newLuaNumber(ln(numVal(x)) / ln(b))]

proc luaMax(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) == 0:
    raise newException(LuaRuntimeError, "bad argument #1 to 'max' (value expected)")
  var best = args[0]
  if not isNumber(best):
    raise newException(LuaRuntimeError, "bad argument #1 to 'max' (number expected)")
  for i in 1 ..< args.len:
    if not isNumber(args[i]):
      raise newException(LuaRuntimeError, "bad argument #" & $(i + 1) & " to 'max' (number expected)")
    if numVal(args[i]) > numVal(best): best = args[i]
  return @[best]

proc luaMin(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) == 0:
    raise newException(LuaRuntimeError, "bad argument #1 to 'max' (value expected)")
  var best = args[0]
  if not isNumber(best):
    raise newException(LuaRuntimeError, "bad argument #1 to 'max' (number expected)")
  for i in 1 ..< args.len:
    if not isNumber(args[i]):
      raise newException(LuaRuntimeError, "bad argument #" & $(i + 1) & " to 'max' (number expected)")
    if numVal(args[i]) < numVal(best): best = args[i]
  return @[best]

proc luaModf(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) != 1:
    raise newException(LuaRuntimeError, "wrong number of arguments to 'modf'")
  let num = args[0]
  if not isNumber(num):
    raise newException(LuaRuntimeError, "bad argument #1 to 'modf' (number expected)")

  let x = numVal(num)
  if x == Inf or x == NegInf:
    return @[newLuaNumber(x), newLuaNumber(0.0)]   # matches real Lua: modf(inf) -> inf, 0.0

  let (intPart, fracPart) = splitDecimal(x)
  return @[newLuaNumber(intPart), newLuaNumber(fracPart)]

proc luaRad(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,"Invalid # of arguments to 'rad'. Expected one argument.")
  let num = args[0]
  if not isNumber(num):
    raise newException(LuaRuntimeError,"Invalid argument at position 1 for 'rad'. (expected number)")
  return @[newLuaNumber(degToRad(num.numVal))]

proc luaRandom(args: varargs[LuaValue]): seq[LuaValue] =
  case len(args)
  of 0:
    return @[newLuaNumber(rand(1.0))]
  of 1:
    if not isNumber(args[0]):
      raise newException(LuaRuntimeError, "bad argument #1 to 'random' (number expected)")
    let m = int(intVal(args[0]))
    if m < 1:
      raise newException(LuaRuntimeError, "bad argument #1 to 'random' (interval is empty)")
    return @[newLuaInteger(int64(rand(1 .. m)))]
  of 2:
    if not isNumber(args[0]) or not isNumber(args[1]):
      raise newException(LuaRuntimeError, "bad arguments to 'random' (numbers expected)")
    let lo = int(intVal(args[0]))
    let hi = int(intVal(args[1]))
    if lo > hi:
      raise newException(LuaRuntimeError, "bad argument #2 to 'random' (interval is empty)")
    return @[newLuaInteger(int64(rand(lo .. hi)))]
  else:
    raise newException(LuaRuntimeError, "wrong number of arguments to 'random'")

proc luaRandomSeed(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) == 0:
    randomize()
    return @[]
  if not isNumber(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'randomseed' (number expected)")
  var seed = int64(intVal(args[0]))
  if len(args) >= 2:
    if not isNumber(args[1]):
      raise newException(LuaRuntimeError, "bad argument #2 to 'randomseed' (number expected)")
    seed = (seed shl 32) xor int64(intVal(args[1]))
  randomize(seed)
  return @[]

proc luaSin(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,"Invalid # of arguments to 'sin'. Expected one argument.")
  let num = args[0]
  if not isNumber(num):
    raise newException(LuaRuntimeError,"Invalid argument at position 1 for 'sin'. (expected number)")
  return @[newLuaNumber(sin(num.numVal))]

proc luaSqrt(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,"Invalid # of arguments to 'sqrt'. Expected one argument.")
  let num = args[0]
  if not isNumber(num):
    raise newException(LuaRuntimeError,"Invalid argument at position 1 for 'sqrt'. (expected number)")
  return @[newLuaNumber(sqrt(num.numVal))]

proc luaTan(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError,"Invalid # of arguments to 'tan'. Expected one argument.")
  let num = args[0]
  if not isNumber(num):
    raise newException(LuaRuntimeError,"Invalid argument at position 1 for 'tan'. (expected number)")
  return @[newLuaNumber(tan(num.numVal))]

proc luaToInteger(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) != 1:
    raise newException(LuaRuntimeError, "wrong number of arguments to 'tointeger'")
  let num = args[0]
  if isInteger(num):
    return @[num]
  elif isFloat(num):
    let (intPart, fracPart) = splitDecimal(num.nval)
    if fracPart == 0.0: return @[newLuaInteger(int64(intPart))]
    else: return @[newLuaNil()]
  else:
    return @[newLuaNil()]

proc luaUlt(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 2:
    raise newException(LuaRuntimeError,"Invalid # of arguments to 'ult'. Expected two arguments.")
  let l = args[0]
  let r = args[1]
  if not isInteger(l):
    raise newException(LuaRuntimeError,"Invalid argument at position 1 for 'ult'. (expected integer)")
  if not isInteger(r):
    raise newException(LuaRuntimeError,"Invalid argument at position 2 for 'ult'. (expected integer)")
  return @[newLuaBool(l.ival <% r.ival)]

proc newMathLib*(): LuaValue = 
  randomize() # need to update if there are multiple states running about
  result = newLuaTable()
  result.tval[newLuaString("abs")] = newNimFn(luaAbs)
  result.tval[newLuaString("acos")] = newNimFn(luaArccos)
  result.tval[newLuaString("asin")] = newNimFn(luaArcsin)
  result.tval[newLuaString("atan")] = newNimFn(luaArctan)
  result.tval[newLuaString("ceil")] = newNimFn(luaCeil)
  result.tval[newLuaString("cos")] = newNimFn(luaCos)
  result.tval[newLuaString("deg")] = newNimFn(luaDeg)
  result.tval[newLuaString("exp")] = newNimFn(luaExp)
  result.tval[newLuaString("floor")] = newNimFn(luaFloor)
  result.tval[newLuaString("frexp")] = newNimFn(luaFrexp)
  result.tval[newLuaString("huge")] = newLuaNumber(Inf)
  result.tval[newLuaString("max")] = newNimFn(luaMax)
  result.tval[newLuaString("min")] = newNimFn(luaMin)
  result.tval[newLuaString("mininteger")] = newLuaInteger(int64.low) # idk if this works
  result.tval[newLuaString("maxinteger")] = newLuaInteger(int64.high) # idk if this works
  result.tval[newLuaString("rad")] = newNimFn(luaRad)
  result.tval[newLuaString("random")] = newNimFn(luaRandom)
  result.tval[newLuaString("sin")] = newNimFn(luaSin)
  result.tval[newLuaString("sqrt")] = newNimFn(luaSqrt)
  result.tval[newLuaString("tan")] = newNimFn(luaTan)
  result.tval[newLuaString("tointeger")] = newNimFn(luaToInteger)
  result.tval[newLuaString("ult")] = newNimFn(luaUlt)
  result.tval[newLuaString("pi")] = newLuaNumber(PI)
  result.tval[newLuaString("fmod")] = newNimFn(luaFmod)
  result.tval[newLuaString("log")] = newNimFn(luaLog)
  result.tval[newLuaString("modf")] = newNimFn(luaModf)
  result.tval[newLuaString("randomseed")] = newNimFn(luaRandomSeed)
  result.tval[newLuaString("ldexp")] = newNimFn(luaLdexp)