import std/[lexbase, streams]
from strutils import Digits, Letters, IdentChars
import types, llimits
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
    TokenKind* = enum
        TK_AND = "and"
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
        TK_SLASH = "/"
        TK_STAR = "*"
        TK_MOD = "%"
        TK_CARROT = "^"
        TK_EQEQ = "=="
        TK_COMMA = ","
        TK_DOT = "."
        TK_SEMCOL = ";"
        TK_COLON = ":"
        TK_LEFTPAREN = "("
        TK_RIGHTPAREN = ")"
        TK_LEFTBRACKET = "{"
        TK_RIGHTBRACKET = "}"
        TK_LEFTSTAPLE = "["
        TK_RIGHTSTAPLE = "]"
        TK_HASH = "#"
        TK_COMMENT
        TK_ERROR

# let NUM_RESERVED = int(TK_WHILE) - (FIRST_RESERVED + 1)

type
    SemInfo = object
        r*: lua_Number
        ts*: TString
    Token = object
        kind*: TokenKind
        lexeme*: string
        linenumber*: int
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
    SyntaxError = object of CatchableError

const NewLineChars = {'\r','\n','\l'}
const WhiteSpaceChars = {' ','\t','\f','\v'}
const NotationChars = {'e','x','.'}


proc initWithString*(contents: string): LexState =
    result = LexState()
    result.open(newStringStream(contents))

proc initWithFile*(fileName: string): LexState =
    let contents = readFile(fileName)
    result = initWithString(contents)

proc syntax_error(msg: string, token: TokenKind) =
    raise newException(SyntaxError, msg & " Token: " & $token)


template peek(): char = ls.buf[ls.bufpos]
template peekNext(): char = ls.buf[ls.bufpos+1]

proc isEOF(ls: LexState): bool = result = peek() == EndOfFile

proc isNewline(ls: LexState): bool = result = peek() in NewLineChars

proc advance(ls: var LexState) =
    if (isEof(ls)): return
    inc(ls.bufpos)

proc handleNewline(ls: var LexState) =
    let ch = peek()
    assert(isNewline(ls))
    advance(ls)
    inc(ls.lineNumber)
    if isNewline(ls) and peek() != ch:
        advance(ls)
            


proc match(ls: var LexState, ch: char): bool =
    result = false
    if peek() == ch:
        advance(ls)
        result = true

func saveChar(ls: var LexState) = add(ls.lexeme, peek())

proc saveAndNext(ls: var LexState) =
    saveChar(ls)
    advance(ls)

func resetLexeme(ls: var LexState) = ls.lexeme = ""

proc skipComment(ls: var LexState) =
    while not isNewline(ls):
        advance(ls)

proc skipLongComment(ls: var LexState): bool =
    result = false
    while peek() != ']':
        advance(ls)
    if match(ls, ']'):
        advance(ls)
        result = true

proc newString(ls: var LexState) =
    let str = ls.lexeme
    resetLexeme(ls)

proc readLongString(ls: var LexState) =
    # skip [[
    advance(ls)
    advance(ls)
    saveAndNext(ls)
    while peek() != ']':
        if isEOF(ls):
            syntax_error("Unfinished long string", TK_STRING)
        saveAndNext(ls)
    advance(ls)
    if peek() != ']':
        syntax_error("Invalid long string delimiter", TK_STRING)
    advance(ls)

proc isReserved(ls: var LexState): bool =
    result = false
    if ls.lexeme in luaX_tokens:
        result = true


proc getReserved(ls: LexState): TokenKind =
    case ls.lexeme:
        of "and":
            result = TK_AND
        of "break":
            result = TK_BREAK
        of "do":
            result = TK_DO
        of "else":
            result = TK_ELSE
        of "elseif": result = TK_ELSEIF
        of "end": result = TK_END
        of "false": result = TK_FALSE
        of "for": result = TK_FOR
        of "function": result = TK_FUNCTION
        of "goto": result = TK_GOTO
        of "if": result = TK_IF
        of "in": result = TK_IN
        of "local": result = TK_LOCAL
        of "nil": result = TK_NIL
        of "not": result = TK_NOT
        of "or": result = TK_OR
        of "repeat": result = TK_REPEAT
        of "return": result = TK_RETURN
        of "then": result = TK_THEN
        of "true": result = TK_TRUE
        of "until": result = TK_UNTIL
        of "while": result = TK_WHILE
        else:
            result = TK_NAME

proc readString(ls: var LexState) =
    advance(ls)
    while peek() != '"' and peek() != '\'':
        if isNewline(ls):
            syntax_error("unfinished string", TK_EOS)
        elif isEOF(ls):
            syntax_error("unfinished string", TK_STRING)
        saveAndNext(ls)
    advance(ls)
        # escape sequence handling later


proc readNumeral(ls: var LexState) =
    # how to handle
    # countries that don't use '.'
    # potentially get entire lexeme before doing checks on whether ',' or '.'
    while peek() in Digits + {'.','x','e'}:
        if unlikely(peek() in {'.','x','e'} and not(peekNext() in Digits)):
            case peek():
                of '.':
                    syntax_error("Invalid decimal placement for decimal number", TK_NUMBER)
                of 'x':
                    syntax_error("Invalid binary number", TK_NUMBER)
                of 'e':
                    syntax_error("Invalid decimal exponent", TK_NUMBER)
                else: discard
        saveAndNext(ls)

proc readVar(ls: var LexState) =
    while peek() in IdentChars:
        saveAndNext(ls)

func createToken(ls:LexState,kind:TokenKind,lexeme:string): Token = result = Token(kind:kind,lexeme:lexeme,linenumber:ls.lineNumber)
func createStringToken(ls:LexState): Token = result = createToken(ls,TK_STRING,ls.lexeme)
func createReservedToken(ls:LexState): Token = result = createToken(ls,getReserved(ls),ls.lexeme)
func createNameToken(ls:LexState): Token = result = createToken(ls,TK_NAME,ls.lexeme)
func createNumberToken(ls:LexState): Token = result = createToken(ls,TK_NUMBER,ls.lexeme)

func createCommentToken(ls:LexState): Token = result = createToken(ls,TK_COMMENT,"comment")

#ternary token match
template TTM(ch: char, tCond: TokenKind, fCond: TokenKind) =
    advance(ls)
    if match(ls, ch):
        yield(createToken(ls,tCond,$tCond))
    else:
        yield(createToken(ls,fCond,$fCond))
        continue

iterator getToken*(ls: var LexState): Token =
    while not isEOF(ls):
        case peek():
            of WhitespaceChars: discard
            of NewLineChars:
                handleNewline(ls)
                continue
            of '-':
                advance(ls)
                if match(ls, '-'):
                    if peek() == '[' and peekNext() == '[':
                        discard skipLongComment(ls)
                        yield(createCommentToken(ls))
                    else:
                        skipComment(ls)
                        yield(createCommentToken(ls))

                else:
                    yield(createToken(ls,TK_MINUS,$TK_MINUS))
            of '[':
                if peekNext() == '[':
                    readLongString(ls)
                    yield(createStringToken(ls))
                    resetLexeme(ls)
                else:
                    yield(createToken(ls,TK_LEFTSTAPLE,$TK_LEFTSTAPLE))
            of ']':
                yield(createToken(ls,TK_RIGHTSTAPLE,$TK_RIGHTSTAPLE))
            of '=': TTM('=', TK_EQEQ, TK_EQ)
            of '<': TTM('=', TK_LE, TK_LESS)
            of '>': TTM('=', TK_GE, TK_GREATER)
            of '~': TTM('=', TK_NE, TK_NOT)
            of ':': TTM(':', TK_DBCOLON, TK_COLON)
            of '"', '\'':
                readString(ls)
                yield(createStringToken(ls))
                resetLexeme(ls)
                continue

            of Digits:
                readNumeral(ls)
                yield(createNumberToken(ls))
                resetLexeme(ls)
                continue
            of '.':
                advance(ls)
                if match(ls, '.'):
                    if peekNext() == '.':
                         yield(createToken(ls,TK_DOTS,$TK_DOTS))
                    else:
                       yield(createToken(ls,TK_CONCAT,$TK_CONCAT))
                else:
                     yield(createToken(ls,TK_DOT,$TK_DOT))
                continue
            of '+':  yield(createToken(ls,TK_PLUS,$TK_PLUS))
            of '*':  yield(createToken(ls,TK_STAR,$TK_STAR))
            of '/':  yield(createToken(ls,TK_SLASH,$TK_SLASH))
            of '(': yield(createToken(ls,TK_LEFTPAREN,$TK_LEFTPAREN))
            of ')': yield(createToken(ls,TK_RIGHTPAREN,$TK_RIGHTPAREN))
            of '{': yield(createToken(ls,TK_LEFTBRACKET,$TK_LEFTBRACKET))
            of '}': yield(createToken(ls,TK_RIGHTBRACKET,$TK_RIGHTBRACKET))
            of ';': yield(createToken(ls,TK_SEMCOL,$TK_SEMCOL))
            of '%': yield(createToken(ls,TK_MOD,$TK_MOD))
            of '#': yield(createToken(ls,TK_HASH,$TK_HASH))
            of ',': yield(createToken(ls,TK_COMMA,$TK_COMMA))
            of '^': yield(createToken(ls,TK_CARROT,$TK_CARROT))
            else:
                if peek() in IdentChars:
                    readVar(ls)
                    if isReserved(ls):
                        yield(createReservedToken(ls))
                    else:
                        yield(createNameToken(ls))
                    resetLexeme(ls)
                    continue
                else:
                    yield(createToken(ls,TK_ERROR,"error"))
        advance(ls)






# proc luaX_setinput*(L: lua_State, ls: LexState, z: ZIO, source: TString,
#         firstchar: int) = discard
# proc luaX_newstring*(ls: LexState, str: string, l: int): TString = discard
# proc luaX_next*(ls: LexState) = discard
# proc luaX_lookahead*(ls: LexState): int = discard
# proc luaX_syntaxerror*(ls: LexState, s: string) = discard # what is __attribute__???
# proc luaX_token2str*(ls: LexState, token: int): string = discard



