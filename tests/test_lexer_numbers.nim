import std/unittest
import helpers/testutils
import ../src/lerror

suite "number literals: hex integers":
  test "a basic hex literal parses correctly":
    check runLua("""print(0xFF == 255)""") == "true\n"

  test "a hex literal with lowercase digits":
    check runLua("""print(0x10 == 16)""") == "true\n"

  test "a hex literal with mixed-case digits":
    check runLua("""print(0x1aF == 431)""") == "true\n"

suite "number literals: exponent notation":
  test "unsigned exponent, unaffected by the sign-handling fix":
    check runLua("""print(1e10 == 10000000000)""") == "true\n"

  test "a positive-signed exponent":
    check runLua("""print(1e+2 == 100)""") == "true\n"

  test "a negative-signed exponent":
    check runLua("""print(1e-2 == 0.01)""") == "true\n"

  test "a negative-signed exponent on a non-integer base":
    check runLua("""print(2.5e-1 == 0.25)""") == "true\n"

  test "an exponent marker followed by a sign and no digits raises":
    expect LuaSyntaxError:
      discard runLua("""local x = 1e-""")

  test "an exponent marker followed by no sign and no digits raises":
    expect LuaSyntaxError:
      discard runLua("""local x = 1e)""")

  test "an exponent marker at the very end of the source raises":
    expect LuaSyntaxError:
      discard runLua("""1e""")
