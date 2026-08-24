import std/unittest
import helpers/testutils
import ../src/lerror

suite "string escapes":

  test "\\n produces a real newline byte, not two literal characters":
    check runLua("""print(#"a\nb")""") == "3\n"

  test "\\t produces a real tab byte":
    check runLua("""print(#"a\tb")""") == "3\n"

  test "\\\\ produces a single backslash":
    check runLua("""print(#"a\\b")""") == "3\n"

  test "\\\" embeds a literal quote inside a double-quoted string":
    check runLua("""print("she said \"hi\"")""") == "she said \"hi\"\n"

  test "\\r, \\a, \\b, \\f, \\v are each exactly one byte":
    check runLua("""print(#"\r\a\b\f\v")""") == "5\n"

  test "\\xNN hex escape":
    check runLua("""print("\x41\x42")""") == "AB\n"

  test "\\ddd decimal escape":
    check runLua("""print("\65\66")""") == "AB\n"

  test "backslash followed by a real newline embeds one newline":
    # Built as a regular (non-triple) Nim string specifically so \n below
    # is Nim's OWN escape, producing a genuine newline byte inside the Lua
    # source text itself -- not just two visible characters in the source.
    check runLua("print(\"a\\\nb\")") == "a\nb\n"

  test "\\z skips following whitespace including newlines":
    check runLua("print(\"a\\z\n   b\")") == "ab\n"

  test "an invalid escape sequence raises a syntax error at parse time":
    expect LuaSyntaxError:
      discard runLua("""print("\q")""")