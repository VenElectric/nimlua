import std/[lexbase,tables,streams]
from token import Token
from lobject import MetaTable
import llex,lparser

type
    LuaState* = object
        parser*: ParseState
        lexer*: LexState
        metatables*: Table[string,MetaTable]

using
    L: var LuaState

func buf*(ls:var LexState): string = ls.buf
func bufpos*(ls:var LexState): int = ls.bufpos

proc newLuaState*(): LuaState = 
    result.metatables = initTable[string,MetaTable]()


proc initLexer*(L;buff: string) =
    L.lexer = LexState()
    L.lexer.open(newStringStream(buff))

proc initParser*(L;tokens:seq[Token]) =
    L.parser = ParseState(tokens: tokens)




