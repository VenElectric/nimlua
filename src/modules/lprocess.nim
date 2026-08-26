import std/tables
from os import execShellCmd,existsEnv,getEnv
import ../lvalue,../ltypes,../lerror

proc luaGetenv(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 1 or not isString(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'getenv' (string expected)")
  if existsEnv(args[0].sval):
    return @[newLuaString(getEnv(args[0].sval))]
  return @[newLuaNil()]

proc luaExit(args: varargs[LuaValue]): seq[LuaValue] =
  # Raises rather than calling quit() directly -- the real process termination
  # only happens at the true CLI boundary (nimlua.nim's main), which is what
  # keeps this safe to call from a script running inside an in-process test
  # harness without killing the whole test runner.
  var code = 0
  if args.len >= 1:
    if isBool(args[0]):
      code = if args[0].bval: 0 else: 1
    elif isNumber(args[0]):
      code = int(intVal(args[0]))
  var e = newException(LuaExitError, "os.exit(" & $code & ")")
  e.code = code
  raise e

proc luaExecute(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if args.len == 0:
    return @[newLuaBool(true)]   # no-arg execute just reports whether a shell exists
  if not isString(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'execute' (string expected)")
  let exitCode = execShellCmd(args[0].sval)
  return @[newLuaBool(exitCode == 0), newLuaString("exit"), newLuaInteger(exitCode)]

proc newProcessLib*(): LuaValue =
  result = newLuaTable()
  result.tval[newLuaString("exit")] = newNimFn(luaExit)
  result.tval[newLuaString("getenv")] = newNimFn(luaGetenv)
  result.tval[newLuaString("execute")] = newNimFnVM(luaExecute)