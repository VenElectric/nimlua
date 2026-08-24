import std/unittest
import helpers/testutils

suite "table.insert / table.remove":
  test "rawequal on distinct tables with identical contents is false":
    check runLua("""
      local a = {x = 1}
      local b = {x = 1}
      print(rawequal(a, b))
      """) == "false\n"
  
  test "insert appends when no position given":
    check runLua("""
      local t = {1, 2}
      table.insert(t, 3)
      print(t[1], t[2], t[3])
    """) == "1\t2\t3\n"

  test "insert at a position shifts later elements up":
    check runLua("""
      local t = {1, 2, 3}
      table.insert(t, 2, 99)
      print(t[1], t[2], t[3], t[4])
    """) == "1\t99\t2\t3\n"

  test "remove with no position removes the last element":
    check runLua("""
      local t = {1, 2, 3}
      local removed = table.remove(t)
      print(removed, #t)
    """) == "3\t2\n"

  test "remove at a position shifts later elements down":
    check runLua("""
      local t = {1, 2, 3}
      local removed = table.remove(t, 1)
      print(removed, t[1], t[2])
    """) == "1\t2\t3\n"

suite "table.concat":
  test "default separator and range":
    check runLua("""print(table.concat({"a", "b", "c"}))""") == "abc\n"

  test "explicit separator":
    check runLua("""print(table.concat({"a", "b", "c"}, ","))""") == "a,b,c\n"

suite "table.move":
  test "copy within the same table, overlapping ranges":
    check runLua("""
      local t = {1, 2, 3, 4, 5}
      table.move(t, 1, 3, 2)
      print(t[1], t[2], t[3], t[4], t[5])
    """) == "1\t1\t2\t3\t5\n"

suite "table.sort":
  test "default ascending order for numbers":
    check runLua("""
      local t = {3, 1, 2}
      table.sort(t)
      print(t[1], t[2], t[3])
    """) == "1\t2\t3\n"

  test "custom comparator sorts descending":
    check runLua("""
      local t = {1, 3, 2}
      table.sort(t, function(a, b) return a > b end)
      print(t[1], t[2], t[3])
    """) == "3\t2\t1\n"

suite "table.pack / table.unpack":
  test "pack captures both values and a count":
    check runLua("""
      local t = table.pack(1, 2, 3)
      print(t.n, t[1], t[2], t[3])
    """) == "3\t1\t2\t3\n"

  test "unpack with explicit range":
    check runLua("""print(table.unpack({10, 20, 30}, 2, 3))""") == "20\t30\n"

suite "rawget / rawset / rawequal / rawlen":
  test "rawget bypasses __index":
    check runLua("""
      local base = {x = 1}
      local t = setmetatable({}, {__index = base})
      print(t.x, rawget(t, "x"))
    """) == "1\tnil\n"

  test "rawset bypasses __newindex":
    check runLua("""
      local mt = {__newindex = function() error("should not fire") end}
      local t = setmetatable({}, mt)
      rawset(t, "x", 5)
      print(t.x)
    """) == "5\n"

  test "rawequal ignores __eq":
    check runLua("""
      local mt = {__eq = function() return true end}
      local a = setmetatable({}, mt)
      local b = setmetatable({}, mt)
      print(a == b, rawequal(a, b))
    """) == "true\tfalse\n"

  test "rawlen ignores __len":
    check runLua("""
      local t = setmetatable({1, 2, 3}, {__len = function() return 99 end})
      print(#t, rawlen(t))
    """) == "99\t3\n"
