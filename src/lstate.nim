
type 
    StringTable* = object 
        hash: GCObject
        nuse: uint32
        size: int
    GCObject* = object #placeholder
    CallInfo* =  object #placeholder
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






