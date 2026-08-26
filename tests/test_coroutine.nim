import std/unittest
import helpers/testutils
import ../src/lerror

suite "coroutine: the core multi-value yield/resume round-trip":
  test "state and values are preserved correctly across several resumes":
    check runLua("""
      local co = coroutine.create(function(a, b)
        print("start", a, b)
        local x = coroutine.yield(a + b)
        print("resumed with", x)
        local y = coroutine.yield(x * 2)
        print("resumed with", y)
        return "done"
      end)

      print(coroutine.resume(co, 1, 2))
      print(coroutine.status(co))
      print(coroutine.resume(co, 10))
      print(coroutine.resume(co, 99))
      print(coroutine.status(co))
      print(coroutine.resume(co))
    """) == "start\t1\t2\ntrue\t3\nsuspended\nresumed with\t10\ntrue\t20\nresumed with\t99\ntrue\tdone\ndead\nfalse\tcannot resume dead coroutine\n"

suite "coroutine: status transitions":
  test "suspended before first resume, suspended after yield, dead after return":
    check runLua("""
      local co = coroutine.create(function()
        coroutine.yield()
      end)
      print(coroutine.status(co))
      coroutine.resume(co)
      print(coroutine.status(co))
      coroutine.resume(co)
      print(coroutine.status(co))
    """) == "suspended\nsuspended\ndead\n"

  test "resuming itself from inside its own body reports non-suspended":
    check runLua("""
      local co
      co = coroutine.create(function()
        print(coroutine.resume(co))
      end)
      coroutine.resume(co)
    """) == "false\tcannot resume non-suspended coroutine\n"

suite "coroutine: error handling":
  test "an uncaught error inside the coroutine surfaces through resume, and marks it dead":
    check runLua("""
    local co = coroutine.create(function() error("boom") end)
    print(coroutine.resume(co))
    print(coroutine.status(co))
  """) == "false\tline 1: boom\ndead\n"

  test "yielding from outside any coroutine raises":
    check runLua("""
    local ok, err = pcall(function() coroutine.yield(1) end)
    print(ok, err)
  """) == "false\tline 1: attempt to yield from outside a coroutine\n"

  test "yielding across a pcall boundary inside a coroutine raises, catchable by that pcall":
    check runLua("""
    local co = coroutine.create(function()
      local ok, err = pcall(function()
        coroutine.yield(1)
      end)
      return ok, err
    end)
    print(coroutine.resume(co))
  """) == "true\tfalse\tline 3: attempt to yield across a C-call boundary\n"