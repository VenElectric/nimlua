import std/unittest
import helpers/testutils
import ../src/lerror

suite "internal tables: ordinary tables are unaffected":
  test "rawget/rawset work normally on a plain table":
    check runLua("""
      local t = {a = 1}
      rawset(t, "b", 2)
      print(rawget(t, "a"), rawget(t, "b"))
    """) == "1\t2\n"

suite "internal tables: enums block raw access":
  test "rawget on an enum raises":
    expect LuaRuntimeError:
      discard runLua("""rawget(FileMode, "read")""")

  test "rawset on an enum raises":
    expect LuaRuntimeError:
      discard runLua("""rawset(FileMode, "hack", 99)""")

  test "ordinary (non-raw) access to an enum still works after the guard":
    check runLua("""
      print(FileMode.read)
      print(FileMode[FileMode.read])
    """) == "1\nread\n"

suite "internal tables: _G blocks raw access":
  test "rawget on _G raises":
    expect LuaRuntimeError:
      discard runLua("""rawget(_G, "print")""")

  test "rawset on _G raises":
    expect LuaRuntimeError:
      discard runLua("""rawset(_G, "hack", 99)""")

  test "ordinary global read/write through _G still works after the guard":
    check runLua("""
      x = 5
      print(_G.x)
      _G.y = 10
      print(y)
    """) == "5\n10\n"

suite "internal tables: TypeKind blocks raw access":
  test "rawget on TypeKind raises":
    expect LuaRuntimeError:
      discard runLua("""rawget(TypeKind, "set")""")

  test "rawset on TypeKind raises":
    expect LuaRuntimeError:
      discard runLua("""rawset(TypeKind, "hack", "hack")""")

  test "ordinary access to TypeKind still works after the guard":
    check runLua("""print(TypeKind.set)""") == "set\n"
