from strutils import join
import std/[tables,sugar,sequtils]
import ../lvalue,../lerror,../ltypes
import ../lvm

proc allKeysNumbers(v:LuaTable): bool = 
  let s = collect(newSeq):
    for k in v.keys:
      k
  return all(s,proc(x:LuaValue): bool = isNumber(x))

proc allValuesOfKind(v:LuaTable,kinds:set[LuaKind]): bool =
  let s = collect(newSeq):
    for v in v.values:
      v
  return all(s,proc(x:LuaValue): bool = x.kind in kinds)

proc tableToSeq(v:LuaTable): seq[LuaValue] =
  for val in v.values:
    result.add val

proc luaToStr(v: LuaValue): string =
  case v.kind
  of ltString: v.sval
  of ltNumber: $v.nval
  else: raise newException(LuaRuntimeError, "invalid value (" & $v.kind & ") in table for 'concat'")

proc tableConcat(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 1 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "Cannot use concat on a non-table value.")
  let tab = args[0]

  var sep = ""
  if len(args) >= 2:
    if not isString(args[1]) and not isNumber(args[1]):
      raise newException(LuaRuntimeError, "Bad argument for sep: string or number expected, but got: " & $args[1].kind)
    sep = luaToStr(args[1])

  var start = 1
  var endPos = len(tab.tval)
  if len(args) >= 3 and isNumber(args[2]): start = int(intVal(args[1]))  # same bug
  if len(args) >= 4 and isNumber(args[3]): endPos = int(intVal(args[2]))  # same bug

  var items: seq[string] = @[]
  for i in start .. endPos:
    let key = newLuaNumber(float64(i))
    if not tab.tval.hasKey(key):
      raise newException(LuaRuntimeError, "invalid value (nil) at index " & $i & " in table for 'concat'")
    items.add(luaToStr(tab.tval[key]))

  return @[newLuaString(items.join(sep))]

proc tableInsert(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 2 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "Can not use insert on a non-table value")
  let tab = args[0]
  let n = len(tab.tval)

  if len(args) == 2:
    tab.tval[newLuaNumber(float64(n + 1))] = args[1]
  elif len(args) == 3:
    if not isNumber(args[1]):
      raise newException(LuaRuntimeError, "Bad argument #2 to 'insert': number expected")

    let pos = int(intVal(args[1]))
    for i in countdown(n, pos):
      tab.tval[newLuaNumber(float64(i + 1))] = tab.tval[newLuaNumber(float64(i))]
    tab.tval[newLuaNumber(float64(pos))] = args[2]
  else:
    raise newException(LuaRuntimeError, "Wrong number of arguments to insert")

  return @[newLuaNil()]

proc tableRemove(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 1 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'remove' (table expected)")
  let tab = args[0]
  let n = len(tab.tval)

  var pos = n
  if len(args) >= 2:
    if not isNumber(args[1]):
      raise newException(LuaRuntimeError, "bad argument #2 to 'remove' (number expected)")
    pos = int(intVal(args[1]))

  if n == 0:
    return @[newLuaNil()]
  if pos < 1 or pos > n + 1:
    raise newException(LuaRuntimeError, "bad argument #2 to 'remove' (position out of bounds)")
  if pos == n + 1:
    return @[newLuaNil()]

  let removedVal = tab.tval.getOrDefault(newLuaNumber(float64(pos)), newLuaNil())
  for i in pos ..< n:
    tab.tval[newLuaNumber(float64(i))] = tab.tval[newLuaNumber(float64(i + 1))]
  tab.tval.del(newLuaNumber(float64(n)))

  return @[removedVal]

proc tableMove(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 4 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'move' (table expected)")
  if not isNumber(args[1]) or not isNumber(args[2]) or not isNumber(args[3]):
    raise newException(LuaRuntimeError, "bad arguments to 'move' (numbers expected)")

  let a1 = args[0]
  let f = int(intVal(args[1]))
  let e = int(intVal(args[2]))
  let t = int(intVal(args[3]))
  let a2 = if len(args) >= 5 and isTable(args[4]): args[4] else: a1

  if e >= f:
    # Copy descending instead of ascending whenever the destination overlaps
    # the source range from behind, in the SAME table -- otherwise an
    # ascending copy would clobber a source slot before it's been read.
    let ascending = (t <= f) or (t > e) or (a1.tval != a2.tval)
    let indices = if ascending: toSeq(0 .. (e - f)) else: toSeq(countdown(e - f, 0))
    for i in indices:
      let srcKey = newLuaNumber(float64(f + i))
      let dstKey = newLuaNumber(float64(t + i))
      if a1.tval.hasKey(srcKey): a2.tval[dstKey] = a1.tval[srcKey]
      else: a2.tval.del(dstKey)

  return @[a2]

proc tablePack(args:varargs[LuaValue]): seq[LuaValue] =
  var tab = newLuaTable()
  for i, v in args:
    tab.tval[newLuaNumber(float64(i + 1))] = v
  tab.tval[newLuaString("n")] = newLuaInteger(args.len)
  return @[tab]

proc tableUnpack(args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 1 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'unpack' (table expected)")
  let tab = args[0]
  var i = 1
  var j = len(tab.tval)
  if len(args) >= 2 and isNumber(args[1]): i = int(intVal(args[1]))
  if len(args) >= 3 and isNumber(args[2]): j = int(intVal(args[2]))
  result = @[]
  for idx in i .. j:
    result.add(tab.tval.getOrDefault(newLuaNumber(float64(idx)), newLuaNil()))

proc luaSortLess(vm: var VM, comp: LuaValue, a, b: LuaValue): bool =
  if comp.kind == ltNil:
    return truthy(luaLess(vm,a, b))
  let stopDepth = vm.frames.len
  vm.push(comp)
  vm.push(a)
  vm.push(b)
  vm.performCall(2)
  discard vm.run(stopDepth)
  vm.adjustResults(1)
  return truthy(vm.pop())

proc tableSort*(vm: var VM, args: varargs[LuaValue]): seq[LuaValue] =
  if len(args) < 1 or not isTable(args[0]):
    raise newException(LuaRuntimeError, "bad argument #1 to 'sort' (table expected)")
  let tab = args[0]

  var comp = newLuaNil()
  if len(args) >= 2 and args[1].kind != ltNil:
    if args[1].kind notin {ltClosure, ltNativeFn, ltNativeFnVM}:
      raise newException(LuaRuntimeError, "bad argument #2 to 'sort' (function expected)")
    comp = args[1]

  let n = len(tab.tval)
  var items = newSeq[LuaValue](n)
  for i in 1 .. n:
    items[i - 1] = tab.tval.getOrDefault(newLuaNumber(float64(i)), newLuaNil())

  # Insertion sort, deliberately, not algorithm.sort -- see note below.
  for i in 1 ..< n:
    let key = items[i]
    var j = i - 1
    while j >= 0 and vm.luaSortLess(comp, key, items[j]):
      items[j + 1] = items[j]
      dec j
    items[j + 1] = key

  for i in 1 .. n:
    tab.tval[newLuaNumber(float64(i))] = items[i - 1]

  return @[]

proc newTabLib*(): LuaValue = 
  result = newLuaTable()
  result.tval[newLuaString("pack")] = newNimFn(tablePack)
  result.tval[newLuaString("insert")] = newNimFn(tableInsert)
  result.tval[newLuaString("concat")] = newNimFn(tableConcat)
  result.tval[newLuaString("remove")] = newNimFn(tableRemove)
  result.tval[newLuaString("move")] = newNimFn(tableMove)
  result.tval[newLuaString("unpack")] = newNimFn(tableUnpack)
  result.tval[newLuaString("sort")] = newNimFnVM(tableSort)
