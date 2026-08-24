import std/unittest
import helpers/testutils
import ../src/lerror

suite "string.byte":
  test "no position defaults to the first byte only":
    check runLua("""print(string.byte("abc"))""") == "97\n"

  test "a single explicit position":
    check runLua("""print(string.byte("abc", 2))""") == "98\n"

  test "negative position counts from the end":
    check runLua("""print(string.byte("abc", -1))""") == "99\n"

  test "an out-of-range end position clamps instead of erroring":
    check runLua("""print(string.byte("abc", 1, 100))""") == "97\t98\t99\n"

  test "an inverted range (start after end) returns nothing":
    check runLua("""print(string.byte("abc", 3, 1))""") == "\n"

  test "an empty string returns nothing":
    check runLua("""print(string.byte(""))""") == "\n"

  test "wrong argument type raises":
    expect LuaRuntimeError:
      discard runLua("""string.byte(5)""")

  test "too many arguments raises":
    expect LuaRuntimeError:
      discard runLua("""string.byte("a", 1, 2, 3)""")

suite "string.char":
  test "builds a string from byte codes":
    check runLua("""print(string.char(65, 66, 67))""") == "ABC\n"

  test "zero arguments gives an empty string":
    check runLua("""print(string.char())""") == "\n"

  test "a value above 255 raises":
    expect LuaRuntimeError:
      discard runLua("""string.char(256)""")

  test "a negative value raises":
    expect LuaRuntimeError:
      discard runLua("""string.char(-1)""")

  test "a non-number argument raises":
    expect LuaRuntimeError:
      discard runLua("""string.char("x")""")

suite "string.len":
  test "counts bytes":
    check runLua("""print(string.len("hello"))""") == "5\n"

  test "an empty string has length 0":
    check runLua("""print(string.len(""))""") == "0\n"

  test "wrong argument type raises":
    expect LuaRuntimeError:
      discard runLua("""string.len(5)""")

  test "wrong argument count raises":
    expect LuaRuntimeError:
      discard runLua("""string.len("a", "b")""")

suite "string.lower":
  test "lowercases ASCII letters":
    check runLua("""print(string.lower("HELLO"))""") == "hello\n"

  test "non-letters pass through unchanged":
    check runLua("""print(string.lower("Hello123!"))""") == "hello123!\n"

suite "string.upper":
  test "uppercases ASCII letters":
    check runLua("""print(string.upper("hello"))""") == "HELLO\n"

  test "non-letters pass through unchanged":
    check runLua("""print(string.upper("Hello123!"))""") == "HELLO123!\n"

suite "string.reverse":
  test "reverses an ordinary string":
    check runLua("""print(string.reverse("hello"))""") == "olleh\n"

  test "an empty string reverses to itself":
    check runLua("""print(string.reverse(""))""") == "\n"

  test "a single character reverses to itself":
    check runLua("""print(string.reverse("a"))""") == "a\n"

suite "string.rep":
  test "repeats with no separator":
    check runLua("""print(string.rep("ab", 3))""") == "ababab\n"

  test "repeats with a separator, never trailing":
    check runLua("""print(string.rep("ab", 3, "-"))""") == "ab-ab-ab\n"

  test "zero repetitions gives an empty string":
    check runLua("""print(string.rep("x", 0))""") == "\n"

  test "negative count gives an empty string":
    check runLua("""print(string.rep("x", -5))""") == "\n"

  test "a huge count on a short string raises (overflow-safe count check)":
    expect LuaRuntimeError:
      discard runLua("""string.rep("x", 10000000)""")

  test "a modest count with a huge separator still raises (separator-aware size check)":
    # Builds a large separator via a rep call that does NOT itself exceed the
    # limit, then uses it to push a small/short rep call over the top --
    # specifically exercises the SECOND size check, not the first.
    expect LuaRuntimeError:
      discard runLua("""
        local hugeSep = string.rep("y", 50000)
        string.rep("x", 100, hugeSep)
      """)

suite "string.find (plain mode only -- pattern matching is not yet implemented; plain defaults to true for now)":
  test "the simplest call shape now works without needing an explicit plain flag":
    check runLua("""print(string.find("hello world", "world"))""") == "7\t11\n"

  test "finds a literal substring":
    check runLua("""print(string.find("hello world", "world", 1, true))""") == "7\t11\n"

  test "search starting from a given position":
    check runLua("""print(string.find("hello", "l", 4, true))""") == "4\t4\n"

  test "no match returns nil":
    check runLua("""print(string.find("hello", "xyz", 1, true))""") == "nil\n"

  test "nil init falls back to the default (start of string)":
    check runLua("""print(string.find("hello", "l", nil, true))""") == "3\t3\n"

  test "negative init counts from the end":
    check runLua("""print(string.find("hello", "o", -1, true))""") == "5\t5\n"

  test "an init beyond the string's length returns nil rather than erroring":
    check runLua("""print(string.find("hello", "x", 100, true))""") == "nil\n"

  test "plain mode treats pattern metacharacters as literal text":
    check runLua("""print(string.find("a.b.c", ".", 1, true))""") == "2\t2\n"

  test "wrong argument count raises":
    expect LuaRuntimeError:
      discard runLua("""string.find("only one arg")""")

  test "wrong argument type raises":
    expect LuaRuntimeError:
      discard runLua("""string.find(5, "x")""")


