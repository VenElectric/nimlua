import std/unittest
import helpers/testutils
import ../src/lerror

suite "json.tojson: unrepresentable kinds become null":
  test "a function value becomes null (round-trip through loadjson)":
    check runLua("""
      local t = {fn = function() end}
      local back = json.loadjson(json.tojson(t))
      print(back.fn)
    """) == "nil\n"

  test "userdata with no overload becomes null (round-trip through loadjson)":
    check runLua("""
      local f = file.tmpfile()
      local t = {handle = f}
      f:close()
      local back = json.loadjson(json.tojson(t))
      print(back.handle == nil)
    """) == "true\n"

suite "json.tojson / json.loadjson: scalars round-trip correctly":
  test "string, integer, float, and boolean all survive a round trip":
    check runLua("""
      local t = {s = "hello", i = 42, f = 3.5, b = true}
      local back = json.loadjson(json.tojson(t))
      print(back.s, back.i, back.f, back.b)
    """) == "hello\t42\t3.5\ttrue\n"

suite "json.tojson: dense arrays":
  test "a dense 1..n array produces a real JSON array (order-safe, direct string check)":
    check runLua("""print(json.tojson({10, 20, 30}))""") == "[10,20,30]\n"

suite "json.tojson / json.loadjson: sparse arrays within the cap":
  test "gaps within the sparsity cap fill with null and round-trip correctly":
    check runLua("""
      local t = {}
      t[1] = "a"
      t[4] = "b"
      t[6] = "c"
      local back = json.loadjson(json.tojson(t))
      print(back[1], back[2], back[3], back[4], back[5], back[6])
    """) == "a\tnil\tnil\tb\tnil\tc\n"

suite "json.tojson / json.loadjson: sparsity beyond the cap falls back to an object":
  test "a huge sparse gap does not produce a giant array":
    check runLua("""
      local t = {}
      t[1] = "a"
      t[1000000] = "b"
      local jsonStr = json.tojson(t)
      print(#jsonStr < 1000)
    """) == "true\n"

  test "beyond-cap round-trip recovers values under STRING keys, not the original integer keys":
    # This is an inherent, unavoidable property of JSON itself -- object
    # keys are always strings, so "was originally integer key 1" and "was
    # originally string key '1'" become indistinguishable once serialized.
    # Documenting this as expected behavior, not a bug.
    check runLua("""
      local t = {}
      t[1] = "a"
      t[1000000] = "b"
      local back = json.loadjson(json.tojson(t))
      print(back[1], back["1"], back[1000000], back["1000000"])
    """) == "nil\ta\tnil\tb\n"

suite "json.tojson: mixed or non-integer keys fall back to an object":
  test "a table with a non-integer key is never treated as an array":
    check runLua("""
      local back = json.loadjson(json.tojson({[1] = "a", foo = "bar"}))
      print(back["1"], back.foo)
    """) == "a\tbar\n"

  test "a float key disqualifies array treatment":
    check runLua("""
      local back = json.loadjson(json.tojson({[1.5] = "x"}))
      print(back["1.5"])
    """) == "x\n"

suite "json.tojson / json.loadjson: nested structures":
  test "an array of objects round-trips correctly":
    check runLua("""
      local t = {{name = "a"}, {name = "b"}}
      local back = json.loadjson(json.tojson(t))
      print(back[1].name, back[2].name)
    """) == "a\tb\n"

  test "an object containing an array round-trips correctly":
    check runLua("""
      local t = {items = {1, 2, 3}}
      local back = json.loadjson(json.tojson(t))
      print(back.items[1], back.items[2], back.items[3])
    """) == "1\t2\t3\n"

suite "json.loadjson: parsing hand-written JSON directly":
  test "parses an object":
    check runLua("""
      local t = json.loadjson('{"a": 1, "b": "two"}')
      print(t.a, t.b)
    """) == "1\ttwo\n"

  test "parses an array":
    check runLua("""
      local t = json.loadjson('[1, 2, 3]')
      print(t[1], t[2], t[3])
    """) == "1\t2\t3\n"

  test "parses null as nil":
    check runLua("""
      local t = json.loadjson('{"a": null}')
      print(t.a)
    """) == "nil\n"

suite "argument validation":
  test "tojson rejects a non-table argument":
    expect LuaRuntimeError:
      discard runLua("""json.tojson(42)""")

  test "tojson rejects zero arguments":
    expect LuaRuntimeError:
      discard runLua("""json.tojson()""")

  test "loadjson rejects a non-string argument":
    expect LuaRuntimeError:
      discard runLua("""json.loadjson(42)""")

  test "loadjson raises a clean error on malformed JSON":
    expect LuaRuntimeError:
      discard runLua("""json.loadjson("{not valid json")""")
