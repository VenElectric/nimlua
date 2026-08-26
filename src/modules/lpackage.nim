import std/[os,tables,strutils]
from strutils import replace
import ../ltypes, ../lvalue, ../lerror, ../llex, ../lparse, ../lvm, ../lcompiler

proc defaultPackagePath(): string =
  let libDir = getHomeDir() / ".kuu" / "lua"
  # Self-healing: create the directory here rather than relying on a
  # nimble install-time hook, which has a documented issue where it may
  # not fire at all when srcDir is set (exactly this project's config).
  try:
    createDir(libDir)
  except OSError:
    discard   # permissions/read-only fs -- require() just won't find
              # anything there; not a fatal problem either way
  return "./?.lua;./?/init.lua;" & (libDir / "?.lua") & ";" & (libDir / "?/init.lua")

proc newPackageLib*(): LuaValue =
  result = newLuaTable()
  result.tval[newLuaString("loaded")] = newLuaTable()
  result.tval[newLuaString("path")] = newLuaString(defaultPackagePath())

proc searchPath(modName: string, pathTemplate: string): seq[string] =
  # Real Lua replaces dots with the OS-appropriate separator here, not '/'
  # unconditionally -- matters if this ever runs on Windows.
  let modPath = modName.replace(".", $DirSep)
  result = @[]
  for tmpl in pathTemplate.split(';'):
    if tmpl.len == 0: continue
    result.add(tmpl.replace("?", modPath))

proc luaRequire*(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 1 or not isString(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'require' (string expected)")
  let modName = args[0].sval

  let pkg = vm.globals["package"]
  let loaded = pkg.tval[newLuaString("loaded")]
  let loadedKey = newLuaString(modName)
  if loaded.tval.hasKey(loadedKey):
    return @[loaded.tval[loadedKey]]

  let pathTemplate = pkg.tval[newLuaString("path")].sval
  let candidates = searchPath(modName, pathTemplate)

  var foundPath = ""
  for candidate in candidates:
    if fileExists(candidate):
      foundPath = candidate
      break

  if foundPath == "":
    var msg = "module '" & modName & "' not found:"
    for candidate in candidates:
      msg.add("\n\tno file '" & candidate & "'")
    raise newException(LuaRuntimeError, msg)

  let source = readFile(foundPath)
  let tokens = tokenize(source)
  var parser = LuaParser(tokens: tokens, current: 0)
  let ast = parser.parseBlock()

  var moduleChunk = initChunk()
  var compiler = newCompiler()
  compiler.compile(ast, moduleChunk, 1)
  moduleChunk.writeChunk(uint8(opReturn), 1)
  moduleChunk.writeChunk(0'u8, 1)

  let stopDepth = vm.frames.len
  var modClosure = newLuaClosure(modName, 0, moduleChunk)
  vm.stack.add(wrapLuaClosure(modClosure))
  vm.stack.add(vm.globals["_G"])
  vm.frames.add(CallFrame(closure: modClosure, ip: 0, slotBase: vm.stack.len - 2))
  discard vm.run(stopDepth)

  let resultVal = if vm.lastReturnCount > 0: vm.pop() else: newLuaBool(true)
  loaded.tval[loadedKey] = resultVal
  return @[resultVal]