import std/unittest
import helpers/testutils
import ../src/lerror

suite "process.getenv":
  test "a variable that almost certainly exists returns a string":
    check runLua("""print(type(process.getenv("PATH")))""") == "string\n"

  test "a variable that almost certainly does not exist returns nil":
    check runLua("""print(process.getenv("THIS_VAR_SHOULD_NOT_EXIST_98765"))""") == "nil\n"

suite "process.execute (sandboxed by default)":
  test "raises because allowExecute defaults to false":
    expect LuaRuntimeError:
      discard runLua("""process.execute("echo hi")""")

  # NOTE: nothing here confirms execute actually WORKS once enabled --
  # runLua's harness has no way to flip vm.processCaps before interpret()
  # runs. Worth a harness extension later (e.g. a runLuaVM variant that lets
  # you touch vm state before execution) if that path needs direct coverage.

suite "process.exit":
  test "raises LuaExitError, not an ordinary runtime error":
    expect LuaExitError:
      discard runLua("process.exit()")

  test "no arguments defaults to exit code 0":
    var code = -1
    try:
      discard runLua("process.exit()")
    except LuaExitError as e:
      code = e.code
    check code == 0

  test "exit(false) maps to exit code 1":
    var code = -1
    try:
      discard runLua("process.exit(false)")
    except LuaExitError as e:
      code = e.code
    check code == 1

  test "exit(true) maps to exit code 0":
    var code = -1
    try:
      discard runLua("process.exit(true)")
    except LuaExitError as e:
      code = e.code
    check code == 0

  test "an explicit numeric code passes through unchanged":
    var code = -1
    try:
      discard runLua("process.exit(42)")
    except LuaExitError as e:
      code = e.code
    check code == 42

  test "exit propagates straight through pcall, uncaught":
    var code = -1
    var pcallReturned = false
    try:
      discard runLua("""
        local ok = pcall(function() process.exit(7) end)
        print("should never print", ok)
      """)
      pcallReturned = true
    except LuaExitError as e:
      code = e.code
    check not pcallReturned
    check code == 7
