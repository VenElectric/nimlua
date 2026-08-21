import std/[tables,sugar]
from strutils import parseFloat,parseInt
import ../ltypes
import ../lvalue
import ../lutil
import ../lerror

proc luaRawGet*(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 2:
    raise newException(LuaRuntimeError,"Incorrect number of arguments to 'rawget'. (table and key expected)")
  let tab = args[0]
  let index = args[1]
  if not isTable(tab):
    raise newException(LuaRuntimeError,"Bad argument #1 to 'rawget'. (table expected)")
  return @[tab.tval.getOrDefault(index, newLuaNil())]

proc luaRawSet*(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 3:
    raise newException(LuaRuntimeError, "Incorrect number of arguments to 'rawset'. (table, key, and value expected)")
  let tab = args[0]
  let index = args[1]
  let value = args[2]
  if not isTable(tab):
    raise newException(LuaRuntimeError, "Bad argument #1 to 'rawset'. (table expected)")
  if index.kind == ltNil:
    raise newException(LuaRuntimeError, "table index is nil")
  if isLuaNil(value):
    tab.tval.del(index)
  else:
    tab.tval[index] = value
  return @[tab]

proc luaRawEqual*(args:varargs[LuaValue]): seq[LuaValue] =
  if len(args) != 2:
    raise newException(LuaRuntimeError,"Incorrect number of arguments to 'rawEqual'. Two values expected.")
  return @[newLuaBool(args[0] == args[1])]

proc luaRawLen*(args:varargs[LuaValue]): seq[LuaValue] = 
  if len(args) != 1:
    raise newException(LuaRuntimeError, "Incorrect number of arguments to 'rawlen'. One value expected.")
  let v = args[0]
  result = @[]
  if isString(v):
    result.add(newLuaNumber(len(v.sval).float64))
  elif isTable(v):
    result.add(newLuaNumber(len(v.tval).float64))
  else:
    raise newException(LuaRuntimeError,"Bad argument # to 'rawlen'. (table or string expected)")
    

proc luaSetMetatable*(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 1 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "Bad argument #1 to 'setmetatable'. (table expected)")
  let t = args[0]
  if len(args) < 2 or args[1].kind == ltNil:
    t.mt = nil
  elif args[1].kind == ltTable:
    t.mt = args[1]
  else:
    raise newException(LuaRuntimeError, "Bad argument #2 to 'setmetatable' (nil or table expected)")
  return @[t]

proc luaGetMetatable*(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 1 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'getmetatable' (table expected)")
  if system.isNil(args[0].mt): return @[newLuaNil()]
  return @[args[0].mt]

proc luaPrint*(args: varargs[LuaValue]): seq[LuaValue] =
  for i, arg in args:
    # Uses the `$` stringify operator we overloaded in Phase 1!
    stdout.write($arg)
    if i < args.high:
      stdout.write("\t")

  stdout.write("\n")
  return @[newLuaNil()] # Lua functions push nil if they don't explicitly return

proc luaNext*(args: varargs[LuaValue]): seq[LuaValue] = 
  if args.len < 1 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'next' (table expected)")

  let tbl = args[0]
  let key = if args.len > 1: args[1] else: newLuaNil()

  if key.kind == ltNil:
    for k, v in tbl.tval.pairs:
      return @[k, v] # Return BOTH key and value
    return @[newLuaNil()] 

  var foundCurrent = false
  for k, v in tbl.tval.pairs:
    if foundCurrent:
      return @[k, v]
    
    # Using the overloaded `==` from lvalue.nim[cite: 33]
    if k == key: 
      foundCurrent = true

  return @[newLuaNil()]

proc luaPairs*(args: varargs[LuaValue]): seq[LuaValue] = 
  if len(args) < 1 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'pairs' (table expected)")
  
  # Return the iterator, the state (the table), and the initial control var (nil)
  return @[newNimFn(luaNext), args[0], newLuaNil()]


proc luaINext(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len < 2 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "inext expected a table and an index")

  let tbl = args[0]
  let currentIdx = args[1].nval
  let nextIdx = currentIdx + 1.0
  let nextKey = newLuaNumber(nextIdx)
  
  if tbl.tval.hasKey(nextKey):
    return @[nextKey, tbl.tval[nextKey]]
  
  return @[newLuaNil()]

proc luaIPairs*(args: varargs[LuaValue]): seq[LuaValue] = 
  if len(args) < 1 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'ipairs' (table expected)")
  
  # Return the iterator, the state (the table), and the initial control var (0.0)
  return @[newNimFn(luaINext), args[0], newLuaNumber(0.0)]



proc luaToNumber*(args: varargs[LuaValue]): seq[LuaValue] =
  if args.len == 0:
    return @[newLuaNil()]

  var base = 10
  if args.len >= 2 and not isLuaNil(args[1]):
    if isNumber(args[1]):
      base = args[1].nval.int64
    elif isString(args[1]):
      try:
        base = parseInt(args[1].sval)
      except ValueError:
        raise newException(ValueError, "bad argument #2 to 'tonumber' (number expected)")

  return @[luaUToNumber(args[0], base)]
  
proc luaToString*(args: varargs[LuaValue]): seq[LuaValue] = 
  if args.len == 0:
    raise newException(LuaRuntimeError,"Invalid # of arguments to 'tostring'. Expected one argument.")
  return @[newLuaString($args[0])]

proc luaType*(args: varargs[LuaValue]): seq[LuaValue] = 
  if args.len == 0:
    raise newException(LuaRuntimeError,"Invalid # of arguments to 'type'. Expected one argument.")
  
  let v = args[0]
  return @[newLuaString($v.kind)]

proc luaSelect*(args: varargs[LuaValue]): seq[LuaValue] = 
  if args.len < 2:
    raise newException(LuaRuntimeError, "Invalid # of arguments to 'select'. Expected at least two arguments.")
  
  let arg1 = args[0]
  if not isNumber(arg1) and not isString(arg1):
    raise newException(LuaRuntimeError, "bad argument #1 to 'select' (number expected)")
  
  let n = arg1.nval.int64
  if n == 0:
    raise newException(LuaRuntimeError, "bad argument #1 to 'select' (number expected)")
  
  result = collect(newSeq):
    for i in countup(1,args.len-1):
      args[i]