
type
  LuaError = object of CatchableError
  LuaSyntaxError* = object of LuaError
  LuaCompileError* = object of LuaError
  LuaRuntimeError* = object of LuaError