import std/[lexbase,streams]
from strutils import Whitespace,Digits,Letters
import types,llimits
from lua import ThreadStatus

const
    FIRST_RESERVED = 257
    luaX_tokens = ["and", "break", "do", "else", "elseif", "end", "false",
    "for", "function", "goto", "if", "in", "local", "nil", "not", "or",
    "repeat",
    "return", "then", "true", "until", "while",
    "..", "...", "==", ">=", "<=", "~=", "::", "<eof>",
    "<number>", "<name>", "<string>"]


type
    TokenKind = enum
        TK_AND = (FIRST_RESERVED,"and")
        TK_BREAK = "break"
        TK_DO = "do"
        TK_ELSE = "else"
        TK_ELSEIF = "elseif"
        TK_END = "end"
        TK_FALSE = "false"
        TK_FOR = "for"
        TK_FUNCTION = "function"
        TK_GOTO = "goto"
        TK_IF = "if"
        TK_IN = "in"
        TK_LOCAL = "local"
        TK_NIL = "nil"
        TK_NOT = "not"
        TK_OR = "or"
        TK_REPEAT = "repeat"
        TK_RETURN = "return"
        TK_THEN = "then"
        TK_TRUE = "true"
        TK_UNTIL = "until"
        TK_WHILE = "while"
        TK_CONCAT = ".."
        TK_DOTS = "..."
        TK_EQ = "="
        TK_GE = ">="
        TK_LE = "<="
        TK_NE = "~="
        TK_DBCOLON = "::"
        TK_EOS
        TK_NUMBER
        TK_NAME
        TK_STRING
        TK_LESS = "<"
        TK_GREATER = ">"
        TK_PLUS = "+"
        TK_MINUS = "-"
        TK_DIV = "/"
        TK_MULT = "*"
        TK_MOD = "%"
        TK_POW = "^"
        TK_EQEQ = "=="
        TK_COMMA = ","
        TK_DOT = "."
        TK_SEMCOL = ";"
        TK_COLON = ":"
        TK_LEFTPAREN = ")"
        TK_RIGHTPAREN = "("
        TK_LEFTBRACKET = "{"
        TK_RIGHTBRACKET = "}"
        TK_COMMENT
        TK_ERROR

let NUM_RESERVED = int(TK_WHILE) - (FIRST_RESERVED + 1)

type
    SemInfo = object
        r*: lua_Number
        ts*: TString
    Token = object
        token: TokenKind
        seminfo: SemInfo
    LexState = object of BaseLexer
        lastline: int
        t: Token
        lexeme: string
        lookahead: Token
        fs: FuncState
        L: lua_State
        dyd: Dyndata
        source: TString
        envn: TString
        decpoint: char
    SyntaxError = object of Exception

proc initWithString*(contents:string): LexState = 
    result = LexState()
    result.open(newStringStream(contents))

proc initWithFile*(fileName:string): LexState = 
    let contents = readFile(fileName)
    result = initWithString(contents)

proc syntax_error(msg:string,token:TokenKind) = 
    raise newException(SyntaxError,msg & " Token: " & $token)


template peek():char = ls.buf[ls.bufpos]
template peekNext():char = ls.buf[ls.bufpos+1]

proc isEOF(ls:LexState): bool = result = ls.bufpos >= len(ls.buf)

proc isNewline(ls: LexState): bool = result = peek() in {'\r','\n'}

proc handleNewline(ls:var LexState) = 
    let ch = peek()
    if isNewline(ls):
        inc(ls.bufpos)
        inc(ls.lineNumber)
    if isNewline(ls) and peek() != ch:
        inc(ls.bufpos)




proc next(ls: var LexState): char = 
    if isEOF(ls):
        return '\0'
    inc(ls.bufpos)
    handleNewline(ls)
    return peek()

proc advance(ls: var LexState) = 
    if isEOF(ls):
        return
    else:
        handleNewline(ls)
        inc(ls.bufpos)


proc match(ls:var LexState,ch:char): bool =
    result = false
    if peek() == ch:
        discard next(ls)
        result = true

proc saveChar(ls:var LexState) = add(ls.lexeme,peek())
proc saveAndNext(ls:var LexState) = 
    saveChar(ls)
    advance(ls)

proc resetLexeme(ls:var LexState) = ls.lexeme = ""

proc skipWhiteSpace(ls:var LexState) = 
    while peek() in Whitespace:
        discard next(ls)

proc skipComment(ls:var LexState) = 
    while not isNewline(ls):
        discard next(ls)

proc skipLongComment(ls:var LexState):bool = 
    result = false
    while peek() != ']':
        discard next(ls)
    if match(ls,']'):
        discard next(ls)
        result = true

proc newString(ls:var LexState) = 
    let str = ls.lexeme
    resetLexeme(ls)

proc readLongString(ls:var LexState) = 
    saveAndNext(ls)
    while peek() != ']':
        if isEOF(ls):
            syntax_error("Unfinished long string",TK_STRING)
        saveAndNext(ls)
    advance(ls)
    if peek() != ']':
        syntax_error("Invalid long string delimiter",TK_STRING)
    advance(ls)

    newString(ls)

proc readString(ls:var LexState) = 
    saveAndNext(ls)
    while peek() != '"' and peek() != '\'':
        if isNewline(ls):
            syntax_error("unfinished string",TK_EOS)
        elif isEOF(ls):
            syntax_error("unfinished string",TK_STRING)
        saveAndNext(ls)
        # escape sequence handling later

proc readNumeral(ls:var LexState) = 
    while peek() in Digits + {'.'}:
        discard

#ternary token match
template TTM(ch:char,tCond:TokenKind,fCond:TokenKind) =
    if match(ls,ch):
        yield(tCond)
    else:
        yield(fCond)

iterator getToken(ls:var LexState): TokenKind = 
    skipWhiteSpace(ls)
    while not isEOF(ls):
        let ch = next(ls)
        case ch:
            of '-':
                if peek() != '-': 
                    yield(TK_MINUS)
                elif match(ls,'['):
                    discard skipLongComment(ls)
                    yield(TK_COMMENT)
                else:
                    skipComment(ls)
                    yield(TK_COMMENT)
            of '[': 
                advance(ls)
                if peek() != '[':
                    syntax_error("Invalid long string delimiter",TK_STRING)
                    yield(TK_ERROR)
                advance(ls)
                readLongString(ls)
                yield(TK_STRING)
                
            of '=': TTM('=',TK_EQEQ,TK_EQ)
            of '<': TTM('=',TK_LE,TK_LESS)
            of '>': TTM('=',TK_GE,TK_GREATER)
            of '~': TTM('=',TK_NE,TK_NOT)
            of ':': TTM(':',TK_DBCOLON,TK_COLON)
            of '"','\'': 
                readString(ls)
                yield(TK_STRING)
            of Digits: 
                readNumeral(ls)
                yield(TK_NUMBER)
            of '.': 
                saveAndNext(ls)
                if match(ls,'.'):
                    if peekNext() == '.':
                        yield(TK_DOTS)
                    else:
                        yield(TK_CONCAT)
            of Letters: 
                yield(TK_NAME)
            else: yield(TK_ERROR)

proc llex(ls: var LexState) = 
    let ch = next(ls)
    
        



proc luaX_setinput*(L: lua_State, ls: LexState, z: ZIO, source: TString,
        firstchar: int) = discard
proc luaX_newstring*(ls: LexState, str: string, l: int): TString = discard
proc luaX_next*(ls: LexState) = discard
proc luaX_lookahead*(ls: LexState): int = discard
proc luaX_syntaxerror*(ls: LexState, s: string) = discard # what is __attribute__???
proc luaX_token2str*(ls: LexState, token: int): string = discard



