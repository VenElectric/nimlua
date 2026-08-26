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

suite "string.find":
  # `plain` correctly defaults to false again (matching real Lua) now that
  # real pattern matching exists -- calls with no 4th argument below go
  # through the REAL matcher, not a hardcoded plain-substring path.

  test "no pattern metacharacters -- plain-looking search now goes through the real matcher":
    check runLua("""print(string.find("hello world", "world"))""") == "7\t11\n"

  test "explicit plain=true still forces literal substring search":
    check runLua("""print(string.find("hello world", "world", 1, true))""") == "7\t11\n"

  test "plain mode treats pattern metacharacters as literal text":
    check runLua("""print(string.find("a.b.c", ".", 1, true))""") == "2\t2\n"

  test "search starting from a given position (plain mode)":
    check runLua("""print(string.find("hello", "l", 4, true))""") == "4\t4\n"

  test "no match returns nil":
    check runLua("""print(string.find("hello", "xyz", 1, true))""") == "nil\n"

  test "nil init falls back to the default (start of string)":
    check runLua("""print(string.find("hello", "l", nil, true))""") == "3\t3\n"

  test "negative init counts from the end":
    check runLua("""print(string.find("hello", "o", -1, true))""") == "5\t5\n"

  test "an init beyond the string's length returns nil rather than erroring":
    check runLua("""print(string.find("hello", "x", 100, true))""") == "nil\n"

  test "wrong argument count raises":
    expect LuaRuntimeError:
      discard runLua("""string.find("only one arg")""")

  test "wrong argument type raises":
    expect LuaRuntimeError:
      discard runLua("""string.find(5, "x")""")

  test "a real pattern (character class + quantifier) finds the first run of letters":
    check runLua("""print(string.find("hello world", "%a+", 1))""") == "1\t5\n"

  test "multiple captures are returned alongside start/end":
    check runLua("""print(string.find("key=value", "(%a+)=(%a+)"))""") == "1\t9\tkey\tvalue\n"

  test "'^' genuinely anchors to the start in find (unlike gmatch)":
    check runLua("""print(string.find("abc", "^b"))""") == "nil\n"

suite "string.match":
  test "no explicit captures -- falls back to the whole match":
    check runLua("""print(string.match("hello", "%a+"))""") == "hello\n"

  test "explicit captures are returned instead of the whole match":
    check runLua("""print(string.match("key=value", "(%a+)=(%a+)"))""") == "key\tvalue\n"

  test "no match returns nil":
    check runLua("""print(string.match("hello", "%d+"))""") == "nil\n"

suite "string.gmatch":
  test "iterates every run of alphanumerics as a key=value pair":
    check runLua("""
      local out = {}
      for k, v in string.gmatch("key1=val1,key2=val2", "(%w+)=(%w+)") do
        table.insert(out, k .. ":" .. v)
      end
      print(table.concat(out, ","))
    """) == "key1:val1,key2:val2\n"

  test "'^' does NOT anchor inside gmatch -- it's treated as a literal character":
    # Documented, deliberate real-Lua behavior: an anchor would prevent
    # iteration entirely, so gmatch specifically disables it.
    check runLua("""
      local out = {}
      for a in string.gmatch("aaa", "^a") do table.insert(out, a) end
      print(table.concat(out, ","))
    """) == "a,a,a\n"

  test "'$' still functions as a real anchor inside gmatch, unlike '^'":
    check runLua("""
      local out = {}
      for a in string.gmatch("aaa", "a$") do table.insert(out, a) end
      print(table.concat(out, ","))
    """) == "a\n"

  test "a pattern that can match an empty string still terminates (forward-progress guard)":
    check runLua("""
      local n = 0
      for m in string.gmatch("abc", "x*") do n = n + 1 end
      print(n > 0)
    """) == "true\n"

suite "string.gsub":
  test "plain string replacement, with a match count":
    check runLua("""print(string.gsub("hello world", "o", "0"))""") == "hell0 w0rld\t2\n"

  test "function replacement receives the capture (or whole match) and its return replaces it":
    check runLua("""print(string.gsub("hello world", "(%w+)", string.upper))""") == "HELLO WORLD\t2\n"

  test "table replacement looks up the first capture as a key":
    check runLua("""
      print(string.gsub("$name is $age", "%$(%w+)", {name = "Bob", age = "30"}))
    """) == "Bob is 30\t2\n"

  test "the optional 4th argument limits the number of substitutions":
    check runLua("""print(string.gsub("hello", "l", "L", 1))""") == "heLlo\t1\n"

  test "a pattern that can match empty strings substitutes at every position, including the ends":
    check runLua("""print(string.gsub("abc", "x*", "-"))""") == "-a-b-c-\t4\n"

suite "pattern features: %b (balanced match)":
  test "matches nested parentheses correctly, not just the first closing paren":
    check runLua("""print(string.match("(foo (bar) baz)", "%b()"))""") == "(foo (bar) baz)\n"

suite "pattern features: %f (frontier)":
  test "finds a transition into a lowercase run":
    check runLua("""print(string.find("THE quick fox", "%f[%l]%l+"))""") == "5\t9\n"

suite "pattern features: %1-%9 (pattern back-reference)":
  test "requires the subject to contain an exact repeat of an earlier capture":
    check runLua("""print(string.match("hello hello", "(%a+) %1"))""") == "hello\n"

  test "a non-repeated phrase does not match":
    check runLua("""print(string.match("hello world", "(%a+) %1"))""") == "nil\n"