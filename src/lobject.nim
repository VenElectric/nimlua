import std/[tables]

type
    LuaValueKind* = enum
        LUA_TNIL = "nil"
        LUA_TBOOLEAN = "boolean"
        LUA_TFLOAT = "float"
        LUA_TINTEGER = "integer"
        LUA_TSTRING = "string"
        LUA_TTABLE = "table"
        LUA_TFUNCTION = "function"
    TableKind* = enum
        STR_TABLE
        INT_TABLE
    MetaKeys* = enum
        MAND = "__and"
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





# add float / integer
# sub float / integer


# const MetaKeysStr = ["__add", "__sub", "__mul", "__div", "__unm", "__mod", "__pow",
#         "__idiv", "__band", "__bor", "__bxor", "__bnot", "__shl", "__shr",
#         "__eq", "__lt", "__le", "__concat","__len","__index","__newindex","__call","__tostring","__pairs","__ipairs"]

# remove metatable from LuaValue object and make them separate entities
# when parsing, need to lookup metatable for type
# IntMeta,FloatMeta, etc....
# each table has their own metatable?
# don't think that functions need a metatable, right?

type
    FuncType = proc(args: varargs[LuaValue]): LuaValue
    NimFn* = ref object
        arity*: Natural
        name*: string
        fn*: FuncType
    MetaTable* = TableRef[string, NimFn]
    LuaTable* = Table[string, LuaValue]
    LuaValue* {.acyclic.} = ref object
        case kind*: LuaValueKind
            of LUA_TNIL: discard
            of LUA_TBOOLEAN: boolv*: bool
            of LUA_TFLOAT: floatv*: float64
            of LUA_TINTEGER: intv*: int64
            of LUA_TSTRING: strv*: string
            of LUA_TTABLE:
                mt*: MetaTable
                tablev*: LuaTable
            of LUA_TFUNCTION: funcv*: NimFn



let LUANIL* = LuaValue(kind: LUA_TNIL)

using
    lv: LuaValue
    lvk: LuaValueKind
    lt: LuaTable
    vlt: var LuaTable
    slv: sink LuaValue

