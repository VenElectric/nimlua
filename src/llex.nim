import std/[lexbase, strformat, parseutils, strscans]
from streams import newStringStream
from strutils import Digits, IdentChars, Letters


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
        TK_EOF = "<EOF>"
        TK_NUMBER = "{NUMBER}"
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
        TK_ERROR

# let NUM_RESERVED = int(TK_WHILE) - (FIRST_RESERVED + 1)

type
    Token* = object
        kind: TokenKind
        lexeme: string
        linenumber: int
    LexState* = object of BaseLexer
        lexeme: string
        start: int
        currentToken: Token
    SyntaxError = object of CatchableError

using
    ls: var LexState
    l: LexState

# const NewLineChars = {'\r', '\n', '\c'}
# const WhiteSpaceChars = {' ', '\t', '\f', '\v'}
# const NotationChars = {'e', 'x', '.'}


proc initWithString*(contents: string): LexState =
    result = LexState()
    result.lineNumber = 1
    result.open(newStringStream(contents))

proc initWithFile*(fileName: string): LexState =
    let contents = readFile(fileName)
    result = initWithString(contents)

func currentToken*(ls): Token = ls.currentToken

proc syntaxError(lineNum: int, msg: string) =
    raise newException(SyntaxError, fmt"{msg} | Line: {lineNum}")


proc getReserved(lexeme: string): TokenKind =
    case lexeme:
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

func createToken(linenumber: int, kind: TokenKind, lexeme: string): Token =
    result = Token(kind: kind, lexeme: lexeme, linenumber: linenumber)

func createEOFToken(linenumber: int): Token = result = createToken(linenumber,
        TK_EOF, "eof")

func createErrorToken(linenumber: int, msg: string): Token = createToken(
        linenumber, TK_ERROR, msg)

func isEOF(l): bool = l.buf[l.bufpos] == EndOfFile

func peek(l; pos: int = 0): char =
    if isEOF(l):
        return '\0'
    return l.buf[l.bufpos + pos]

func lineNumber*(l): int = l.lineNumber


proc handleNewline(ls) =
    case peek(ls):
        of '\c': ls.bufpos = ls.handleCR(ls.bufpos)
        of '\n': ls.bufpos = ls.handleLF(ls.bufpos)
        else: discard

proc skip(ls;steps: int = 1) = inc(ls.bufpos,steps)

proc check(ls; lexeme: var string, ch: char): int =
    result = 0

    if ch == peek(ls):
        lexeme.add(ch)
        inc(result)

proc check(ls;lexeme: var string,chars: set[char]): int =
    result = 0

    if peek(ls) in chars:
        lexeme.add(ch)
        inc(result)

proc skipComment(ls): bool = scanp(ls.buf, ls.bufpos, "--", +(~'\L'),'\L')


proc skipLongComment(ls):bool = scanp(ls.buf, ls.bufpos, +(~{'-', '\0'}, '\L' -> handleNewline(ls)), "--]]")

proc readLongString(ls): bool = scanp(ls.buf, ls.bufpos, "[[", +(~{']', '\0'} -> lexeme.add($_), '\L' -> handleNewline(ls)), "]]")


proc readString(ls): bool = scanp(ls.buf, ls.bufpos, +(~{'\'', '"', '\L', '\0'} -> lexeme.add($_)), `quoteChar`)

# float 5.0
# exponent 5e+20
# 4     0.4     4.57e-3     0.3e12     5e+20
    # how to handle
    # countries that don't use '.'
    # potentially get entire lexeme before doing checks on whether ',' or '.


proc readNumeral(ls): bool = 
    discard scanp(ls.buf,ls.bufpos,+(`Digits`,~'\L') -> ls.lexeme.add($_))
    discard scanp(ls.buf,ls.bufpos,+(`Digits`,~'\L') -> ls.lexeme.add($_),check(ls,ls.lexeme,{'.',','}),+(`Digits`,~'\L') -> ls.lexeme.add($_))
    discard scanp(ls.buf,ls.bufpos,+(`Digits`,~'\L') -> ls.lexeme.add($_),check(ls,ls.lexeme,'e'),check(ls,ls.lexeme,{'.',','}),+(`Digits`,~'\L') -> ls.lexeme.add($_))
    scanp(ls.buf, ls.bufpos, +`Digits` -> lexeme.add($_), check(ls, lexeme,
            '.'), (check(ls, lexeme, 'e'), (check(ls, lexeme, '+'), check(ls,
            lexeme, '-'))), +`Digits` -> lexeme.add($_))

proc readVar(ls): bool = scanp(ls.buf, ls.bufpos, parseIdent(ls.buf, lexeme, ls.bufpos))


proc get_char_literal_token(ch: char): TokenKind =

    case ch:
        of ',': result = TK_COMMA
        of '(': result = TK_LEFTPAREN
        of ')': result = TK_RIGHTPAREN
        of ']': result = TK_LEFTSTAPLE
        of '{': result = TK_LEFTBRACKET
        of '}': result = TK_RIGHTBRACKET
        of ';': result = TK_SEMCOL
        of '#': result = TK_HASH
        of '+': result = TK_PLUS
        of '^': result = TK_CARROT
        of '%': result = TK_MOD
        of '*': result = TK_STAR
        of '/': result = TK_SLASH
        of ':': result = TK_COLON
        of '-': result = TK_MINUS
        of '=': result = TK_EQ
        of '>': result = TK_GE
        of '<': result = TK_LE
        of '[': result = TK_RIGHTSTAPLE
        else: result = TK_ERROR

proc parseLiteral(ls): Token =
    var kind = TK_ERROR
    case peek(ls):
        of ',': kind = TK_COMMA
        of '(': kind = TK_LEFTPAREN
        of ')': kind = TK_RIGHTPAREN
        of ']': kind = TK_LEFTSTAPLE
        of '{': kind = TK_LEFTBRACKET
        of '}': kind = TK_RIGHTBRACKET
        of ';': kind = TK_SEMCOL
        of '#': kind = TK_HASH
        of '+': kind = TK_PLUS
        of '^': kind = TK_CARROT
        of '%': kind = TK_MOD
        of '*': kind = TK_STAR
        of '/': kind = TK_SLASH
        of ':': 
            if peek(ls,1) == ':':
                skip(ls)
                kind = TK_DBCOLON
            else:
                kind = TK_COLON
        of '-': kind = TK_MINUS
        of '=': kind = TK_EQ
        of '>': kind = TK_GE
        of '<': kind = TK_LE
        of '[': kind = TK_RIGHTSTAPLE
        else: kind = TK_ERROR

    if kind == TK_ERROR:
        syntaxError(ls.lineNumber,fmt"Invalid character {$peek(ls)}")

    return createToken(ls.lineNumber,kind,$kind)



const LITERALS = {',', '(', ')', ']', '{', '}', '+', '/', '*', ';', '#', '^',
        '%', '.', '=', '>', '<', '-', '[', ':'}


proc getToken(ls): Token =

    var tk: TokenKind = TK_ERROR

    if scanp(ls.buf,ls.bufpos,'\L' -> handleNewline(ls)):
        return getToken(ls)
    if scanp(ls.buf,ls.bufpos,'\0'):
        return createEOFToken(ls.linenumber)
    elif scanp(ls.buf, ls.bufpos, "..." -> (tk = TK_DOTS),
            ".." -> (tk = TK_CONCAT), '.' -> (tk = TK_DOT),
            ">=" -> (tk = TK_GE), "<=" -> (tk = TK_LE),
            "==" -> (tk = TK_EQEQ), "::" -> (tk = TK_DBCOLON)):
        return createToken(ls.linenumber,tk,$tk)
    elif scanp(ls.buf,ls.bufpos,"[["):
        return readLongString(ls)
    elif scanp(ls.buf, ls.bufpos, "--[[" -> skipLongComment(ls), "--" -> skipComment(ls)):
        return getToken(ls)
    elif scanp(ls.buf, ls.bufpos, `LITERALS` -> (tk = get_char_literal_token($_))):
        return createToken(ls.lineNumber,tk,$tk)
    elif scanp(ls.buf,ls.bufpos,{'\'','"'}):
        return readString(ls)
    elif peek(ls) in Digits:
        return readNumeral(ls)
    elif peek(ls) in IdentChars:
        return readVar(ls)
    else:
        return createErrorToken(ls.linenumber,"Unhandled Lex Error")




