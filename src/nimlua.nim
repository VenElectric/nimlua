import lvm, log, lauxlib, ltypes,lerror
import std/[logging, parseopt]

initLogging(lvlAll)



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
  try:
    vm.executeFile(fileName)
  except LuaExitError as e:
    quit(e.code)

when isMainModule:
  main()

