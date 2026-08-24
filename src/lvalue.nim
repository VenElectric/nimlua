import std/[tables, hashes]
from math import splitDecimal
import lerror, ltypes

proc `==`*(a, b: LuaValue): bool
proc hash*(v: LuaValue): Hash
proc newLuaString*(v: sink string): LuaValue

let MTINDEX* = newLuaString("__index")
let MTNEWINDEX* = newLuaString("__newindex")
let MTCALL* = newLuaString("__call")
let MTADD* = newLuaString("__add")
let MTSUB* = newLuaString("__sub")
let MTMUL* = newLuaString("__mul")
let MTDIV* = newLuaString("__div")
let MTMOD* = newLuaString("__mod")
let MTPOW* = newLuaString("__pow")
let MTNEG* = newLuaString("__unm")
let MTIDIV* = newLuaString("__idiv")
let MTBAND* = newLuaString("__band")
let MTBOR* = newLuaString("__bor")
let MTBXOR* = newLuaString("__bxor")
let MTBNOT* = newLuaString("__bnot")
let MTSHL* = newLuaString("__shl")
let MTSHR* = newLuaString("__shr")
let MTCONCAT* = newLuaString("__concat")
let MTLEN* = newLuaString("__len")
let MTEQ* = newLuaString("__eq")
let MTLT* = newLuaString("__lt")
let MTLE* = newLuaString("__le")
let MTCLOSE* = newLuaString("__close")
let MTGC* = newLuaString("__gc")
let MTMODE* = newLuaString("__mode")
let MTPAIRS* = newLuaSTring("__pairs")
let MTTYPE* = newLuaString("__type")
let MTNAME* = newLuaString("__name")
let MTTOSTR* = newLuaString("__tostring")


proc initChunk*(): Chunk =
  Chunk(code: @[], constants: @[], lines: @[])

proc writeChunk*(chunk: var Chunk, byte: uint8, line: int) =
  chunk.code.add(byte)
  chunk.lines.add(line)

proc addConstant*(chunk: var Chunk, value: LuaValue): uint8 =
  chunk.constants.add(value)
  # Return the index of the constant we just added.
  # Note: A uint8 index limits us to 256 constants per chunk in v1.
  return uint8(chunk.constants.len - 1)

proc numVal*(v: LuaValue): float64 =
  case v.kind
  of ltInteger: float64(v.ival)
  of ltNumber: v.nval
  else: raise newException(LuaRuntimeError, "attempt to treat a " & $v.kind & " value as a number")

proc intVal*(v: LuaValue): int64 =
  case v.kind
    of ltInteger: v.ival
    of ltNumber:
      let (intPart, fltPart) = splitDecimal(v.nval)
      if fltPart == 0.0:
        return int64(intPart)
      else:
        raise newException(LuaRuntimeError, "Number has no integer representation")
    else: raise newException(LuaRuntimeError, $v.kind & " has no integer representation")

func kind*(v: LuaValue): LuaKind = v.kind
func isLuaNil*(v: LuaValue): bool = v.kind == ltNil
func isBool*(v: LuaValue): bool = v.kind == ltBool
func isFloat*(v: LuaValue): bool = v.kind == ltNumber
func isInteger*(v: LuaValue): bool = v.kind == ltInteger
func isNumber*(v: LuaValue): bool = v.isInteger or v.isFloat
func isString*(v: LuaValue): bool = v.kind == ltString
func isTable*(v: LuaValue): bool = v.kind == ltTable
func isNimFn*(v: LuaValue): bool = v.kind == ltNativeFn
func isNimFnVM*(v: LuaValue): bool = v.kind == ltNativeFnVM
func isLuaFn*(v: LuaValue): bool = v.kind == ltClosure
func isUserData*(v: LuaValue): bool = v.kind == ltUserData
func isCallable*(v: LuaValue): bool = isNimFn(v) or isLuaFn(v) or isNimFnVM(v)
proc isSet*(v: LuaValue): bool =
  isTable(v) and not isNil(v.mt) and v.mt.tval.hasKey(MTTYPE) and v.mt.tval[MTTYPE].sval == "set"
# Helper constructor

proc getInt*(v: LuaValue): int64 = v.ival
proc getBool*(v: LuaValue): bool = v.bval
proc getNumber*(v: LuaValue): float64 = v.nval
proc getString*(v: LuaValue): string = v.sval
proc getTable*(v: LuaValue): LuaTable = v.tval
proc getClosure*(v: LuaValue): LuaClosure = v.fnVal
proc getFunction*(v: LuaClosure): LuaFunction = v.fn
proc getFunction*(v: LuaValue): LuaFunction = v.fnVal.getFunction()
proc getNativeFn*(v: LuaValue): NativeFunc = v.nativeFn
proc getNativeFnVM*(v: LuaValue): NativeFuncVM = v.nativeFnVM
proc getUserData*(v: LuaValue): LuaUserData = v.ud

proc hasMetatable*(v: LuaValue): bool = (isTable(v) or isUserData(v)) and not isNil(v.mt)
proc hasMetaKey*(v: LuaValue, k: LuaValue): bool = v.mt.tval.hasKey(k)

proc newLuaValue(kind: LuaKind): LuaValue = LuaValue(kind: kind)
proc newLuaNil*(): LuaValue = newLuaValue(ltNil)

proc newNimFn*(fn: NativeFunc): LuaValue =
  result = newLuaValue(ltNativeFn)
  result.nativefn = fn

proc newNimFnVM*(fn: NativeFuncVM): LuaValue =
  result = newLuaValue(ltNativeFnVM)
  result.nativeFnVM = fn

proc newLuaFunction*(name: string, arity: int, chunk: Chunk,
    isVararg: bool = false): LuaFunction = LuaFunction(name: name, arity: arity,
    chunk: chunk, isVararg: isVararg)

proc wrapLuaClosure*(name: string, arity: int, chunk: Chunk,
    isVararg: bool = false): LuaValue =
  result = newLuaValue(ltClosure)
  result.fnVal = LuaClosure(upvalues: @[])
  result.fnVal.fn = newLuaFunction(name, arity, chunk, isVararg)

proc newLuaClosure*(name: string, arity: int, chunk: Chunk,
    isVararg: bool = false): LuaClosure =
  result = LuaClosure(upvalues: @[])
  result.fn = newLuaFunction(name, arity, chunk, isVararg)

proc wrapLuaClosure*(cl: LuaClosure): LuaValue =
  result = newLuaValue(ltClosure)
  result.fnVal = cl

proc newLuaNumber*(v: sink float64): LuaValue =
  result = newLuaValue(ltNumber)
  result.nval = v
proc newLuaInteger*(v: sink int64): LuaValue =
  result = newLuaValue(ltInteger)
  result.ival = v
proc newLuaBool*(v: sink bool): LuaValue =
  result = newLuaValue(ltBool)
  result.bval = v
proc newLuaString*(v: sink string): LuaValue =
  result = newLuaValue(ltString)
  result.sval = v

proc newUpvalue*(stack:LuaStack,location: int, isLocal: bool, isOpen: bool = true,closed: LuaValue = nil): LuaUpValue = 
  result = LuaUpValue(stack: stack,location: location, isLocal: isLocal, closed: closed,isOpen: isOpen)

proc newLuaTable*(): LuaValue =
  result = newLuaValue(ltTable)
  result.tval = newTable[LuaValue, LuaValue]()

proc newUserData*(v: LuaUserData): LuaValue =
  result = newLuaValue(ltUserData)
  result.ud = v

proc newLuaEnum*(members: openArray[string]): LuaValue =
  result = newLuaTable()
  for i, name in members:
    let v = newLuaInteger(int64(i + 1))
    result.tval[newLuaString(name)] = v
    result.tval[v] = newLuaString(name)

proc newLuaEnum*(members: openArray[tuple[name,display:string]]): LuaValue =
  result = newLuaTable()
  for i, m in members:
    let v = newLuaInteger(int64(i + 1))
    result.tval[newLuaString(m.name)] = v
    result.tval[v] = newLuaString(m.display)

proc chunk*(cl: LuaClosure): Chunk = cl.fn.chunk

proc truthy*(a: LuaValue): bool =
  if isNil(a): return false
  case a.kind
  of ltNil: false
  of ltBool: a.bval
  of ltNumber, ltString, ltTable, ltClosure, ltNativeFn, ltNativeFnVM,
      ltInteger, ltUserData: true


proc `==`*(a, b: LuaValue): bool =
  if isNil(a) and isNil(b): return true
  if isNil(a) or isNil(b): return false
  if a.kind == b.kind:
    case a.kind
    of ltNil: true
    of ltBool: a.bval == b.bval
    of ltInteger, ltNumber: numVal(a) == numVal(b)
    of ltString: a.sval == b.sval
    of ltTable: cast[pointer](a.tval) == cast[pointer](b.tval)
    of ltNativeFn, ltNativeFnVM,ltClosure: cast[pointer](a) == cast[pointer](b)   # same wrapper object
    of ltUserData: cast[pointer](a.ud) == cast[pointer](b.ud)    
  else:
    if isNumber(a) and isNumber(b): return numVal(a) == numVal(b)
    else: return false

proc hash*(v: LuaValue): Hash =
  case v.kind
  of ltNil: 0.hash()
  of ltNumber, ltInteger: numVal(v).hash()
  of ltBool: v.bval.hash()
  of ltString: v.sval.hash()
  of ltClosure: cast[int](v.fnVal).hash()
  of ltTable: cast[int](v.tval).hash()
  of ltUserData: cast[int](v.ud).hash()
  of ltNativeFn: addr(v.nativeFn).hash()
  of ltNativeFnVM: addr(v.nativeFnVM).hash()

proc `$`*(v: LuaValue): string =
  if isNil(v): return "nil"
  case v.kind:
  of ltBool: $v.bval
  of ltNil: "nil"
  of ltNumber: $v.nval
  of ltInteger: $v.ival
  of ltString: v.sval
  of ltClosure: "function: " & v.fnVal.fn.name
  of ltNativeFn, ltNativeFnVM: "function: 0x" & $cast[int](v)
  of ltTable: "table: 0x" & $cast[int](v)
  of ltUserData: "userdata: 0x" & $cast[int](v)

proc expect(v: LuaValue, k: LuaKind): bool = v.kind == k
proc expect*(v: LuaValue, k: set[LuaKind]): bool = v.kind in k
