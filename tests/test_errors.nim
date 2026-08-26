import std/unittest
import helpers/testutils

suite "assert":
  test "assert's other truthy arguments reach print's argument list":
    check runLua("""print(assert(1, "ok", 3))""") == "1\tok\t3\n"

  test "falsy first argument raises with the default message":
    check runLua("""
      local ok, err = pcall(function() assert(false) end)
      print(ok, err)
    """) == "false\tassertion failed!\n"

  test "falsy first argument raises with a custom message":
    check runLua("""
      local ok, err = pcall(function() assert(false, "custom") end)
      print(ok, err)
    """) == "false\tcustom\n"

  test "non-string assert message survives pcall intact":
    check runLua("""
      local ok, err = pcall(function() assert(false, {code = 1}) end)
      print(ok, err.code)
    """) == "false\t1\n"

suite "error":
  test "error() is caught by pcall":
    check runLua("""
      local ok, err = pcall(function() error("boom") end)
      print(ok, err)
    """) == "false\tboom\n"

  test "a non-string error value survives intact":
    check runLua("""
      local ok, err = pcall(function() error({code = 42}) end)
      print(ok, err.code)
    """) == "false\t42\n"

suite "pcall":
  test "successful call reports true plus all return values":
    check runLua("""
      print(pcall(function() return 1, 2, 3 end))
    """) == "true\t1\t2\t3\n"

  test "a plain runtime error (not a manual error()) is still caught":
    check runLua("""
      local ok, err = pcall(function() return {} + {} end)
      print(ok)
    """) == "false\n"

  test "pcall does not itself print anything -- only what wraps it does":
    check runLua("""pcall(function() return 1 end)""") == ""
  
  test "error inside a function-valued __index handler is caught by an enclosing pcall":
    check runLua("""
      local mt = {__index = function(t, k) error("boom from index") end}
      local x = setmetatable({}, mt)
      local ok, err = pcall(function() return x.missing end)
      print(ok, err)
      """) == "false\tboom from index\n"
    
  test "a non-string error thrown inside __index survives pcall intact":
    check runLua("""
      local mt = {__index = function(t, k) error({code = 7}) end}
      local x = setmetatable({}, mt)
      local ok, err = pcall(function() return x.missing end)
      print(ok, err.code)
      """) == "false\t7\n"
  
  test "vm.lastError does not leak across a nested pcall inside a metamethod handler":
    check runLua("""
    local mt = {__index = function(t, k)
      pcall(function() error("inner, already handled") end)
      return "handled"
    end}
    local x = setmetatable({}, mt)
    print(x.anything)
    local ok, err = pcall(function() return {} + {} end)
    print(ok, err)
    """) == "handled\nfalse\tline 7: Cannot perform '+' on table and table\n"

suite "xpcall":
  test "handler receives and can transform the error value":
    check runLua("""
      local ok, msg = xpcall(function() error("boom") end,
                              function(e) return "caught: " .. e end)
      print(ok, msg)
    """) == "false\tcaught: boom\n"
  
