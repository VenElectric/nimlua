import std/[os,tables]
from strutils import replace
import ../ltypes, ../lvalue, ../lerror, ../llex, ../lparse, ../lvm

proc newPackageLib*(): LuaValue =
  result = newLuaTable()
  result.tval[newLuaString("loaded")] = newLuaTable()
  result.tval[newLuaString("path")] = newLuaString("./?.lua")

proc luaRequire*(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 1 or not isString(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'require' (string expected)")
  let modName = args[0].sval

  let pkg = vm.globals["package"]
  let loaded = pkg.tval[newLuaString("loaded")]
  let loadedKey = newLuaString(modName)

  if loaded.tval.hasKey(loadedKey):
    return @[loaded.tval[loadedKey]]

  let path = modName.replace(".", "/") & ".lua"
  if not fileExists(path):
    raise newException(LuaRuntimeError, "module '" & modName & "' not found (no file '" & path & "')")
  let source = readFile(path)

  let tokens = tokenize(source)
  var parser = LuaParser(tokens: tokens, current: 0)
  let ast = parser.parseBlock()

  var moduleChunk = initChunk()
  var compiler = lvm.newCompiler()
  compiler.compile(ast, moduleChunk, 1)
  moduleChunk.writeChunk(uint8(opReturn), 1)
  moduleChunk.writeChunk(0'u8, 1)

  let stopDepth = vm.frames.len
  var modClosure = newLuaClosure(modName, 0, moduleChunk)
  vm.stack.add(wrapLuaClosure(modName, 0, moduleChunk))
  vm.frames.add(CallFrame(closure: modClosure, ip: 0, slotBase: vm.stack.len - 1))
  discard vm.run(stopDepth)
  
  let resultVal = if vm.lastReturnCount > 0: vm.pop() else: newLuaBool(true)
  loaded.tval[loadedKey] = resultVal
  return @[resultVal]