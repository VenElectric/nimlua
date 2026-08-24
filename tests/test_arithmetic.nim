import std/unittest
import helpers/testutils
import ../src/lerror

suite "comparison boundaries":
  # This exact pair caught the swapped >/>= implementation bug.
  test "> and >= at the exact boundary":
    check runLua("print(5 > 5)") == "false\n"
    check runLua("print(5 >= 5)") == "true\n"

  test "> and >= off the boundary":
    check runLua("print(9 > 10)") == "false\n"
    check runLua("print(10 > 9)") == "true\n"
    check runLua("print(10 >= 10)") == "true\n"

suite "integer / float negation":
  # Caught the isNumber-before-isInteger ordering bug (opNegate FieldDefect).
  test "negating a plain integer literal does not crash":
    check runLua("print(-5)") == "-5\n"

  test "negating a float":
    check runLua("print(-5.0)") == "-5.0\n"

  test "negation does not double-pop the stack":
    check runLua("""
      local a = 100
      local b = -5
      print(a, b)
    """) == "100\t-5\n"

suite "modulo sign convention":
  # Caught both the original float luaMod regression and its integer twin.
  test "negative dividend, positive divisor":
    check runLua("print(-5 % 3)") == "1\n"

  test "positive dividend, negative divisor":
    check runLua("print(5 % -3)") == "-1\n"

  test "float modulo follows the same rule":
    check runLua("print(-5.0 % 3.0)") == "1.0\n"

suite "integer/float subtype":
  test "int + int stays int":
    check runLua("print(1 + 1)") == "2\n"

  test "int + float promotes to float":
    check runLua("print(1 + 0.5)") == "1.5\n"

  test "exponentiation always produces a float":
    check runLua("print(18 ^ 2)") == "324.0\n"
    check runLua("print(2 ^ -1)") == "0.5\n"

  test "integer and float keys unify in a table":
    check runLua("""
      local t = {}
      t[1] = "x"
      print(t[1.0])
    """) == "x\n"

suite "floor division":
  test "integer floor division floors toward negative infinity, not zero":
    check runLua("print(-7 // 2)") == "-4\n"

  test "floor division by zero raises":
    expect LuaRuntimeError:
      discard runLua("print(1 // 0)")
