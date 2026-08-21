import std/[tables, hashes]
from strutils import toHex
import lerror,ltypes


proc `==`*(a, b: LuaValue): bool
proc hash*(v: LuaValue): Hash

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

func kind*(v: LuaValue): LuaKind = v.kind
func isLuaNil*(v: LuaValue): bool = v.kind == ltNil
func isBool*(v: LuaValue): bool = v.kind == ltBool
func isNumber*(v: LuaValue): bool = v.kind == ltNumber
func isString*(v: LuaValue): bool = v.kind == ltString
func isTable*(v: LuaValue): bool = v.kind == ltTable
func isNimFn*(v: LuaValue): bool = v.kind == ltNativeFn
func isNimFnVM*(v:LuaValue): bool = v.kind == ltNativeFnVM
func isLuaFn*(v: LuaValue): bool = v.kind == ltClosure
# Helper constructor
proc newLuaValue(kind: LuaKind): LuaValue = LuaValue(kind: kind)
proc newLuaNil*(): LuaValue = newLuaValue(ltNil)

proc newNimFn*(fn: NativeFunc): LuaValue =
  result = newLuaValue(ltNativeFn)
  result.nativefn = fn

proc newNimFnVM*(fn: NativeFuncVM): LuaValue =
  result = newLuaValue(ltNativeFnVM)
  result.nativeFnVM = fn

proc newLuaFunction*(name: string, arity: int, chunk: Chunk,isVararg:bool = false): LuaFunction = LuaFunction(name: name, arity: arity, chunk: chunk,isVararg:isVararg)

proc wrapLuaClosure*(name: string,arity:int,chunk:Chunk,isVararg:bool = false): LuaValue =
  result = newLuaValue(ltClosure)
  result.fnVal = LuaClosure(upvalues: @[])
  result.fnVal.fn = newLuaFunction(name,arity,chunk,isVararg)

proc newLuaClosure*(name: string,arity:int,chunk:Chunk,isVararg:bool = false): LuaClosure =
  result = LuaClosure(upvalues: @[])
  result.fn = newLuaFunction(name,arity,chunk,isVararg)

proc wrapLuaClosure*(cl:LuaClosure): LuaValue = 
  result = newLuaValue(ltClosure)
  result.fnVal = cl

proc newLuaNumber*(v: sink float64): LuaValue =
  result = newLuaValue(ltNumber)
  result.nval = v
proc newLuaBool*(v: sink bool): LuaValue =
  result = newLuaValue(ltBool)
  result.bval = v
proc newLuaString*(v: sink string): LuaValue =
  result = newLuaValue(ltString)
  result.sval = v
# location*: int
#     isLocal*: bool
#     closed*: LuaValue
proc newUpvalue*(location:int,isLocal: bool,isOpen:bool = true,closed:LuaValue = nil): LuaUpValue =
  LuaUpValue(location:location,isLocal: isLocal, closed: closed,isOpen: isOpen)

proc chunk*(cl:LuaClosure): Chunk = cl.fn.chunk

proc truthy*(a:LuaValue): bool =
  if isNil(a): return false
  case a.kind
  of ltNil: false
  of ltBool: a.bval
  of ltNumber,ltString,ltTable,ltClosure,ltNativeFn,ltNativeFnVM: true
    

proc `==`*(a, b: LuaValue): bool =
  if isNil(a) and isNil(b): return true
  if isNil(a) or isNil(b): return false
  if a.kind != b.kind: return false
  case a.kind
  of ltNil: true
  of ltBool: a.bval == b.bval
  of ltNumber: a.nval == b.nval
  of ltString: a.sval == b.sval
  of ltTable: a.tval == b.tval
  of ltClosure: a.fnVal.fn == b.fnVal.fn
  of ltNativeFn,ltNativeFnVM: false

proc hash*(v: LuaValue): Hash =
  case v.kind
  of ltNil: 0.hash()
  of ltNumber: v.nval.hash()
  of ltBool: v.bval.hash()
  of ltString: v.sval.hash()
  of ltClosure: addr(v.fnVal).hash()
  of ltTable: addr(v.tval).hash()
  of ltNativeFn: addr(v.nativeFn).hash()
  of ltNativeFnVM: addr(v.nativeFnVM).hash()

proc newLuaTable*(): LuaValue =
  result = newLuaValue(ltTable)
  result.tval = newTable[LuaValue, LuaValue]()

proc `$`*(v: LuaValue): string =
  if isNil(v): return "nil"
  case v.kind:
  of ltBool: $v.bval
  of ltNil: "nil"
  of ltNumber: $v.nval
  of ltString: "\"" & v.sval & "\""
  of ltClosure: "function: " & v.fnVal.fn.name
  of ltNativeFn,ltNativeFnVM: "function: 0x" & $cast[int](v)
  of ltTable: "table: 0x" & $cast[int](v)

proc expect(v: LuaValue, k: LuaKind): bool = v.kind == k
proc expect*(v:LuaValue,k: set[LuaKind]): bool = v.kind in k
