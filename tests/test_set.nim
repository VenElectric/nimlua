import std/unittest
import helpers/testutils
import ../src/lerror

suite "set: construction and cardinality":
  test "new builds a set with the given members":
    check runLua("""print(#set.new(1, 2, 3))""") == "3\n"

  test "duplicate members do not double-count":
    check runLua("""print(#set.new(1, 1, 2))""") == "2\n"

  test "an empty set has cardinality 0":
    check runLua("""print(#set.new())""") == "0\n"

  test "distinct tables with identical contents count as separate members":
    # Direct callback to the table-identity fix -- two empty tables are
    # NOT the same set member just because their contents match.
    check runLua("""
      local a = {}
      local b = {}
      print(#set.new(a, b))
    """) == "2\n"

  test "adding nil at construction raises":
    expect LuaRuntimeError:
      discard runLua("""set.new(1, nil, 2)""")

suite "set: contains / add / remove":
  test "contains reflects membership":
    check runLua("""
      local s = set.new(1, 2)
      print(s:contains(1), s:contains(3))
    """) == "true\tfalse\n"

  test "add is chainable and returns the set itself":
    check runLua("""
      local s = set.new()
      s:add(1):add(2):add(3)
      print(#s, s:contains(2))
    """) == "3\ttrue\n"

  test "remove drops a member":
    check runLua("""
      local s = set.new(1, 2, 3)
      s:remove(2)
      print(#s, s:contains(2))
    """) == "2\tfalse\n"

  test "adding nil raises":
    expect LuaRuntimeError:
      discard runLua("""set.new():add(nil)""")

  test "membership also works via ordinary table indexing":
    check runLua("""
      local s = set.new(1, 2)
      print(s[1], s[3])
    """) == "true\tnil\n"

suite "set: union / intersect / difference / symmetric difference":
  test "union combines both sets' members":
    check runLua("""
      local a = set.new(1, 2, 3)
      local b = set.new(3, 4, 5)
      print(#(a | b))
    """) == "5\n"

  test "intersect keeps only shared members":
    check runLua("""
      local a = set.new(1, 2, 3)
      local b = set.new(2, 3, 4)
      local i = a & b
      print(#i, i:contains(2), i:contains(1))
    """) == "2\ttrue\tfalse\n"

  test "difference removes the right-hand set's members":
    check runLua("""
      local a = set.new(1, 2, 3)
      local b = set.new(2, 3)
      local d = a - b
      print(#d, d:contains(1))
    """) == "1\ttrue\n"

  test "symmetric difference keeps members unique to each side":
    check runLua("""
      local a = set.new(1, 2)
      local b = set.new(2, 3)
      local x = a ~ b
      print(#x, x:contains(1), x:contains(2), x:contains(3))
    """) == "2\ttrue\tfalse\ttrue\n"

suite "set: equality and subset comparisons":
  test "equality ignores insertion order":
    check runLua("""
      local a = set.new(1, 2, 3)
      local b = set.new(3, 2, 1)
      print(a == b)
    """) == "true\n"

  test "different cardinality is never equal":
    check runLua("""
      local a = set.new(1, 2, 3)
      local b = set.new(1, 2)
      print(a == b)
    """) == "false\n"

  test "<= is true for a subset, including a set compared to itself":
    check runLua("""
      local a = set.new(1, 2, 3)
      local b = set.new(1, 2)
      print(b <= a, a <= a)
    """) == "true\ttrue\n"

  test "< is true only for a PROPER subset":
    check runLua("""
      local a = set.new(1, 2, 3)
      local b = set.new(1, 2)
      print(b < a, a < a)
    """) == "true\tfalse\n"

suite "set: iteration":
  test "pairs walks every member exactly once":
    check runLua("""
      local s = set.new(10, 20, 30)
      local n = 0
      for k in pairs(s) do n = n + 1 end
      print(n)
    """) == "3\n"

suite "set: operating on a non-set value raises":
  test "a plain table is rejected, even one that looks set-shaped":
    expect LuaRuntimeError:
      discard runLua("""
        local s = set.new(1, 2)
        return s | {3, 4}
      """)

  test "a number operand is rejected":
    expect LuaRuntimeError:
      discard runLua("""return set.new(1) & 5""")

suite "set: type() reporting":
  test "type() reports 'set' for a set, not 'table'":
    check runLua("""print(type(set.new(1, 2)))""") == "set\n"
