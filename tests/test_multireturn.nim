import std/unittest
import helpers/testutils

suite "multi-return":
  test "local a, b = f() binds both values":
    check runLua("""
      local function two() return 1, 2 end
      local a, b = two()
      print(a, b)
    """) == "1\t2\n"

  test "ordinary call in a non-last position is clamped to one value":
    check runLua("""
      local function two() return 1, 2 end
      print(two(), "x")
    """) == "1\tx\n"

  test "extra names beyond available values are nil":
    check runLua("""
      local function one() return 1 end
      local a, b, c = one()
      print(a, b, c)
    """) == "1\tnil\tnil\n"

suite "spread-in-calls":
  test "assert's other truthy arguments reach print's argument list":
    check runLua("""print(assert(1, "ok", 3))""") == "1\tok\t3\n"

  test "table.unpack spreads into a call":
    check runLua("""print(table.unpack({1, 2, 3}))""") == "1\t2\t3\n"

  test "vararg forwarding spreads as separate arguments":
    check runLua("""
      local function f(...) print(...) end
      f(1, 2, 3)
    """) == "1\t2\t3\n"

suite "return f() tail-forwarding":
  test "wrapper forwards all of inner's return values":
    check runLua("""
      local function inner() return 1, 2 end
      local function wrapper() return inner() end
      local a, b = wrapper()
      print(a, b)
    """) == "1\t2\n"

  test "method call in tail position forwards all values too":
    check runLua("""
      local CLASS = {}
      function CLASS:pair() return 1, 2 end
      local obj = setmetatable({}, {__index = CLASS})
      function CLASS:wrapper() return self:pair() end
      print(obj:wrapper())
    """) == "1\t2\n"
