import std/[lexbase]
from token import Token

type
    LexState* = object of BaseLexer
        lexeme*: string = ""
        currentToken*: Token
        tokens*: seq[Token] = @[]
    ParseState* = object
        currentToken*: Token
        previousToken*: Token
        cursor*: int = 0
        tokens*: seq[Token]
    LuaState* = object
        parser*: ParseState
        lexer*: LexState
        chunk: int

using
    L: var LuaState

# proc `parser=`*(L;p:ParseState) {.inline.} = L.parser = p
# func parser*(L): ParseState = L.parser

# proc `lexer=`*(L;ls:var LexState) {.inline.} = L.lexer = ls
# func lexer*(L): LexState = L.lexer
func buf*(ls:var LexState): string = ls.buf
func bufpos*(ls:var LexState): int = ls.bufpos


