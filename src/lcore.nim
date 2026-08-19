import std/[tables]
import lvalue,lerror
proc luaRawGet(args:varargs[LuaValue]): LuaValue = discard
proc luaRawSet(args:varargs[LuaValue]): LuaValue = discard

proc luaSetMetatable*(args: varargs[LuaValue]): LuaValue =
  if len(args) < 1 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'setmetatable' (table expected)")
  let t = args[0]
  if len(args) < 2 or args[1].kind == ltNil:
    t.mt = nil
  elif args[1].kind == ltTable:
    t.mt = args[1]
  else:
    raise newException(LuaRuntimeError, "bad argument #2 to 'setmetatable' (nil or table expected)")
  return t

proc luaGetMetatable*(args: varargs[LuaValue]): LuaValue =
  if len(args) < 1 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'getmetatable' (table expected)")
  if system.isNil(args[0].mt): return newLuaNil()
  return args[0].mt

proc luaPrint*(args: varargs[LuaValue]): LuaValue =
  for i, arg in args:
    # Uses the `$` stringify operator we overloaded in Phase 1!
    stdout.write($arg)
    if i < args.high:
      stdout.write("\t")

  stdout.write("\n")
  return newLuaNil() # Lua functions push nil if they don't explicitly return

proc luaNext*(args:varargs[LuaValue]): LuaValue = 
  let tab = args[0]
  var index = 0.0
  if len(args) == 2 and isNumber(args[1]):
    index = args[1].nval
  

proc luaPairs*(args:varargs[LuaValue]): LuaValue = discard

proc luaIPairs*(args:varargs[LuaValue]): LuaValue = discard