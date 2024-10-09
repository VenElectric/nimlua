import types


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






