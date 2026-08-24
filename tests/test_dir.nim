import std/[unittest, os]
import helpers/testutils
import ../src/lerror

const BaseDir = "test_lua_dir_root"
const MovedDir = "test_lua_dir_moved"
const CopiedDir = "test_lua_dir_copied"

proc cleanupAll() =
  for p in [BaseDir, MovedDir, CopiedDir]:
    try: removeDir(p)
    except: discard

suite "dir: create / exists / remove":
  setup: cleanupAll()
  teardown: cleanupAll()

  test "create makes a real directory":
    check runLua("""
      local ok = dir.create('""" & BaseDir & """')
      print(ok, dir.exists('""" & BaseDir & """'))
    """) == "true\ttrue\n"

  test "exists is false for a directory that was never created":
    check runLua("""print(dir.exists('""" & BaseDir & """'))""") == "false\n"

  test "remove deletes an existing directory":
    check runLua("""
      dir.create('""" & BaseDir & """')
      local ok = dir.remove('""" & BaseDir & """')
      print(ok, dir.exists('""" & BaseDir & """'))
    """) == "true\tfalse\n"

suite "dir: move / copy":
  setup: cleanupAll()
  teardown: cleanupAll()

  test "move relocates a directory":
    check runLua("""
      dir.create('""" & BaseDir & """')
      local ok = dir.move('""" & BaseDir & """', '""" & MovedDir & """')
      print(ok, dir.exists('""" & BaseDir & """'), dir.exists('""" & MovedDir & """'))
    """) == "true\tfalse\ttrue\n"

  test "copy leaves the original in place":
    check runLua("""
      dir.create('""" & BaseDir & """')
      local ok = dir.copy('""" & BaseDir & """', '""" & CopiedDir & """')
      print(ok, dir.exists('""" & BaseDir & """'), dir.exists('""" & CopiedDir & """'))
    """) == "true\ttrue\ttrue\n"

suite "dir: walk and PathKind":
  setup: cleanupAll()
  teardown: cleanupAll()

  test "walk distinguishes files from subdirectories via PathKind":
    check runLua("""
      dir.create('""" & BaseDir & """')
      dir.create('""" & BaseDir & """/sub')
      local f = file.open('""" & BaseDir & """/a.txt', FileMode.write)
      f:write("x")
      f:close()

      local fileCount = 0
      local dirCount = 0
      for kind, path in dir.walk('""" & BaseDir & """') do
        if kind == PathKind.file then fileCount = fileCount + 1 end
        if kind == PathKind.dir then dirCount = dirCount + 1 end
      end
      print(fileCount, dirCount)
    """) == "1\t1\n"

  test "walking an empty directory yields no iterations":
    check runLua("""
      dir.create('""" & BaseDir & """')
      local n = 0
      for kind, path in dir.walk('""" & BaseDir & """') do n = n + 1 end
      print(n)
    """) == "0\n"

  test "walking a nonexistent directory raises":
    expect LuaRuntimeError:
      discard runLua("""for k, p in dir.walk('does_not_exist_xyz') do end""")

suite "PathKind enum":
  test "members are distinct, and reverse lookup gives the name back":
    check runLua("""
      print(PathKind.file ~= PathKind.dir)
      print(PathKind[PathKind.dir])
    """) == "true\ndir\n"

suite "dir: temp / tempScoped":
  test "temp creates a real, already-existing directory":
    check runLua("""
      local path = dir.temp("luatest_", "_d")
      local exists = dir.exists(path)
      dir.remove(path)
      print(exists)
    """) == "true\n"

  test "tempScoped is automatically removed when its <close> scope ends":
    check runLua("""
      local path
      do
        local t <close> = dir.tempScoped("luatest_", "_d")
        path = t:path()
      end
      print(dir.exists(path))
    """) == "false\n"
