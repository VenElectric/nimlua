import std/[unittest, os]
import helpers/testutils
import ../src/lerror

const TestFile = "test_lua_file_temp.txt"

proc cleanup() =
  try: removeFile(TestFile)
  except: discard

suite "file: open / write / read round-trip":
  setup: cleanup()
  teardown: cleanup()

  test "write then read back the same contents":
    check runLua("""
      local f = file.open('""" & TestFile & """', FileMode.write)
      f:write("hello world")
      f:close()
      local f2 = file.open('""" & TestFile & """', FileMode.read)
      print(f2:read("a"))
      f2:close()
    """) == "hello world\n"

  test "opening a nonexistent file for reading returns nil + an error message, not a crash":
    check runLua("""
      local f, err = file.open("this_file_should_not_exist_12345.txt", FileMode.read)
      print(f, err ~= nil)
    """) == "nil\ttrue\n"

  test "using a closed file raises cleanly":
    check runLua("""
      local f = file.open('""" & TestFile & """', FileMode.write)
      f:close()
      local ok = pcall(function() f:write("x") end)
      print(ok)
    """) == "false\n"

suite "file: FileMode enum":
  test "forward lookup gives an integer, reverse lookup gives the name back":
    check runLua("""
      print(FileMode.read)
      print(FileMode[1])
    """) == "1\nread\n"

suite "file: lines iteration":
  setup: cleanup()
  teardown: cleanup()

  test "iterates one line at a time via a stateful closure, not the full iterator protocol":
    check runLua("""
    local f = file.open('""" & TestFile & """', FileMode.write)
    f:write([[line1
line2
line3]])
    f:close()
    local f2 = file.open('""" & TestFile & """', FileMode.read)
    local count = 0
    for line in f2:lines() do
      count = count + 1
    end
    f2:close()
    print(count)
  """) == "3\n"

suite "file: append mode":
  setup: cleanup()
  teardown: cleanup()

  test "append adds to existing content instead of truncating it":
    check runLua("""
      local f = file.open('""" & TestFile & """', FileMode.write)
      f:write("first")
      f:close()
      local f2 = file.open('""" & TestFile & """', FileMode.append)
      f2:write("second")
      f2:close()
      local f3 = file.open('""" & TestFile & """', FileMode.read)
      print(f3:read("a"))
      f3:close()
    """) == "firstsecond\n"

suite "file.stdout shares vm.output with print":
  test "print and file.stdout:write interleave into the same captured stream":
    check runLua("""
      print("a")
      file.stdout:write("b")
      print("c")
    """) == "a\nbc\n"

  test "file.stdout:close() is a no-op -- print still works afterward":
    check runLua("""
      file.stdout:close()
      print("still works")
    """) == "still works\n"

suite "file: <close> attribute":
  setup: cleanup()
  teardown: cleanup()

  test "a <close> file handle is actually closed (and flushed) when its scope ends":
    # This is the regression test for the opCloseValue fix -- native (non-Lua)
    # __close handlers were previously silently skipped entirely. Without that
    # fix, this write might never reach disk before the read below runs.
    check runLua("""
      do
        local f <close> = file.open('""" & TestFile & """', FileMode.write)
        f:write("closed via scope")
      end
      local f2 = file.open('""" & TestFile & """', FileMode.read)
      print(f2:read("a"))
      f2:close()
    """) == "closed via scope\n"

proc countLuaTmpFiles(): int =
  result = 0
  for f in walkFiles(getTempDir() / "lua_tmp_*.tmp"):
    inc result

suite "file: tmpfile":
  test "creates a real, writable file that can be closed without error":
    check runLua("""
      local f = file.tmpfile()
      f:write("hello tmpfile")
      f:close()
      print("ok")
    """) == "ok\n"

  test "the underlying file is removed once closed":
    let before = countLuaTmpFiles()
    discard runLua("""
      local f = file.tmpfile()
      f:write("data")
      f:close()
    """)
    let after = countLuaTmpFiles()
    check after == before

  test "using a tmpfile handle after close raises, same as an ordinary file":
    expect LuaRuntimeError:
      discard runLua("""
        local f = file.tmpfile()
        f:close()
        f:write("should fail")
      """)

  test "type() reports 'file' for a tmpfile handle, same as file.open":
    check runLua("""
      local f = file.tmpfile()
      local t = type(f)
      f:close()
      print(t)
    """) == "file\n"