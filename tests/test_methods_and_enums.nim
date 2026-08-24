import std/unittest
import helpers/testutils

suite "method definition and call sugar":
  test "colon method receives self implicitly":
    check runLua("""
      local CLASS = {}
      function CLASS:method(x)
        return self.val + x
      end
      local obj = setmetatable({val = 10}, {__index = CLASS})
      print(obj:method(5))
    """) == "15\n"

  test "self really is the same table the method was called on":
    check runLua("""
      local CLASS = {}
      function CLASS:setVal(v) self.val = v end
      local obj = setmetatable({val = 0}, {__index = CLASS})
      obj:setVal(99)
      print(obj.val)
    """) == "99\n"

  test "dotted (non-colon) function definition":
    check runLua("""
      local t = {}
      function t.plain(x, y) return x + y end
      print(t.plain(2, 3))
    """) == "5\n"

  test "multi-segment dotted path":
    check runLua("""
      local Shapes = { Circle = {} }
      function Shapes.Circle:area(r) return r * r end
      local c = setmetatable({}, {__index = Shapes.Circle})
      print(c:area(4))
    """) == "16\n"

  test "method receiver is evaluated exactly once":
    check runLua("""
      local calls = 0
      local function getObj()
        calls = calls + 1
        return { greet = function(self) return "hi" end }
      end
      print(getObj():greet())
      print(calls)
    """) == "hi\n1\n"

suite "enum":
  test "auto-numbering starts at 1":
    check runLua("""
      local Color = enum(RED, GREEN, BLUE)
      print(Color.RED, Color.GREEN, Color.BLUE)
    """) == "1\t2\t3\n"

  test "explicit value, then continues counting from it":
    check runLua("""
      local Color = enum(RED, GREEN, BLUE = 10, PURPLE)
      print(Color.RED, Color.GREEN, Color.BLUE, Color.PURPLE)
    """) == "1\t2\t10\t11\n"

  test "reverse lookup from value back to name":
    check runLua("""
      local Color = enum(RED, GREEN, BLUE = 10)
      print(Color[10])
    """) == "BLUE\n"

  test "negative explicit values are supported":
    check runLua("""
      local Status = enum(ERROR = -1, OK = 0, PENDING)
      print(Status.ERROR, Status.OK, Status.PENDING)
    """) == "-1\t0\t1\n"

  test "enum can be used inline as an expression, not just assigned first":
    check runLua("""
      print(enum(A, B, C).B)
    """) == "2\n"

  test "member names round-trip through pairs like any ordinary table":
    check runLua("""
      local Color = enum(RED, GREEN)
      local seen = 0
      for k, v in pairs(Color) do seen = seen + 1 end
      -- 2 members * 2 entries each (forward + reverse) = 4 keys
      print(seen)
    """) == "4\n"