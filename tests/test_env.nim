import std/unittest
import helpers/testutils
import ../src/lerror

suite "_ENV: ordinary global behavior is unaffected":
  test "a bare global read and write still works exactly as before":
    check runLua("""
      x = 5
      print(x)
    """) == "5\n"

  test "_ENV and _G are the same object at the top level":
    check runLua("""print(_ENV == _G)""") == "true\n"

suite "_ENV: real sandboxing via a local rebind":
  test "writes inside a sandboxed block never touch the real globals":
    check runLua("""
      do
        local _ENV = {print = print}
        y = 10
        print(y)
      end
      print(type(y))
    """) == "10\nnil\n"

  test "the right-hand side of 'local _ENV = ...' is evaluated in the OLD environment":
    # print on the right-hand side must resolve via the outer _ENV, since the
    # new local _ENV isn't in effect until the assignment completes -- same
    # rule as ordinary 'local x = x' shadowing.
    check runLua("""
      do
        local _ENV = {print = print}
        print("still works")
      end
    """) == "still works\n"

  test "a sandbox with __index = _G falls through for reads but stays local for writes":
    check runLua("""
      do
        local _ENV = setmetatable({}, {__index = _G})
        print("hello from sandbox")
        localOnly = "sandboxed value"
      end
      print(type(localOnly), _G.localOnly)
    """) == "hello from sandbox\nnil\tnil\n"

  test "reading an undefined name inside a sandbox with no fallback is nil, not an error":
    check runLua("""
    local result
    do
      local _ENV = {}
      result = undefinedThing
    end
    print(result == nil)
  """) == "true\n"

suite "_ENV: nested closures capture it as an ordinary upvalue":
  test "a returned closure resolves a global the same way across multiple calls":
    check runLua("""
      function makeCounter()
        count = count or 0
        return function()
          count = count + 1
          return count
        end
      end
      local c1 = makeCounter()
      print(c1(), c1(), c1())
    """) == "1\t2\t3\n"

suite "_ENV: global <const> is still enforced, now via the runtime path":
  test "reassigning a const global raises":
    check runLua("""
      global z <const> = 1
      local ok = pcall(function() z = 2 end)
      print(ok, z)
    """) == "false\t1\n"

suite "_ENV: the 'global' keyword respects sandboxing":
  test "global inside a sandboxed block writes into the sandbox, not the real globals":
    check runLua("""
      do
        local _ENV = {}
        global w = 99
      end
      print(type(w))
    """) == "nil\n"

suite "_ENV: multi-assignment mixing a local reassignment with a fresh global":
  test "the hidden-temp-local path preserves correct values for both targets":
    check runLua("""
      local a, b = 1, 2
      a, X = 3, 4
      print(a, b, X)
    """) == "3\t2\t4\n"
