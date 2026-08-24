import std/[tables, logging,streams,sets]
import ltypes, lvm, lvalue, lparse, llex, lcompiler, lerror,ldebug
import modules/[lmodule,lcore]

proc globalIndex(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 2 or not isString(args[1]): return @[newLuaNil()]
  let name = args[1].sval
  if vm.globals.hasKey(name): return @[vm.globals[name]]
  return @[newLuaNil()]

proc globalNewindex(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 3 or not isString(args[1]):
    raise newException(LuaRuntimeError, "bad argument to _G (string key expected)")
  let name = args[1].sval
  if vm.globalConsts.contains(name):
    raise newException(LuaRuntimeError, "Attempt to assign to constant global '" & name & "'")
  vm.globals[name] = args[2]
  return @[]

proc gPairs(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  let snapshot = newLuaTable()
  for name, val in vm.globals:
    snapshot.tval[newLuaString(name)] = val
  return @[newNimFn(luaNext), snapshot, newLuaNil()]

proc createGlobalTable*(vm: var VM) = 
  let G = newLuaTable()
  let gMT = newLuaTable()
  gMT.tval[MTINDEX] = newNimFnVM(globalIndex)
  gMT.tval[MTNEWINDEX] = newNimFnVM(globalNewindex)
  gMT.tval[MTPAIRS] = newNimFnVM(gPairs)
  G.mt = gMT
  vm.globals["_G"] = G
  vm.globals["_VERSION"] = newLuaString("Lua 5.5")

proc interpret*(vm: var VM, chunk: var Chunk) =
  if isNil(vm.output):
    vm.output = newFileStream(stdout)
  vm.stack = LuaStack(values: @[])
  vm.frames = @[]
  vm.newTypeKindLib()
  vm.openCore()
  vm.openTable()
  vm.openFile()
  vm.openMath()
  vm.openPackage()
  vm.createGlobalTable()
  vm.openProcess()
  vm.openTime()
  vm.openDir()
  vm.openSet()
  vm.openString()
  vm.openCoroutine()
  vm.openUnicode()

  let mainVal = newLuaClosure("<main>", 0, chunk)
  vm.stack.add(wrapLuaClosure(mainVal))   # slot 0: the closure itself
  vm.stack.add(vm.globals["_G"])          # slot 1: _ENV, seeded from _G
  let rootFrame = CallFrame(closure: mainVal, ip: 0, slotBase: 0)
  vm.frames.add(rootFrame)

  discard vm.run()

proc executeString*(vm: var VM, contents: string) =
  try:
    let tokens = tokenize(contents)

    var parser = LuaParser(tokens: tokens, current: 0)
    var ast = parser.parseBlock()
    var compiler = newCompiler()
    #printAST(parser)
    var chunk = initChunk()
    compiler.compile(ast, chunk, 1)

    chunk.writeChunk(uint8(opReturn), 1)
    chunk.writeChunk(1'u8, 1)
    #disassembleChunk(chunk,"<main>")


    interpret(vm, chunk)
  except LuaSyntaxError as e:
    fatal "Syntax Error: ", e.msg
  except LuaCompileError as e:
    fatal "Compile Error: ", e.msg
  except LuaRuntimeError as e:
    fatal "Runtime Error: ", e.msg
  except LuaExitError:
    raise   # deliberately NOT caught here -- must reach the real CLI boundary
  except CatchableError as e:
    fatal "Unhandled Error: ", e.msg

proc executeFile*(vm: var VM, fileName: string) =
  try:
    let fp = open(fileName, fmRead)
    let contents = fp.readAll()
    executeString(vm, contents)
  except IoError:
    fatal "Unable to open file: ", fileName
