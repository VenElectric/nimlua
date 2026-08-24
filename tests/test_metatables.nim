import std/unittest
import helpers/testutils
import ../src/lerror

suite "arithmetic metamethods":
  test "distinct tables with identical contents are NOT equal without __eq":
    check runLua("""
    local a = {x = 1}
    local b = {x = 1}
    print(a == b)
      """) == "false\n"

  test "__add fallback, table + table":
    check runLua("""
      local Vec = {}
      Vec.__add = function(a, b) return { x = a.x + b.x, y = a.y + b.y } end
      local v1 = setmetatable({ x = 1, y = 2 }, Vec)
      local v2 = setmetatable({ x = 3, y = 4 }, Vec)
      local v3 = v1 + v2
      print(v3.x, v3.y)
    """) == "4\t6\n"

  test "__unm (unary minus)":
    check runLua("""
      local Vec = {}
      Vec.__unm = function(v) return { x = -v.x, y = -v.y } end
      local v1 = setmetatable({ x = 1, y = 2 }, Vec)
      local v5 = -v1
      print(v5.x, v5.y)
    """) == "-1\t-2\n"

  test "no metamethod at all raises":
    expect LuaRuntimeError:
      discard runLua("local x = {} + {}")

suite "__concat":
  test "table on the left":
    check runLua("""
      local Str = {}
      Str.__concat = function(a, b)
        local aval = (type(a) == "table") and a.val or tostring(a)
        local bval = (type(b) == "table") and b.val or tostring(b)
        return aval .. bval
      end
      local s1 = setmetatable({ val = "hello " }, Str)
      print(s1 .. "world")
    """) == "hello world\n"

  test "table on the right":
    check runLua("""
      local Str = {}
      Str.__concat = function(a, b)
        local aval = (type(a) == "table") and a.val or tostring(a)
        local bval = (type(b) == "table") and b.val or tostring(b)
        return aval .. bval
      end
      local s1 = setmetatable({ val = "hello" }, Str)
      print("say: " .. s1)
    """) == "say: hello\n"

suite "__eq":
  test "different objects, same contents, via __eq":
    check runLua("""
      local Pt = {}
      Pt.__eq = function(a, b) return a.x == b.x and a.y == b.y end
      local p1 = setmetatable({ x = 1, y = 1 }, Pt)
      local p2 = setmetatable({ x = 1, y = 1 }, Pt)
      print(p1 == p2)
    """) == "true\n"

  test "same object short-circuits before __eq":
    check runLua("""
      local p1 = setmetatable({ x = 1 }, { __eq = function() return false end })
      print(p1 == p1)
    """) == "true\n"

  test "mismatched kinds never call __eq":
    check runLua("""
      local p1 = setmetatable({ x = 1 }, {})
      print(p1 == 5)
    """) == "false\n"

suite "__lt / __le":
  test "ordering via __lt and __le":
    check runLua("""
      local Ord = {}
      Ord.__lt = function(a, b) return a.n < b.n end
      Ord.__le = function(a, b) return a.n <= b.n end
      local o1 = setmetatable({ n = 1 }, Ord)
      local o2 = setmetatable({ n = 2 }, Ord)
      print(o1 < o2, o2 < o1, o1 <= o1, o2 > o1, o1 >= o2)
    """) == "true\tfalse\ttrue\ttrue\tfalse\n"

suite "__len":
  test "takes priority over raw table length":
    check runLua("""
      local t = setmetatable({1, 2, 3}, {__len = function() return 99 end})
      print(#t)
    """) == "99\n"

  test "plain table still uses raw length":
    check runLua("print(#{1, 2, 3})") == "3\n"

suite "__index / __newindex":
  test "__index as a table (prototype-style inheritance)":
    check runLua("""
      local CLASS = { greeting = "hi" }
      local obj = setmetatable({}, { __index = CLASS })
      print(obj.greeting)
    """) == "hi\n"

  test "__index as a function":
    check runLua("""
      local mt = { __index = function(t, k) return "computed:" .. k end }
      local x = setmetatable({}, mt)
      print(x.anything)
    """) == "computed:anything\n"

  test "__newindex as a function prevents the raw assignment":
    check runLua("""
      local log = {}
      local mt = { __newindex = function(t, k, v) log[k] = v end }
      local x = setmetatable({}, mt)
      x.a = 1
      print(rawget(x, "a"), log.a)
    """) == "nil\t1\n"

  test "cyclic __index chain raises instead of hanging":
    expect LuaRuntimeError:
      discard runLua("""
        local a = {}
        local b = {}
        setmetatable(a, { __index = b })
        setmetatable(b, { __index = a })
        print(a.missing)
      """)
