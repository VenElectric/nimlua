import types

#func newLClosure*(v:Closure): LuaValue = LuaValue(kind: LUA_TFUNCTION, funcv: v)

proc newLClosure*(): Closure = discard

proc newNClosure*(): Closure = discard