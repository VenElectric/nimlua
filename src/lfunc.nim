import types

#func newLClosure*(v:Closure): LuaValue = LuaValue(kind: LUA_TFUNCTION, funcv: v)

proc newLClosure*(L:LuaState,n:int): Closure = 
    result = Closure(kind: LClosure)
    result.l.upvalues = newSeqOfCap[LuaValue](n)
    result.l.proto = Proto()



proc newNClosure*(): Closure = discard