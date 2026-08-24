import std/unittest
import helpers/testutils
import ../src/lerror

# Running example throughout: "café" = c, a, f, é (4 characters, 5 bytes).
# c=byte1, a=byte2, f=byte3, é=bytes4-5 (a 2-byte character).
# A malformed example: "a\x80b" -- 0x80 is a lone continuation byte with
# nothing before it to continue, invalid at (1-based) byte position 2.
#
# NOTE: hex integer literals (0x...) do not currently parse in this
# interpreter -- every codepoint constant below is written in decimal.
# 128512 = 0x1F600 (an emoji, 4-byte UTF-8), 1114112 = 0x110000 (one past
# the max valid codepoint), 55296 = 0xD800 (start of the surrogate range).

suite "unicode.char":
  test "encodes a multi-byte (4-byte) codepoint correctly":
    check runLua("""
      local s = unicode.char(0x1F600)
      print(#s, unicode.len(s))
    """) == "4\t1\tnil\n"
 
  test "a value above the Unicode range raises":
    expect LuaRuntimeError:
      discard runLua("""unicode.char(0x110000)""")
 
  test "a surrogate value raises":
    expect LuaRuntimeError:
      discard runLua("""unicode.char(0xD800)""")
 
  test "a non-number argument raises":
    expect LuaRuntimeError:
      discard runLua("""unicode.char("x")""")

suite "unicode.len":
  test "counts characters, not bytes":
    check runLua("""print(unicode.len("café"))""") == "4\tnil\n"

  test "counts characters starting within a given byte range":
    check runLua("""print(unicode.len("café", 1, 3))""") == "3\tnil\n"

  test "a character counts if it merely STARTS within the range":
    check runLua("""print(unicode.len("café", 4, 5))""") == "1\tnil\n"

  test "malformed UTF-8 returns nil plus the 1-based byte position":
    check runLua("""print(unicode.len("a\x80b"))""") == "nil\t2\n"

  test "an out-of-bounds initial position raises":
    expect LuaRuntimeError:
      discard runLua("""unicode.len("hi", 50)""")

suite "unicode.valid":
  test "a well-formed string returns nil":
    check runLua("""print(unicode.valid("café"))""") == "nil\n"

  test "a malformed string returns the 1-based byte position":
    check runLua("""print(unicode.valid("a\x80b"))""") == "2\n"

suite "unicode.upper / unicode.lower":
  test "upper is genuinely Unicode-aware, not ASCII-only":
    check runLua("""print(unicode.upper("café"))""") == "CAFÉ\tnil\n"

  test "lower is genuinely Unicode-aware, not ASCII-only":
    check runLua("""print(unicode.lower("CAFÉ"))""") == "café\tnil\n"

  test "upper on malformed input returns nil plus position":
    check runLua("""print(unicode.upper("a\x80b"))""") == "nil\t2\n"

  test "lower on malformed input returns nil plus position":
    check runLua("""print(unicode.lower("a\x80b"))""") == "nil\t2\n"

suite "unicode.reverse":
  test "reverses by character, not by byte":
    check runLua("""print(unicode.reverse("café"))""") == "éfac\tnil\n"

  test "on malformed input returns nil plus position":
    check runLua("""print(unicode.reverse("a\x80b"))""") == "nil\t2\n"

suite "unicode.codepoint":
  test "decodes a single ASCII character by default (j defaults to the resolved i)":
    check runLua("""print(unicode.codepoint("café", 1))""") == "99\n"

  test "decodes a multi-byte character correctly":
    check runLua("""print(unicode.codepoint("café", 4))""") == "233\n"

  test "decodes a full range as multiple return values":
    check runLua("""print(unicode.codepoint("hi", 1, 2))""") == "104\t105\n"

  test "malformed input returns nil plus position":
    check runLua("""print(unicode.codepoint("a\x80b", 1, 3))""") == "nil\t2\n"

suite "unicode.sub":
  test "indexes by CHARACTER, not by byte":
    check runLua("""print(unicode.sub("café", 1, 3))""") == "caf\tnil\n"

  test "negative position counts from the end":
    check runLua("""print(unicode.sub("café", -1))""") == "é\tnil\n"

  test "an out-of-range span clamps to empty, rather than raising":
    check runLua("""print(unicode.sub("café", 10, 20))""") == "\tnil\n"

  test "malformed input returns nil plus position":
    check runLua("""print(unicode.sub("a\x80b", 1))""") == "nil\t2\n"

suite "unicode.offset":
  test "n=1 with the default i returns the start of the first character":
    check runLua("""print(unicode.offset("café", 1))""") == "1\n"

  test "n=-1 finds the start of the LAST character":
    check runLua("""print(unicode.offset("café", -1))""") == "4\n"

  test "n=0 snaps a mid-character byte position back to that character's start":
    check runLua("""print(unicode.offset("café", 0, 5))""") == "4\n"

  test "asking for a character past the end returns nil, not an error":
    check runLua("""print(unicode.offset("hi", 5))""") == "nil\n"

  test "an out-of-bounds initial position raises":
    expect LuaRuntimeError:
      discard runLua("""unicode.offset("hi", 1, 50)""")

suite "unicode.codes":
  test "iterates every character with correct byte positions and codepoints":
    check runLua("""
      local out = {}
      for p, c in unicode.codes("café") do
        table.insert(out, tostring(p) .. ":" .. tostring(c))
      end
      print(table.concat(out, ","))
    """) == "1:99,2:97,3:102,4:233\n"

  test "malformed input raises before any iteration happens":
    expect LuaRuntimeError:
      discard runLua("""
        for p, c in unicode.codes("a\x80b") do
          print("should never print")
        end
      """)

suite "unicode character classification":
  test "isalpha true for a letter, false for a space":
    check runLua("""print(unicode.isalpha(65), unicode.isalpha(32))""") == "true\tfalse\n"

  test "isspace true for a space, false for a letter":
    check runLua("""print(unicode.isspace(32), unicode.isspace(65))""") == "true\tfalse\n"

  test "isupper / islower distinguish case correctly":
    check runLua("""
      print(unicode.isupper(65), unicode.isupper(97))
      print(unicode.islower(97), unicode.islower(65))
    """) == "true\tfalse\ntrue\tfalse\n"

  test "an out-of-range codepoint raises":
    expect LuaRuntimeError:
      discard runLua("""unicode.isalpha(1114112)""")

  test "a non-number argument raises":
    expect LuaRuntimeError:
      discard runLua("""unicode.isalpha("x")""")