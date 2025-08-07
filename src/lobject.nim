import std/[tables,math,options]
import todo

type
    LuaValueKind* = enum
        LUA_TNIL
        LUA_TBOOLEAN
        LUA_TFLOAT
        LUA_TINTEGER
        LUA_TSTRING
        LUA_TTABLE
        LUA_TFUNCTION
    MetaKeys* = enum 
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


# const MetaKeysStr = ["__add", "__sub", "__mul", "__div", "__unm", "__mod", "__pow",
#         "__idiv", "__band", "__bor", "__bxor", "__bnot", "__shl", "__shr",
#         "__eq", "__lt", "__le", "__concat","__len","__index","__newindex","__call","__tostring","__pairs","__ipairs"]

type
    ValueError = object of CatchableError
    LuaTable* = Table[string, LuaValue]
    NimFunction* = proc(args: varargs[LuaValue]): LuaValue
    LuaValue* {.acyclic.} = ref object of MetaBase
        case kind*: LuaValueKind
            of LUA_TNIL: discard
            of LUA_TBOOLEAN: boolv*: bool
            of LUA_TFLOAT: floatv*: float64
            of LUA_TINTEGER: intv*: int64
            of LUA_TSTRING: strv*: string
            of LUA_TTABLE: tablev*: LuaTable
            of LUA_TFUNCTION: funcv*: NimFunction
    MetaTable* = Table[string, NimFunction]
    MetaBase* = ref object of RootObj
        metatable*: MetaTable

using
    lv: LuaValue
    lvk: LuaValueKind

func k*(lv): LuaValueKind = lv.kind

func check*(one, two: LuaValueKind): bool = one == two

func check*(toCheck:LuaValueKind,accept:set[LuaValueKind]): bool = toCheck in accept

func check*(one:LuaValue,two:set[LuaValueKind]): bool = one.k in two

proc expect*(expected, compare: LuaValueKind,message:string) =
    if not check(expected, compare):
        raise newException(CatchableError, message)

proc expect*(expected:LuaValueKind, compare: set[LuaValueKind],message:string) =
    if expected notin compare:
        raise newException(CatchableError, message)

# proc newLuaValue(kind: LuaValueKind): LuaValue =
#     result = new LuaValue
#     result.kind = kind

proc getMetatable(o:MetaBase): MetaTable = o.metatable

proc newLNil*(): LuaValue =
    result = LuaValue(kind:LUA_TNIL)

proc newLBool*(v: bool): LuaValue =
    result = LuaValue(kind:LUA_TBOOLEAN,boolv:v)

proc newLInteger*(v: int64): LuaValue =
    result = LuaValue(kind:LUA_TINTEGER,intv:v)

proc newLFloat*(v: float64): LuaValue =
    result = LuaValue(kind: LUA_TFLOAT, floatv: v)

proc newLString*(v: string): LuaValue =
    result = LuaValue(kind:LUA_TSTRING,strv: v)

proc newLTable*(v: LuaTable): int = discard


func kisNil*(lv): bool = check(lv.k, LUA_TNIL)
func kisBool*(lv): bool = check(lv.k, LUA_TBOOLEAN)
func kisInteger*(lv): bool = check(lv.k, LUA_TINTEGER)
func kisFloat*(lv): bool = check(lv.k, LUA_TFLOAT)
func kisString*(lv): bool = check(lv.k, LUA_TSTRING)
func kisTable*(lv): bool = check(lv.k, LUA_TTABLE)
func kisClosure*(lv): bool = check(lv.k, LUA_TFUNCTION)

proc getString*(lv): string =
    expect(lv.k, LUA_TSTRING,"Invalid Kind")
    result = lv.strv

proc getInteger*(lv): int64 =
    expect(lv.k, LUA_TINTEGER,"Invalid Kind")
    result = lv.intv

proc getFloat*(lv): float64 =
    expect(lv.k, LUA_TFLOAT,"Invalid Kind")
    result = lv.floatv

proc getBool*(lv): bool =
    expect(lv.k, LUA_TBOOLEAN,"Invalid Kind")
    result = lv.boolv

proc getTable*(lv): LuaTable =
    expect(lv.k, LUA_TTABLE,"Invalid Kind")
    result = lv.tablev

converter toFloat64*(v:int64):float64 = float64(v)


proc newMetaTable*(methods:openArray[tuple[key:MetaKeys,fn:NimFunction]]): MetaTable = 
    result = initTable[string,NimFunction](len(methods))
    for m in methods:
        let key = m.key
        let fn = m.fn
        result[$key] = fn

func hasKey(t:MetaTable,key:string): bool = result = key in t
# proc metatable_check(mt:MetaTable,key:MetaKeys,args:varargs[LuaValue]): Option[LuaValue] =
#     result = none(LuaValue)
#     if hasKey(mt,$key):
#         let fn = mt[$key]
#         result = some(fn(args))

func truthiness(v:LuaValue): bool = 
    if kisNil(v):
        return false
    elif kisBool(v):
        return v.boolv
    else:
        return true

proc try_metatable(lhs,rhs:LuaValue,key:MetaKeys): Option[LuaValue] =
    let lhsMeta = getMetatable(lhs)
    let rhsMeta = getMetatable(rhs)
    if hasKey(lhsMeta,$key):
        let fn = lhsMeta[$key]
        result = some(fn(lhs,rhs))
    elif hasKey(rhsMeta,$key):
        let fn = rhsMeta[$key]
        result = some(fn(rhs,lhs))
    else:
        result = none(LuaValue)

proc try_metatable(rhs:LuaValue,key:MetaKeys): Option[LuaValue] =
    let rhsMeta = getMetatable(rhs)
    if hasKey(rhsMeta,$key):
        let fn = rhsMeta[$key]
        result = some(fn(rhs))
    else:
        result = none(LuaValue)


template binop(lhs,rhs:LuaValue,key:MetaKeys,op:untyped):untyped = 
    result = none(LuaValue)
    if kisInteger(lhs) and kisInteger(rhs):
        result = some(newLInteger(`op`(lhs.intv,rhs.intv)))
    elif kisInteger(lhs) and kisFloat(rhs):
        result = some(newLFloat(`op`(lhs.intv,rhs.floatv)))
    elif kisFloat(lhs) and kisInteger(rhs):
        result = some(newLFloat(`op`(lhs.floatv , rhs.intv)))
    elif kisFloat(lhs) and kisFloat(rhs):
        result = some(newLFloat(`op`(lhs.floatv,rhs.floatv)))
    else:
        result = try_metatable(lhs,rhs,key)

template integerbinop(lhs,rhs:LuaValue,key:MetaKeys,op:untyped):untyped = 
    result = none(LuaValue)
    if kisInteger(lhs) and kisInteger(rhs):
        result = some(newLInteger(`op`(lhs.intv,rhs.intv)))
    else:
        result = try_metatable(lhs,rhs,key)

template compbinop(lhs,rhs:LuaValue,key:MetaKeys,op:untyped): untyped = 
    result = none(LuaValue)
    if check(lhs.k,rhs.k):
        if kisInteger(lhs):
            result = some(newLBool(`op`(lhs.intv,rhs.intv)))
        elif kisFloat(lhs):
            result = some(newLBool(`op`(lhs.floatv,rhs.floatv)))
        elif kisString(lhs):
            result = some(newLBool(`op`(lhs.strv,rhs.strv)))
        elif kisBool(lhs):
            result = some(newLBool(`op`(lhs.boolv,rhs.boolv)))
        elif kisNil(lhs):
            result = some(newLBool(true))
        elif kisTable(lhs):
            result = try_metatable(lhs,rhs,key)
        else:
            result = some(newLBool(false))
    else:
        if kisFloat(lhs) and kisInteger(rhs):
            result = some(newLBool(`op`(lhs.floatv,rhs.intv)))
        elif kisInteger(lhs) and kisFloat(rhs):
            result = some(newLBool(`op`(lhs.intv,rhs.floatv)))
        else:
            result = try_metatable(lhs,rhs,key)

template unop(rhs:LuaValue,key:MetaKeys,op:untyped): untyped =
    result = none(LuaValue)
    if kisInteger(rhs):
        result = some(newLInteger(`op`(rhs.intv)))
    elif kisFloat(rhs):
        result = some(newLFloat(`op`(rhs.floatv)))
    else:
        result = try_metatable(rhs,key)

template logicunop(rhs:LuaValue,key:MetaKeys,op:untyped): untyped =
    result = none(LuaValue)
    if kisInteger(rhs):
        result = some(newLInteger(`op`(rhs.intv)))
    elif kisBool(rhs):
        result = some(newLBool(`op`(rhs.boolv)))
    else:
        result = try_metatable(rhs,key)

template logicbinop(lhs,rhs:LuaValue,key:MetaKeys,op:untyped):untyped =
    result = none(LuaValue)
    if check(lhs.k,rhs.k):
        if kisInteger(lhs):
            result = some(newLInteger(`op`(lhs.intv,rhs.intv)))
        elif kisBool(lhs):
            result = some(newLBool(`op`(lhs.boolv,rhs.boolv)))
        else:
            result = try_metatable(rhs,key)
    else:
        result = try_metatable(rhs,key)

proc len*(v:LuaValue): Option[LuaValue] =
    case v.k:
        of LUA_TFLOAT,LUA_TINTEGER,LUA_TNIL: discard # raise (?)
        of LUA_TSTRING: result = some(newLInteger(len(v.strv)))
        of LUA_TTABLE: result = some(newLInteger(len(v.tablev)))
        else: discard # raise (?)

# float or integer
proc `+`*(lhs,rhs:LuaValue): Option[LuaValue] = binop(lhs,rhs,MADD,`+`)
    
# float or integer
proc `-`*(lhs,rhs:LuaValue): Option[LuaValue] = binop(lhs,rhs,MSUB,`-`)

# division returns a float
proc `/`*(lhs,rhs:LuaValue): Option[LuaValue] = integerbinop(lhs,rhs,MDIV,`div`)

# float or integer
proc `*`*(lhs,rhs:LuaValue): Option[LuaValue] = binop(lhs,rhs,MADD,`*`)

# integer
proc `//`*(lhs,rhs:LuaValue): Option[LuaValue] = integerbinop(lhs,rhs,MDIV,floorDiv)

#integer
proc `mod`*(lhs,rhs:LuaValue): Option[LuaValue] = integerbinop(lhs,rhs,MDIV,floorDiv)


proc `==`*(lhs,rhs:LuaValue): Option[LuaValue] = 
    compbinop(lhs,rhs,MEQ,`==`)

proc `~=`*(lhs,rhs:LuaValue): Option[LuaValue] = 
    compbinop(lhs,rhs,MEQ,`!=`)

proc `<`*(lhs,rhs:LuaValue): Option[LuaValue] = 
    compbinop(lhs,rhs,MEQ,`<`)

proc `<=`*(lhs,rhs:LuaValue):Option[LuaValue] = 
    compbinop(lhs,rhs,MEQ,`<=`)

proc `>`*(lhs,rhs:LuaValue): Option[LuaValue] = 
    compbinop(lhs,rhs,MEQ,`>`)

proc `>=`*(lhs,rhs:LuaValue): Option[LuaValue] = 
    compbinop(lhs,rhs,MEQ,`>=`)

proc pow*(lhs,rhs:LuaValue): Option[LuaValue] = 
    result = none(LuaValue)
    if kisInteger(lhs) and kisInteger(rhs):
        result = some(newLFloat(pow(lhs.intv,rhs.intv)))
    elif kisInteger(lhs) and kisFloat(rhs):
        result = some(newLFloat(pow(lhs.intv,rhs.floatv)))
    elif kisFloat(lhs) and kisInteger(rhs):
        result = some(newLFloat(pow(lhs.floatv , rhs.intv)))
    elif kisFloat(lhs) and kisFloat(rhs):
        result = some(newLFloat(pow(lhs.floatv,rhs.floatv)))
    else:
        result = try_metatable(lhs,rhs,MPOW)



proc `-`*(rhs:LuaValue): Option[LuaValue] = 
    unop(rhs,MUNM,`-`)

proc `and`*(lhs,rhs:LuaValue): Option[LuaValue] = 
    logicbinop(lhs,rhs,MBAND,`and`)

proc `or`*(lhs,rhs:LuaValue): Option[LuaValue] = 
    logicbinop(lhs,rhs,MBOR,`or`)

proc `xor`*(lhs,rhs:LuaValue): Option[LuaValue] = 
    logicbinop(lhs,rhs,MBXOR,`xor`)

proc `shr`*(lhs,rhs:LuaValue): Option[LuaValue] = 
    integerbinop(lhs,rhs,MSHR,`shr`)

proc `shl`*(lhs,rhs:LuaValue): Option[LuaValue] = 
    integerbinop(lhs,rhs,MSHL,`shl`)

proc `not`*(rhs:LuaValue): Option[LuaValue] = 
    logicunop(rhs,MBNOT,`not`)

proc `..`*(lhs,rhs:LuaValue): Option[LuaValue] = 
    if check(lhs.k,rhs.k) and kisString(lhs):
        result = some(newLString(lhs.strv & rhs.strv))
    else:
        result = try_metatable(lhs,rhs,MCONCAT)

proc call*(o:LuaValue,args:varargs[LuaValue]): Option[LuaValue] =
    result = none(LuaValue)
    if check(o.k,LUA_TFUNCTION):
        discard
    else:
        let meta = getMetatable(o)
        if hasKey(meta,$MCALL):
            let fn = meta[$MCALL]
            result = some(fn(args))
    



