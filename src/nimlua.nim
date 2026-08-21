import lvm, lvalue, lparse, llex, lerror, log,ldebug,ltypes,lauxlib
import std/[tables, logging, parseopt]

initLogging(lvlAll)



proc executeString(vm: var VM, contents: string) =
  try:
    let tokens = tokenize(contents)

    var parser = LuaParser(tokens: tokens, current: 0)
    var ast = parser.parseBlock()
    var compiler = newCompiler()
    #printAST(parser)
    var chunk = initChunk()
    compiler.compile(ast, chunk, 1)

    chunk.writeChunk(uint8(opReturn),1)
    chunk.writeChunk(1'u8, 1)
    #disassembleChunk(chunk,"<main>")
   
    
    interpret(vm, chunk)
  except LuaSyntaxError as e:
    fatal "Syntax Error: ", e.msg
  except LuaCompileError as e:
    fatal "Compile Error: ", e.msg
  except LuaRuntimeError as e:
    fatal "Runtime Error: ", e.msg
  except CatchableError as e:
    fatal "Unhandled Error: ", e.msg

proc executeFile(vm: var VM, fileName: string) =
  try:
    let fp = open(fileName, fmRead)
    let contents = fp.readAll()
    executeString(vm, contents)
  except IoError:
    fatal "Unable to open file: ", fileName



proc main() =
  var
    p = initOptParser()
    filename = ""
    enableTrace = false

  # Parse command line arguments
  for kind, key, val in p.getopt():
    case kind
    of cmdArgument:
      filename = key
    of cmdLongOption, cmdShortOption:
      case key
      of "trace", "t":
        enableTrace = true
      else:
        discard
    of cmdEnd: discard

  if filename == "":
    echo "Usage: lvm [options] <script.lua>"
    echo "Options:"
    echo "  -t, --trace    Enable opcode instruction tracing"
    quit(1)

  # Initialize and configure the VM
  var vm = VM(traceExecution: enableTrace)
  # Optional: If trace is enabled, ensure the console logger shows Debug messages
  # (Assuming your default console logger threshold was lvlInfo)
  if enableTrace:
    setLogFilter(lvlDebug)

  vm.executeFile(fileName)

when isMainModule:
  main()

