import std/unittest
import helpers/testutils

suite "_G":
  test "reading a bare global through _G":
    check runLua("""
      myGlobal = 42
      print(_G.myGlobal)
    """) == "42\n"

  test "writing through _G creates a real, bare-readable global":
    check runLua("""
      _G.otherGlobal = 10
      print(otherGlobal)
    """) == "10\n"

  test "_G stays live across repeated access, not a one-time snapshot":
    check runLua("""
      x = 1
      print(_G.x)
      x = 2
      print(_G.x)
    """) == "1\n2\n"

  test "an unset global is nil, both bare and through _G":
    check runLua("""print(neverSet, _G.neverSet)""") == "nil\tnil\n"

suite "_VERSION":
  test "reports the expected version string":
    check runLua("print(_VERSION)") == "Lua 5.5\n"

suite "pairs(_G)":
  test "walks a nonzero number of entries":
    check runLua("""
      local n = 0
      for k in pairs(_G) do
        n = n + 1
      end
      print(n > 0)
    """) == "true\n"

  test "includes a global the script itself just created":
    check runLua("""
      myOwnGlobal = "hi"
      local found = false
      for k, v in pairs(_G) do
        if k == "myOwnGlobal" and v == "hi" then found = true end
      end
      print(found)
    """) == "true\n"

suite "__pairs on an ordinary table":
  test "a table's own __pairs metamethod is honored, not just _G's":
    check runLua("""
      local calls = 0
      local custom = setmetatable({}, {
        __pairs = function(t)
          calls = calls + 1
          return next, {x = 1, y = 2}, nil
        end
      })
      local n = 0
      for k, v in pairs(custom) do n = n + 1 end
      print(n, calls)
    """) == "2\t1\n"

  test "a table with no __pairs still uses ordinary raw iteration":
    check runLua("""
      local t = {a = 1, b = 2, c = 3}
      local n = 0
      for k, v in pairs(t) do n = n + 1 end
      print(n)
    """) == "3\n"

suite "semicolons as optional statement separators":
  test "semicolon between two statements on one line":
    check runLua("local a = 1; local b = 2; print(a, b)") == "1\t2\n"

  test "trailing semicolon after the last statement":
    check runLua("print(\"ok\");") == "ok\n"

  test "semicolons are optional -- identical code without them still works":
    check runLua("local a = 1 local b = 2 print(a, b)") == "1\t2\n"