import std/[tables,options]
from lobject import LuaValue,LUANIL

type
    LuaEnvironment {.acyclic.} = ref object
        locals: Table[string,LuaValue]
        enclosing: Option[LuaEnvironment]

using
    env:LuaEnvironment

proc newEnvironment*(): LuaEnvironment =
    result = new LuaEnvironment
    result.locals = initTable[string,LuaValue]()

proc newEnvironment*(enclosing:LuaEnvironment): LuaEnvironment =
    result = new LuaEnvironment
    result.locals = initTable[string,LuaValue]()
    result.enclosing = some(enclosing)

func isRoot*(env): bool = isNone(env.enclosing)

proc `[]`*(env;key:string): LuaValue = 
    if hasKey(env.locals,key):
        result = env.locals[key]
    else:
        if isSome(env.enclosing):
            result = get(env.enclosing)[key]
        else:
            result = LUANIL

proc `[]=`*(env;key:string,value:sink LuaValue) = 
    env.locals[key] = value
