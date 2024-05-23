import std/[lexbase, strformat]
from streams import newStringStream
from parseutils import skipUntil,parseWhile,parseUntil
from strutils import Digits, IdentChars, Letters
import types, llimits

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
    Token* = object
        kind*: TokenKind
        lexeme*: string
        linenumber*: int
    LexState* = object of BaseLexer
        lastline: int
        curtoken: Token
        lexeme: string
        lookahead: Token
        fs: FuncState
        L: lua_State
        dyd: Dyndata
        source: TString
        envn: TString
        decpoint: char
    SyntaxError = object of CatchableError

const NewLineChars = {'\r', '\n', '\c'}
const WhiteSpaceChars = {' ', '\t', '\f', '\v'}
const NotationChars = {'e', 'x', '.'}

proc getCurToken*(ls:LexState): Token = result = ls.curtoken

proc getLookahead*(ls:LexState):Token = result = ls.lookahead

proc syntax_error(msg: string, token: TokenKind, lineNum: int) =
    raise newException(SyntaxError, fmt"{msg} | Token: {token} | Line: {lineNum}")


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

func createToken(ls: LexState, kind: TokenKind,
        lexeme: string): Token = result = Token(kind: kind, lexeme: lexeme,
        linenumber: ls.lineNumber)
func createStringToken(ls: LexState): Token = result = createToken(ls,
        TK_STRING, ls.lexeme)
func createReservedToken(ls: LexState): Token = result = createToken(ls,
        getReserved(ls), ls.lexeme)
func createNameToken(ls: LexState): Token = result = createToken(ls, TK_NAME, ls.lexeme)
func createNumberToken(ls: LexState): Token = result = createToken(ls,
        TK_NUMBER, ls.lexeme)

func createCommentToken(ls: LexState): Token = result = createToken(ls,
        TK_COMMENT, "comment")

proc initWithString*(contents: string): LexState =
    result = LexState()
    result.lineNumber = 1
    result.open(newStringStream(contents))

proc initWithFile*(fileName: string): LexState =
    let contents = readFile(fileName)
    result = initWithString(contents)

template peek(): char = ls.buf[ls.bufpos]
template peekNext(): char = ls.buf[ls.bufpos+1]

proc getLineNumber*(ls: LexState): int = result = ls.lineNumber

proc isEOF(ls: LexState): bool = result = peek() == EndOfFile

proc advance(ls: var LexState) =
    if (isEof(ls)): return
    inc(ls.bufpos)

proc advance(ls: var LexState, num: int) =
    if (isEof(ls)): return
    inc(ls.bufpos, num)

proc handleNewline(ls: var LexState) =
    case peek():
        of '\c': ls.bufpos = ls.handleCR(ls.bufpos)
        of '\n': ls.bufpos = ls.handleLF(ls.bufpos)
        else: discard

proc match(ls: var LexState, ch: char): bool =
    result = false
    if peek() == ch:
        advance(ls)
        result = true

func resetLexeme(ls: var LexState) = ls.lexeme = ""

proc skipByChar(ls: var LexState, ch: char) =
    let skipped = skipUntil(ls.buf, ch, ls.bufpos)
    advance(ls, skipped)

proc skipByChars(ls: var LexState, chars: set[char]) =
    let skipped = skipUntil(ls.buf, chars, ls.bufpos)
    advance(ls, skipped)

proc saveUntil(ls: var LexState, ch: char): int = result = parseUntil(ls.buf,
        ls.lexeme, ch, ls.bufpos)
proc saveUntil(ls: var LexState, chars: set[char]): int = result = parseUntil(
        ls.buf, ls.lexeme, chars, ls.bufpos)

proc saveWhile(ls: var LexState, chars: set[char]): int = parseWhile(ls.buf,
        ls.lexeme, chars, ls.bufpos)

proc skipComment(ls: var LexState) = skipByChars(ls, NewLineChars)

proc skipLongComment(ls: var LexState) =
    skipByChar(ls, ']')
    advance(ls)
    if not match(ls, ']'):
        syntax_error("Unterminated long comment", TK_STRING, ls.lineNumber)

proc readLongString(ls: var LexState) =
    # skip [[
    advance(ls)
    advance(ls)

    let saved = saveUntil(ls, ']')
    advance(ls, saved)
    if saved == 0 or isEOF(ls):
        syntax_error("Unfinished long string", TK_STRING, ls.lineNumber)
    advance(ls)
    if peek() != ']':
        syntax_error("Long string not terminated by ]]", TK_STRING, ls.lineNumber)
    advance(ls)

proc isReserved(ls: var LexState): bool =
    result = false
    if ls.lexeme in luaX_tokens:
        result = true


proc readString(ls: var LexState) =
    advance(ls)
    let saved = saveUntil(ls, {'"', '\''})
    advance(ls, saved)
    if saved == 0 or isEOF(ls):
        syntax_error("Unfinished string", TK_STRING, ls.lineNumber)
        # escape sequence handling later
    advance(ls)


proc readNumeral(ls: var LexState) =
    # how to handle
    # countries that don't use '.'
    # potentially get entire lexeme before doing checks on whether ',' or '.'
    var str: string
    let saved = parseWhile(ls.buf, str, Digits, ls.bufpos)
    add(ls.lexeme, str)
    advance(ls, saved)
    if peek() in NotationChars and peekNext() in Digits:
        add(ls.lexeme, peek())
        var afterStr: string
        let savedAfter = parseWhile(ls.buf, afterStr, Digits, ls.bufpos)
        advance(ls, savedAfter)
        add(ls.lexeme, afterStr)
    else:
        case peek():
            of '.':
                syntax_error("Invalid decimal placement for decimal number",
                        TK_NUMBER, ls.lineNumber)
            of 'x':
                syntax_error("Invalid binary number", TK_NUMBER, ls.lineNumber)
            of 'e':
                syntax_error("Invalid decimal exponent", TK_NUMBER, ls.lineNumber)
            else: discard

proc readVar(ls: var LexState) =
    let saved = saveWhile(ls, IdentChars)
    advance(ls, saved)

#ternary token match
template TTM(ch: char, tCond: TokenKind, fCond: TokenKind) =
    advance(ls)
    if match(ls, ch):
        result = createToken(ls, tCond, $tCond)
        continue
    else:
        result = createToken(ls, fCond, $fCond)
        continue

proc getToken*(ls: var LexState): Token =
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
                        skipLongComment(ls)
                        result = createCommentToken(ls)
                    else:
                        skipComment(ls)
                        result = createCommentToken(ls)

                else:
                    result = createToken(ls, TK_MINUS, $TK_MINUS)
                continue
            of '[':
                if peekNext() == '[':
                    readLongString(ls)
                    result = createStringToken(ls)
                    resetLexeme(ls)
                    continue
                else:
                    result = createToken(ls, TK_LEFTSTAPLE, $TK_LEFTSTAPLE)
            of ']':
                result = createToken(ls, TK_RIGHTSTAPLE, $TK_RIGHTSTAPLE)
            of '=': TTM('=', TK_EQEQ, TK_EQ)
            of '<': TTM('=', TK_LE, TK_LESS)
            of '>': TTM('=', TK_GE, TK_GREATER)
            of '~': TTM('=', TK_NE, TK_NOT)
            of ':': TTM(':', TK_DBCOLON, TK_COLON)
            of '"', '\'':
                if peek() == '"' and peekNext() == '"':
                    advance(ls)
                    result = createToken(ls, TK_STRING, "\"\"")
                elif peek() == '\'' and peekNext() == '\'':
                    advance(ls)
                    result = createToken(ls, TK_STRING, "''")
                elif peekNext() in Letters:
                    readString(ls)
                    result = createStringToken(ls)
                    resetLexeme(ls)
                    continue
                else:
                    syntax_error("Invalid String", TK_STRING, ls.lineNumber)
            of Digits:
                readNumeral(ls)
                result = createNumberToken(ls)
                resetLexeme(ls)
                continue
            of '.':
                advance(ls)
                if match(ls, '.'):
                    if match(ls, '.'):
                        result = createToken(ls, TK_DOTS, $TK_DOTS)
                        continue
                    else:
                        result = createToken(ls, TK_CONCAT, $TK_CONCAT)
                        continue
                else:
                    result = createToken(ls, TK_DOT, $TK_DOT)
            of '+': result = createToken(ls, TK_PLUS, $TK_PLUS)
            of '*': result = createToken(ls, TK_STAR, $TK_STAR)
            of '/': result = createToken(ls, TK_SLASH, $TK_SLASH)
            of '(': result = createToken(ls, TK_LEFTPAREN, $TK_LEFTPAREN)
            of ')': result = createToken(ls, TK_RIGHTPAREN, $TK_RIGHTPAREN)
            of '{': result = createToken(ls, TK_LEFTBRACKET, $TK_LEFTBRACKET)
            of '}': result = createToken(ls, TK_RIGHTBRACKET, $TK_RIGHTBRACKET)
            of ';': result = createToken(ls, TK_SEMCOL, $TK_SEMCOL)
            of '%': result = createToken(ls, TK_MOD, $TK_MOD)
            of '#': result = createToken(ls, TK_HASH, $TK_HASH)
            of ',': result = createToken(ls, TK_COMMA, $TK_COMMA)
            of '^': result = createToken(ls, TK_CARROT, $TK_CARROT)
            else:
                if peek() in IdentChars:
                    readVar(ls)
                    if isReserved(ls):
                        result = createReservedToken(ls)
                    else:
                        result = createNameToken(ls)
                    resetLexeme(ls)
                    continue
                else:
                    result = createToken(ls, TK_ERROR, "error")
        advance(ls)


proc lua_next*(ls:var LexState) = 
    ls.lastline = ls.lineNumber
    ls.curtoken = getToken(ls)



# proc luaX_setinput*(L: lua_State, ls: LexState, z: ZIO, source: TString,
#         firstchar: int) = discard
# proc luaX_newstring*(ls: LexState, str: string, l: int): TString = discard
# proc luaX_next*(ls: LexState) = discard
# proc luaX_lookahead*(ls: LexState): int = discard
# proc luaX_syntaxerror*(ls: LexState, s: string) = discard # what is __attribute__???
# proc luaX_token2str*(ls: LexState, token: int): string = discard



