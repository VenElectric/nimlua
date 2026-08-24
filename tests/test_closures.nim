import std/unittest
import helpers/testutils
import ../src/lerror

suite "closures and upvalues":
  test "basic upvalue capture":
    check runLua("""
      local function testUpvalue(x)
        return function() print(x) end
      end
      local testFn = testUpvalue(20)
      testFn()
    """) == "20\n"

  test "upvalue-of-an-upvalue, two levels deep":
    check runLua("""
      local function constTest()
        local x = "hello const"
        return function()
          return function() print(x) end
        end
      end
      local first = constTest()
      local second = first()
      second()
    """) == "hello const\n"

  test "reassigning a <const> local raises at compile time":
    expect LuaCompileError:
      discard runLua("""
        local x <const> = 5
        x = 10
      """)

  test "reassigning a <const> captured upvalue raises":
    expect LuaCompileError:
      discard runLua("""
        local function constTest()
          local x <const> = "hello const"
          return function()
            return function() x = "changed" end
          end
        end
        local first = constTest()
        local second = first()
        second()
      """)

  test "closures in a numeric-for loop each capture their own iteration value":
    check runLua("""
      local fns = {}
      for i = 1, 3 do
        fns[i] = function() return i end
        end
        print(fns[1](), fns[2](), fns[3]())
        """) == "1\t2\t3\n"

  # NOTE: deliberately not testing "closures in a numeric-for loop each
  # capture their own iteration value" here. Recall the loop variable in
  # nkNumericFor lives in the OUTER scope, declared once and overwritten
  # each iteration via opSetLocal -- unlike a while-loop body's own locals,
  # it never gets a fresh per-iteration scope. A closure capturing `i`
  # directly very likely sees whatever value `i` holds when the loop exits,
  # not a distinct value per iteration. This needs a real decision (give the
  # loop variable its own per-iteration scope, matching real Lua, vs. leaving
  # it as a documented limitation) before it's safe to pin down in a test --
  # asserting a guessed value here would be worse than not testing it at all.
