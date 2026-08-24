import std/unittest
import helpers/testutils
import ../src/lerror

suite "TypeKind: pre-registered types":
  test "file, tempdir, and set are already registered at startup":
    check runLua("""
      print(TypeKind.file, TypeKind.tempdir, TypeKind.set)
    """) == "file\ttempdir\tset\n"

  test "an unregistered name reads as nil, not an error":
    check runLua("""print(TypeKind.neverRegistered)""") == "nil\n"

suite "TypeKind: registering a new name":
  test "a brand new name registers successfully":
    check runLua("""
      TypeKind.myNewType = "myNewType"
      print(TypeKind.myNewType)
    """) == "myNewType\n"

suite "TypeKind: duplicate registration is rejected":
  test "re-registering an already-taken name raises":
    expect LuaRuntimeError:
      discard runLua("""TypeKind.set = "somethingElse"""")

  test "registering the same name twice in one script raises on the second attempt":
    check runLua("""
      TypeKind.myClass = "myClass"
      local ok = pcall(function() TypeKind.myClass = "myClass" end)
      print(ok)
    """) == "false\n"

  test "the guard does not block reading, only writing, an existing name":
    check runLua("""
      local ok, err = pcall(function() return TypeKind.set end)
      print(ok, err)
    """) == "true\tset\n"

suite "TypeKind: integrates with type()":
  test "type() on a real set matches TypeKind.set":
    check runLua("""
      local s = set.new(1, 2)
      print(type(s) == TypeKind.set)
    """) == "true\n"

  test "type() on a plain table does NOT match TypeKind.set":
    check runLua("""
      print(type({}) == TypeKind.set)
    """) == "false\n"
