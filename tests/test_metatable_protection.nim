import std/unittest
import helpers/testutils
import ../src/lerror

suite "getmetatable/setmetatable: unprotected tables work normally":
  test "a table with no metatable returns nil":
    check runLua("""print(getmetatable({}))""") == "nil\n"

  test "getmetatable returns the REAL metatable when unprotected":
    check runLua("""
      local t = setmetatable({}, {foo = "bar"})
      print(getmetatable(t).foo)
    """) == "bar\n"

  test "setmetatable can freely change an unprotected table's metatable":
    check runLua("""
      local t = setmetatable({}, {a = 1})
      setmetatable(t, {a = 2})
      print(getmetatable(t).a)
    """) == "2\n"

suite "getmetatable/setmetatable: __metatable protection is a general mechanism":
  test "getmetatable returns the __metatable value instead of the real metatable":
    check runLua("""
      local t = setmetatable({}, {__metatable = "locked"})
      print(getmetatable(t))
    """) == "locked\n"

  test "the __metatable value is returned by identity, not copied":
    check runLua("""
      local marker = {}
      local t = setmetatable({}, {__metatable = marker})
      print(getmetatable(t) == marker)
    """) == "true\n"

  test "setmetatable on a protected table raises":
    expect LuaRuntimeError:
      discard runLua("""
        local t = setmetatable({}, {__metatable = "locked"})
        setmetatable(t, {})
      """)

  test "a blocked setmetatable attempt leaves the original metatable's behavior intact":
    check runLua("""
      local t = setmetatable({}, {__index = function() return 42 end, __metatable = "locked"})
      local ok = pcall(function() setmetatable(t, {}) end)
      print(ok, t.anything)
    """) == "false\t42\n"

suite "getmetatable/setmetatable: built-in protected tables (enums)":
  test "getmetatable on an enum returns its __metatable placeholder, not the real metatable":
    check runLua("""print(getmetatable(FileMode))""") == "false\n"

  test "setmetatable on an enum raises":
    expect LuaRuntimeError:
      discard runLua("""setmetatable(FileMode, {})""")
