import std/unittest
import helpers/testutils
import ../src/lerror

suite "coroutine.close: running pending <close> handlers":
  test "a suspended coroutine's pending __close handler actually runs":
    check runLua("""
      local co = coroutine.create(function()
        local t <close> = setmetatable({}, {__close = function() print("cleaning up") end})
        coroutine.yield()
      end)
      coroutine.resume(co)
      print(coroutine.close(co))
      print(coroutine.status(co))
    """) == "cleaning up\ntrue\ndead\n"

  test "a <close> local that already exited its scope is NOT closed a second time":
    # The do...end block forces the <close> local out of scope BEFORE the
    # yield, so opCloseValue runs its handler and marks the slot. If
    # "scoped close" printed again after the marker line, that marking
    # isn't taking effect.
    check runLua("""
      local co = coroutine.create(function()
        do
          local t <close> = setmetatable({}, {__close = function() print("scoped close") end})
          print("inside scope")
        end
        print("after scope")
        coroutine.yield()
      end)
      coroutine.resume(co)
      print("--- now closing ---")
      coroutine.close(co)
    """) == "inside scope\nscoped close\nafter scope\n--- now closing ---\n"

  test "multiple pending handlers run in reverse declaration order":
    check runLua("""
      local co = coroutine.create(function()
        local a <close> = setmetatable({}, {__close = function() print("closing A") end})
        local b <close> = setmetatable({}, {__close = function() print("closing B") end})
        coroutine.yield()
      end)
      coroutine.resume(co)
      coroutine.close(co)
    """) == "closing B\nclosing A\n"

suite "coroutine.close: error handling":
  test "a raising __close handler returns false plus the error, rather than propagating":
    check runLua("""
      local co = coroutine.create(function()
        local t <close> = setmetatable({}, {__close = function() error("close failed") end})
        coroutine.yield()
      end)
      coroutine.resume(co)
      local ok, err = coroutine.close(co)
      print(ok, err)
    """) == "false\tclose failed\n"

suite "coroutine.close: status validation":
  test "closing an already-dead coroutine succeeds":
    check runLua("""
      local co = coroutine.create(function() end)
      coroutine.resume(co)
      print(coroutine.status(co))
      print(coroutine.close(co))
    """) == "dead\ntrue\n"

  test "a closed coroutine reports dead and cannot be resumed":
    check runLua("""
      local co = coroutine.create(function() coroutine.yield() end)
      coroutine.resume(co)
      coroutine.close(co)
      print(coroutine.status(co))
      print(coroutine.resume(co))
    """) == "dead\nfalse\tcannot resume dead coroutine\n"

  test "closing a running coroutine from inside itself raises":
    check runLua("""
      local co
      co = coroutine.create(function()
        print(pcall(function() return coroutine.close(co) end))
      end)
      coroutine.resume(co)
    """) == "false\tline 3: cannot close a running coroutine\n"

  test "close rejects a non-coroutine argument":
    expect LuaRuntimeError:
      discard runLua("""coroutine.close(42)""")

suite "coroutine.wrap":
  test "the wrapped function returns yielded values WITHOUT a leading success boolean":
    check runLua("""
      local gen = coroutine.wrap(function()
        coroutine.yield(1)
        coroutine.yield(2)
        return 3
      end)
      print(gen())
      print(gen())
      print(gen())
    """) == "1\n2\n3\n"

  test "arguments passed to the wrapped function reach the coroutine":
    check runLua("""
      local f = coroutine.wrap(function(a, b)
        coroutine.yield(a + b)
      end)
      print(f(3, 4))
    """) == "7\n"

    test "an error inside the coroutine is RAISED, not returned as false":
      check runLua("""
      local f = coroutine.wrap(function() error("boom") end)
      local ok, err = pcall(f)
      print(ok, err)
    """) == "false\tline 1: boom\n"

  test "wrap rejects a non-function argument":
    expect LuaRuntimeError:
      discard runLua("""coroutine.wrap(42)""")

suite "coroutine.isyieldable":
  test "false at the top level, outside any coroutine":
    check runLua("""print(coroutine.isyieldable())""") == "false\n"

  test "true inside a running coroutine, at its own top level":
    check runLua("""
      local co = coroutine.create(function()
        print(coroutine.isyieldable())
      end)
      coroutine.resume(co)
    """) == "true\n"

  test "false inside a pcall within a coroutine -- a real C-call boundary":
    check runLua("""
      local co = coroutine.create(function()
        pcall(function() print(coroutine.isyieldable()) end)
      end)
      coroutine.resume(co)
    """) == "false\n"

  test "a suspended coroutine passed explicitly reports true":
    check runLua("""
      local co = coroutine.create(function() coroutine.yield() end)
      coroutine.resume(co)
      print(coroutine.isyieldable(co))
    """) == "true\n"

  test "a dead coroutine passed explicitly reports false":
    check runLua("""
      local co = coroutine.create(function() end)
      coroutine.resume(co)
      print(coroutine.isyieldable(co))
    """) == "false\n"

suite "coroutine.running":
  test "at the top level, returns nil plus true (this IS the main thread)":
    check runLua("""print(coroutine.running())""") == "nil\ttrue\n"

  test "inside a coroutine, returns a thread plus false":
    check runLua("""
      local co = coroutine.create(function()
        local self, isMain = coroutine.running()
        print(type(self), isMain)
      end)
      coroutine.resume(co)
    """) == "thread\tfalse\n"

  test "the value returned inside a coroutine is that same coroutine":
    check runLua("""
      local co
      co = coroutine.create(function()
        print(coroutine.running() == co)
      end)
      coroutine.resume(co)
    """) == "true\n"
