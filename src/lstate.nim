import std/[lexbase,tables,streams]
from token import Token
import llex,lparser,lobject

type
    LuaState* = object
        parser*: ParseState
        lexer*: LexState
        metatables*: Table[string,MetaTable]
        globals*: Table[string,LuaValue]

using
    L: var LuaState

func buf*(ls:var LexState): string = ls.buf
func bufpos*(ls:var LexState): int = ls.bufpos

proc newLuaState*(): LuaState = 
    result.metatables = initTable[string,MetaTable]()


proc loadString*(L;buff: string) =
    L.lexer = LexState()
    L.lexer.open(newStringStream(buff))

proc loadFile*(L;file:string) =
    L.lexer = LexState()
    open(L.lexer,newFileStream(file))

proc initLuaParser*(L;tokens:seq[Token]) = L.parser = initParser(tokens)

# proc setMetaTable*(L;key:string,v:sink MetaTable) = L.metatables[key] = v
# proc setMetaTable*(L): proc(key:string,v:sink MetaTable) =
#     result = proc(key:string,v:sink MetaTable) = setMetaTable(L,key,v)
# proc getMetaTable*(L;key:string): lent MetaTable = L.metatables[key]
# proc getMetaTable*(L): proc(key:string): lent MetaTable =
#     result = proc(key:string):lent Metatable = getMetaTable(L,key)


proc getGlobal*(L;key:string): lent LuaValue = L.globals[key]
proc setGlobal*(L;key:string,v:sink LuaValue) = L.globals[key] = v




