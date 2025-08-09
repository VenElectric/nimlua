import std/[tables]
import lexception,lobject

type
    MetaKeys* = enum 
        MNEW = "__new"
        MADD = "__add"
        MSUB = "__sub"
        MMUL = "__mul"
        MDIV = "__div"
        MUNM = "__unm"
        MMOD = "__mod"
        MPOW = "__pow"
        MIDIV = "__idiv"
        MBAND = "__band"
        MBOR = "__bor"
        MBXOR = "__bxor"
        MBNOT = "__bnot"
        MSHL = "__shl"
        MSHR = "__shr"
        MEQ = "__eq"
        MLE = "__le"
        MLT = "__lt"
        MCONCAT = "__concat"
        MLEN = "__len"
        MINDEX = "__index"
        MNEWINDEX = "__newindex"
        MCALL = "__call"
        MSTR = "__tostring"
        MPAIRS = "__pairs"
        MIPAIRS = "__ipairs"

type
    NimFunction* = proc(args:varargs[MetaBase]): MetaBase
    MetaTable* = Table[string, NimFunction]

using
    mb: MetaBase
    vmb: var MetaBase

proc getMetaMethod*(mt;key:MetaKeys): Option[LuaValue] = 
    if hasKey(mt,key):
        result = some(mt[key])

proc getMetaMethod*(lv;key:MetaKeys): Option[LuaValue] = 
    if hasKey(lv.metatable,key):
        result = some(lv.metatable[key])

proc setMetaMethod*(lv;key:MetaKeys,mm:NimFunction) = lv.metatable[key] = newLFunction(mm)

# __index???
proc setMetaMethod*(lv;key:MetaKeys,mm:LuaValue) = lv.metatable[key] = mm

proc unwrapMetaMethod*(lv): NimFunction = 
    expect(lv,LUA_TFUNCTION)
    result = lv.funcv

proc getMetatable(o:LuaValue): MetaTable = o.metatable

proc newMetaTable*(methods:openArray[tuple[key:MetaKeys,fn:NimFunction]]): MetaTable = 
    result = initTable[MetaKeys,LuaValue](len(methods))
    for m in methods:
        let key = m.key
        let fn = m.fn
        result[key] = newLFunction(fn)

proc newMetaTable*(methods:openArray[tuple[key:MetaKeys,mm:LuaValue]]): MetaTable = 
    result = initTable[MetaKeys,LuaValue](len(methods))
    for m in methods:
        let key = m.key
        let mm = m.mm
        result[key] = mm

proc newMetaTable*(methods:varargs[tuple[key:MetaKeys,mm:LuaValue]]): MetaTable =
    result = initTable[MetaKeys,LuaValue](len(methods))
    for m in items(methods):
        let key = m.key
        let mm = m.mm
        result[key] = mm