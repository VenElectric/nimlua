import std/unittest
import helpers/testutils

# A general caveat worth stating up front, same as real Lua's own __gc:
# GC timing is inherently non-deterministic. These tests are supporting
# evidence that the safety net works, not airtight proof -- if one of
# these ever starts flaking, that's worth investigating on its own merits
# rather than assuming the destructor itself regressed.
#
# That said, the NON-CYCLIC cases below should actually be quite reliable:
# a temp dir/file handle with nothing self-referencing it should be
# collected via ORC's ordinary, IMMEDIATE refcounting the instant its last
# reference is popped off the stack -- not deferred to the periodic cycle
# collector at all. The explicit collectgarbage() calls are included as a
# defensive belt-and-suspenders measure, not because they're expected to be
# what actually triggers cleanup in these particular tests.

suite "=destroy: temp directories, no <close> and no explicit :remove()":
  test "a tempScoped handle that simply falls out of scope is still cleaned up":
    check runLua("""
      local savedPath
      do
        local t = dir.tempScoped("gctest_", "_d")
        savedPath = t:path()
        -- deliberately NOT using <close> and NOT calling t:remove() --
        -- this exercises the GC-time safety net specifically, not the
        -- deterministic <close> mechanism (which is already well tested).
      end
      collectgarbage(GCOption.collect)
      print(dir.exists(savedPath))
    """) == "false\n"

suite "=destroy: file handles, no <close> and no explicit :close()":
  test "data written to a dropped, never-closed handle still reaches disk":
    check runLua("""
      local savedPath = dir.temp("gctest_", "_dir")
      local filePath = savedPath .. "/out.txt"
      do
        local f = file.open(filePath, FileMode.write)
        f:write("hello from a dropped handle")
        -- deliberately NOT calling f:close() -- if the destructor never
        -- runs (or never flushes), this write may still be sitting in a
        -- buffer that never reaches disk.
      end
      collectgarbage(GCOption.collect)
      local f2 = file.open(filePath, FileMode.read)
      local contents = f2:read("a")
      f2:close()
      dir.remove(savedPath)
      print(contents)
    """) == "hello from a dropped handle\n"

suite "=destroy: the motivating scenario -- a handle trapped in a reference cycle":
  test "a temp dir held by a self-referencing table is still cleaned up by the cycle collector":
    # This is the actual scenario that motivated building =destroy at all --
    # a registry-style pattern where a table holds a handle AND references
    # itself, which ordinary refcounting alone can never collect. Unlike
    # the non-cyclic tests above, THIS one genuinely depends on the
    # periodic cycle collector actually running, which is why the explicit
    # collectgarbage() call matters much more here than in the simpler cases.
    check runLua("""
      local savedPath
      do
        local registry = {}
        local t = dir.tempScoped("gctest_", "_d")
        savedPath = t:path()
        registry.handle = t
        registry.self = registry
      end
      collectgarbage(GCOption.collect)
      print(dir.exists(savedPath))
    """) == "false\n"
