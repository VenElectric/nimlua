import std/tables
type 
    OpCodes* {.size: sizeof(uint8).} = enum
        OP_MOVE,
        OP_LOADK,
        OP_LOADKX,
        OP_LOADBOOL,
        OP_LOADNIL,
        OP_GETUPVAL,
        OP_GETTABUP,
        OP_GETTABLE,
        OP_SETTABUP,
        OP_SETUPVAL,
        OP_SETTABLE,
        OP_NEWTABLE,
        OP_SELF,
        OP_ADD,
        OP_SUB,
        OP_MUL,
        OP_DIV,
        OP_MOD,
        OP_POW,
        OP_UNM,
        OP_NOT,
        OP_LEN,
        OP_CONCAT,
        OP_JMP,
        OP_EQ,
        OP_LT,
        OP_LE,
        OP_TEST,
        OP_TESTSET,
        OP_CALL,
        OP_TAILCALL,
        OP_RETURN,
        OP_FORLOOP,
        OP_FORPREP,
        OP_TFORCALL,
        OP_TFORLOOP,
        OP_SETLIST,
        OP_CLOSURE,
        OP_VARARG,
        OP_EXTRAARG
    ClosureKind* = enum
        LClosure
        NClosure
    OpModes* = enum
        OMABC,
        OMABx,
        OMAsBx,
        OMAx
    ThreadStatus* = enum
        LUA_OK = 0
        LUA_YIELD = 1
        LUA_ERRRUN = 2
        LUA_ERRSYNTAX = 3
        LUA_ERRMEM = 4
        LUA_ERRGCMM = 5
        LUA_ERRERR = 6
    LuaValueKind* = enum
        LUA_TNIL
        LUA_TBOOLEAN
        LUA_TLIGHTUSERDATA
        LUA_TFLOAT
        LUA_TINTEGER
        LUA_TSTRING
        LUA_TTABLE
        LUA_TFUNCTION
        LUA_TUSERDATA
        LUA_TTHREAD
        LUA_TPROTO
    BinOpr* = enum
       OPR_ADD
       OPR_SUB
       OPR_MUL
       OPR_DIV
       OPR_MOD
       OPR_POW
       OPR_CONCAT
       OPR_EQ
       OPR_LT
       OPR_LE
       OPR_NE
       OPR_GT
       OPR_GE
       OPR_AND
       OPR_OR
       OPR_NOBINOPR 
type 
    LuaNimFunction* = proc(L:LuaState):int
    LuaTable* = ref Table[string,LuaValue]
    UserData* = ref object of RootObj
    LuaState* = object of RootObj
    LuaInteger* = distinct int64
    LuaFloat* = distinct float64
    LuaString* = distinct string
    LuaValue* {.acyclic.} = ref object
        case kind*: LuaValueKind
            of LUA_TNIL: discard
            of LUA_TBOOLEAN: boolv*:bool
            of LUA_TLIGHTUSERDATA: luserv*: UserData
            of LUA_TFLOAT: floatv*: LuaFloat
            of LUA_TINTEGER: intv*: LuaInteger
            of LUA_TSTRING: strv*: LuaString
            of LUA_TTABLE: tablev*: LuaTable
            of LUA_TFUNCTION: funcv*: int
            of LUA_TUSERDATA: userv*: UserData
            of LUA_TTHREAD: threadv*: LuaState
            of LUA_TPROTO: protov*: int

# proc `savedpc=`(c:CallInfo,value:int) = c.savedpc 