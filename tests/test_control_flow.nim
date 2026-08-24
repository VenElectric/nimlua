import std/unittest
import helpers/testutils

suite "if / elseif / else":
  test "picks the first true branch":
    check runLua("""
      local x = 5
      if x < 0 then print("neg")
      elseif x == 0 then print("zero")
      elseif x < 10 then print("small")
      else print("big") end
    """) == "small\n"

  test "if without else, condition false, no crash and nothing leaked on the stack":
    check runLua("""
      local a = 1
      if false then end
      local b = 2
      print(a, b)
    """) == "1\t2\n"

suite "while":
  test "runs zero times when condition starts false":
    check runLua("""
      local i = 10
      while i < 5 do i = i + 1 end
      print(i)
    """) == "10\n"

  test "counts up correctly":
    check runLua("""
      local i = 0
      while i < 5 do
        print(i)
        i = i + 1
      end
    """) == "0\n1\n2\n3\n4\n"

suite "repeat / until":
  # This exact case caught the swapped >/>= bug: body must run for i = 0..10
  # inclusive (11 lines), stopping only once i becomes 11.
  test "runs the body at least once and checks the condition after":
    check runLua("""
      local x = 0
      repeat
        print(x)
        x = x + 1
      until x > 10
    """) == "0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n"

  test "body locals remain visible to the until condition":
    check runLua("""
      local i = 0
      repeat
        local done = (i >= 2)
        i = i + 1
      until done
      print(i)
    """) == "3\n"

suite "numeric for":
  test "ascending with default step":
    check runLua("""
      for i = 1, 3 do print(i) end
    """) == "1\n2\n3\n"

  test "descending with explicit negative step":
    check runLua("""
      for i = 3, 1, -1 do print(i) end
    """) == "3\n2\n1\n"

  test "runtime-determined step sign still picks the right comparison":
    # `step` is a parameter, not a literal, so the compiler can't know its
    # sign ahead of time -- this exercises the runtime sign-check branch,
    # not the compile-time-known-sign fast path the two tests above use.
    check runLua("""
      local function loop(step)
        for i = 3, 1, step do print(i) end
      end
      loop(-1)
    """) == "3\n2\n1\n"

suite "generic for":
  test "pairs walks a table":
    check runLua("""
      local t = {10, 20, 30}
      local sum = 0
      for k, v in pairs(t) do sum = sum + v end
      print(sum)
    """) == "60\n"

  test "ipairs stops at the first gap":
    check runLua("""
      local t = {1, 2, 3}
      t[5] = 50
      local count = 0
      for i, v in ipairs(t) do count = count + 1 end
      print(count)
    """) == "3\n"

suite "break":
  test "exits the innermost loop only":
    check runLua("""
      for i = 1, 3 do
        for j = 1, 3 do
          if j == 2 then break end
          print(i, j)
        end
      end
    """) == "1\t1\n2\t1\n3\t1\n"

suite "goto":
  test "forward jump skips the middle":
    check runLua("""
      print("a")
      goto skip
      print("b")
      ::skip::
      print("c")
    """) == "a\nc\n"
