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
        LUA_TNUMBER
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
    Instruction* = ref object
        opcode*: OpCodes
        case mode*: OpModes
            of OMABC:
                abc*: tuple[a,b,c:uint8]
            of OMABx:
                abx*: tuple[a:uint8,bx:uint16]
            of OMAsBx:
                asbx*: tuple[a:uint8,bx:int16]
            of OMAx:
                ax*: uint32
    GCObject* = object
    CallInfo = ref CallInfoBase
    CallInfoBase* =  object
        fun*:int
        top*:int
        nresults*: int
        callstatus*: uint8
        previous*: CallInfo
        next*: CallInfo
        case kind*:ClosureKind
            of LClosure: 
                base*: int
                code*: seq[Instruction]
                savedpc*: int = 0
            of NClosure: 
                ctx*:int
                k*: LuaNimFunction
                old_errfunc*: int
                old_allowhook*: uint8
                status*: uint8
    GlobalState* = object #placeholder
    LuaState* = object 
        # CommonHeader;
        status*: uint8
        # StkId top
        LG*: GlobalState
        CI*: CallInfo
        oldPC*: uint32
        # stkId stack_last;  /* last free slot in the stack */
        #StkId stack; 
        stacksize*: int
        nny*: uint16
        nCcalls*: uint16
        hookmask*: uint8
        allowhook*: uint8
        basehookcount*: int
        hookcount*: int
        # lua_Hook hook;
        openupval*: ptr GCObject
        gclist*: ptr GCObject
        # struct lua_longjmp *errorJmp;
        errfunc*: int64
        base_ci*: CallInfo
    LuaNumber* = distinct float64
    LuaString* = distinct string
    FuncState* = distinct pointer
    ZIO* = distinct pointer
    Dyndata* = distinct pointer
    LuaNimFunction* = proc(L:LuaState):int
    LuaReader* = proc(l:LuaState,sz:int,ud:auto):string
    LuaWriter* = proc(l:LuaState,p:pointer,sz:int,ud:auto):int
    LuaAlloc* = proc(ud:auto,pt:pointer,osize:int,nsize:int)
    LuaTable* = Table[string,LuaValue]
    UserData* = ref LuaTable
    LuaValue* = ref LuaValueBase
    LuaValueBase = object
        case kind*: LuaValueKind
            of LUA_TNIL: discard
            of LUA_TBOOLEAN: boolv*:bool
            of LUA_TLIGHTUSERDATA: luserv*: UserData
            of LUA_TNUMBER: numv*: LuaNumber
            of LUA_TSTRING: strv*: LuaString
            of LUA_TTABLE: tablev*: LuaTable
            of LUA_TFUNCTION: funcv*: Closure
            of LUA_TUSERDATA: userv*: UserData
            of LUA_TTHREAD: threadv*: LuaState
            of LUA_TPROTO: protov*: Proto
    Proto* = object 
        constants*: seq[LuaValue]
        code*: seq[Instruction]
        prototypes*: seq[ref Proto]
        upvalues*: seq[LuaValue]
    NimClosure* = ref object
        fun*:LuaNimFunction
        upvalues*: seq[LuaValue]
    LuaClosure* = ref object
        proto*: ref Proto
        upvalues*: seq[LuaValue]
    Closure* = object
        case kind*: ClosureKind
            of LClosure: l*: LuaClosure
            of NClosure: n*: NimClosure