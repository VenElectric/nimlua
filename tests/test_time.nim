import std/unittest
import helpers/testutils
import ../src/lerror

suite "time.clock":
  test "returns a non-negative number":
    check runLua("print(time.clock() >= 0)") == "true\n"

suite "time.time":
  test "no-argument form returns a plausible current epoch value":
    # A loose bound rather than an exact value -- this is inherently "now",
    # so just confirm it's a real, recent-looking epoch integer.
    check runLua("print(time.time() > 1700000000)") == "true\n"

  test "table form and positional form agree for the same date":
    check runLua("""
      local a = time.time({year = 2024, month = 6, day = 15, hour = 10, min = 30, sec = 0})
      local b = time.time(2024, 6, 15, 10, 30, 0)
      print(a == b)
    """) == "true\n"

  test "round-trips correctly through time.date('*t')":
    check runLua("""
      local epoch = time.time({year = 2024, month = 6, day = 15, hour = 10, min = 30, sec = 45})
      local t = time.date("*t", epoch)
      print(t.year, t.month, t.day, t.hour, t.min, t.sec)
    """) == "2024\t6\t15\t10\t30\t45\n"

  test "missing required table fields raises":
    expect LuaRuntimeError:
      discard runLua("""time.time({hour = 5})""")

suite "time.difftime":
  test "computes t2 - t1, not the reverse":
    check runLua("print(time.difftime(100, 40))") == "60\n"

  test "wrong number of arguments raises":
    expect LuaRuntimeError:
      discard runLua("time.difftime(1)")

suite "time.date":
  test "no-argument form returns a string":
    check runLua("print(type(time.date()))") == "string\n"

  test "'*t' returns a table with the expected fields":
    check runLua("""
      local t = time.date("*t", time.time({year=2024, month=1, day=1, hour=12, min=0, sec=0}))
      print(t.year, t.month, t.day)
    """) == "2024\t1\t1\n"

  test "wday for a known Monday (2024-01-01)":
    # 2024-01-01 was genuinely a Monday. Lua's wday convention is 1=Sunday,
    # so a Monday should be 2. If THIS test fails while everything else in
    # this file passes, the WeekDay enum ordering assumption flagged during
    # implementation is very likely the cause -- check that mapping first
    # before suspecting anything else.
    check runLua("""
      local t = time.date("*t", time.time({year=2024, month=1, day=1, hour=12, min=0, sec=0}))
      print(t.wday)
    """) == "2\n"
