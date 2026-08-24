import std/unittest
import helpers/testutils
import ../src/lerror

suite "math: basic":
  test "abs preserves integer-ness":
    check runLua("print(math.abs(-5))") == "5\n"
  test "abs on a float":
    check runLua("print(math.abs(-5.5))") == "5.5\n"

  test "ceil and floor return integers, not floats":
    check runLua("print(math.ceil(4.2))") == "5\n"
    check runLua("print(math.floor(4.8))") == "4\n"

  test "sqrt":
    check runLua("print(math.sqrt(16))") == "4.0\n"

suite "math: trig naming matches real Lua (acos/asin/atan, not arc-prefixed)":
  test "acos":
    check runLua("print(math.acos(1))") == "0.0\n"
  test "asin":
    check runLua("print(math.asin(0))") == "0.0\n"
  test "atan":
    check runLua("print(math.atan(0))") == "0.0\n"
  test "sin, cos, tan round-trip at 0":
    check runLua("print(math.sin(0), math.cos(0), math.tan(0))") == "0.0\t1.0\t0.0\n"

suite "math: deg/rad":
  test "rad then deg round-trips back to the original value":
    check runLua("print(math.deg(math.rad(180)))") == "180.0\n"

suite "math: fmod (sign of the DIVIDEND, unlike %)":
  test "fmod on integers takes the dividend's sign":
    check runLua("print(math.fmod(-5, 3))") == "-2\n"
  test "ordinary % takes the divisor's sign, confirming they genuinely differ":
    check runLua("print(-5 % 3)") == "1\n"
  test "fmod on floats":
    check runLua("print(math.fmod(5.5, 2))") == "1.5\n"
  test "integer fmod by zero raises":
    expect LuaRuntimeError:
      discard runLua("math.fmod(5, 0)")

suite "math: log":
  test "single-argument log is natural log":
    check runLua("print(math.log(1))") == "0.0\n"
  test "base-10 log":
    check runLua("print(math.log(100, 10))") == "2.0\n"
  test "base-2 log":
    check runLua("print(math.log(8, 2))") == "3.0\n"
  test "arbitrary base falls back to ln(x)/ln(base)":
    check runLua("print(math.log(27, 3))") == "3.0\n"

suite "math: modf":
  test "splits a positive float into integral and fractional parts":
    check runLua("print(math.modf(3.75))") == "3.0\t0.75\n"
  test "negative float":
    check runLua("print(math.modf(-3.75))") == "-3.0\t-0.75\n"

suite "math: max / min":
  test "max preserves the winning argument's own type":
    check runLua("print(math.max(1, 2, 3))") == "3\n"
    check runLua("print(math.max(1, 2.5, 2))") == "2.5\n"
  test "min":
    check runLua("print(math.min(5, 1, 3))") == "1\n"
  test "max with no arguments raises":
    expect LuaRuntimeError:
      discard runLua("math.max()")

suite "math: tointeger":
  test "an integer-valued float becomes a real integer":
    check runLua("print(math.tointeger(4.0))") == "4\n"
  test "a fractional float returns nil, not an error":
    check runLua("print(math.tointeger(4.5))") == "nil\n"
  test "a string returns nil":
    check runLua("""print(math.tointeger("x"))""") == "nil\n"

suite "math: ult":
  test "unsigned comparison treats a negative as a huge positive":
    check runLua("print(math.ult(-1, 1))") == "false\n"

suite "math: frexp / ldexp round-trip":
  test "ldexp inverts frexp":
    check runLua("""
      local m, e = math.frexp(100.0)
      print(math.ldexp(m, e))
    """) == "100.0\n"

suite "math: random":
  test "no-argument form stays within [0, 1)":
    check runLua("""
      local x = math.random()
      print(x >= 0 and x < 1)
    """) == "true\n"

  test "single-argument form stays within [1, m]":
    check runLua("""
      local x = math.random(10)
      print(x >= 1 and x <= 10)
    """) == "true\n"

  test "two-argument form stays within [lo, hi]":
    check runLua("""
      local x = math.random(5, 8)
      print(x >= 5 and x <= 8)
    """) == "true\n"

  test "randomseed makes the sequence reproducible":
    check runLua("""
      math.randomseed(42)
      local a = math.random(1, 1000000)
      math.randomseed(42)
      local b = math.random(1, 1000000)
      print(a == b)
    """) == "true\n"

suite "math: constants":
  test "pi":
    check runLua("print(math.pi > 3.14 and math.pi < 3.15)") == "true\n"
  test "huge":
    check runLua("print(math.huge > 0)") == "true\n"
  test "mininteger and maxinteger bound an ordinary integer":
    check runLua("print(math.mininteger < 0 and math.maxinteger > 0)") == "true\n"
