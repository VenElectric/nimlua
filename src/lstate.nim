import types

type 
    CallInfo* = ref CallInfoBase
    CallInfoBase =  object
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
    LuaState* = ref LuaStateBase
    LuaStateBase* = object 
        # CommonHeader;
        status: uint8
        # StkId top
        LG: GlobalState
        CI: CallInfo
        oldPC: uint32
        stack: seq[LuaValue]
        stacksize: int
        nny: uint16
        nCcalls: uint16
        hookmask: uint8
        allowhook: uint8
        basehookcount: int
        hookcount: int
        errfunc: int64
        base_ci: CallInfo

template CT(x:int):int = 1 shl x

template isLua(ci:untyped): untyped = ci.callstatus and CIST_LUA
    

const 
    CIST_LUA* = CT(0)
    CIST_HOOK* = CT(1)
    CIST_REENTRY* = CT(2)
    CIST_YIELDED* = CT(3)
    CIST_YPCALL* = CT(4)
    CIST_STAT* = CT(5)
    CIST_TAIL* = CT(6)
    CIST_HOOKYIELD* = CT(7)






