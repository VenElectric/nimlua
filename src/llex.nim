import std/[lexbase, strformat, parseutils, strscans]
from streams import newStringStream, newFileStream
from strutils import Digits, IdentChars, Letters, Whitespace
import token


# let NUM_RESERVED = int(TK_WHILE) - (FIRST_RESERVED + 1)

type
    SyntaxError = object of CatchableError

type
    LexState* = object of BaseLexer
        lexeme*: string = ""
        currentToken*: Token
        tokens*: seq[Token] = @[]

using
    ls: var LexState


# const NewLineChars = {'\r', '\n', '\c'}
# const WhiteSpaceChars = {' ', '\t', '\f', '\v'}
# const NotationChars = {'e', 'x', '.'}


func currentToken*(ls): Token = ls.currentToken

proc syntaxError(lineNum: int, msg: string) =
    raise newException(SyntaxError, fmt"{msg} | Line: {lineNum}")


proc getReserved(ls): TokenKind =
    echo "lexeme: ",ls.lexeme
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

func isEOF(ls): bool = ls.buf[ls.bufpos] == EndOfFile

func peek(ls; pos: int = 0): char =
    if isEOF(ls):
        return '\0'
    return ls.buf[ls.bufpos + pos]

func lineNumber*(ls): int = ls.lineNumber

proc skip(ls; steps: int = 1) = inc(ls.bufpos, steps)

proc advance(ls): char = 
    skip(ls)
    result = peek(ls,-1)

proc match(ls;ch:char): bool = 
    if peek(ls) == ch:
        skip(ls)
        return true
    else:
        return false


proc setLexeme*(ls; sPos, ePos: int) = ls.lexeme = substr(ls.buf, sPos, ePos)

proc handleNewline(ls) =
    case peek(ls):
        of '\c': ls.bufpos = ls.handleCR(ls.bufpos)
        of '\n': ls.bufpos = ls.handleLF(ls.bufpos)
        else: discard



proc resetLexeme(ls) = ls.lexeme = ""

proc skipComment(ls) =
    let skipped = skipUntil(ls.buf, '\L', ls.bufpos)
    if skipped > 0:
        skip(ls, skipped)
        handleNewline(ls)
    else:
        syntaxError(ls.linenumber, "Invalid Comment")


proc skipLongComment(ls) =
    skip(ls, 4) # skip --[[
    var sliceStart = ls.bufpos
    var sliceEnd = sliceStart + 4
    while not isEOF(ls):
        let slice = substr(ls.buf, sliceStart, sliceEnd)
        if slice == "--]]":
            skip(ls, 4)
            break
        if peek(ls) in lexbase.Newlines:
            handleNewline(ls)
        else:
            skip(ls)

proc parseLongString(ls) =
    skip(ls, 2) # skip [[
    let start = ls.bufpos
    var sliceStart = ls.bufpos
    var sliceEnd = sliceStart + 2
    while not isEOF(ls):
        let slice = substr(ls.buf, sliceStart, sliceEnd)
        if slice == "]]":
            skip(ls, 2)
            break
        if peek(ls) in lexbase.Newlines:
            handleNewline(ls)
        else:
            skip(ls)

    if isEOF(ls):
        syntaxError(ls.linenumber, "Unterminated long comment")
    setLexeme(ls, start, ls.bufpos)


proc parseString(ls) =
    let quoteChar = peek(ls)
    skip(ls) # skip ' or "
    let skipped = parseUntil(ls.buf, ls.lexeme, {quoteChar} + lexbase.Newlines, ls.bufpos)
    if peek(ls) in lexbase.Newlines:
        syntaxError(ls.linenumber, "Unterminated string")

    if peek(ls) != quoteChar:
        syntaxError(ls.linenumber, fmt"Non matching string quotation. Expected: {quoteChar} but got: {peek(ls)}")

    if skipped > 0:
        setLexeme(ls, ls.bufpos-skipped, ls.bufpos)
    else:
        syntaxError(ls.linenumber, "Unable to parse string")

# float 5.0
# exponent 5e+20
# 4     0.4     4.57e-3     0.3e12     5e+20
    # how to handle
    # countries that don't use '.'
    # potentially get entire lexeme before doing checks on whether ',' or '.



proc parseNumeral(ls) =
    var skipped = parseWhile(ls.buf, ls.lexeme, Digits + {'-', '+', '.', 'e'}, ls.bufpos)
    if skipped > 0:
        skip(ls, skipped)
    else:
        syntaxError(ls.linenumber, "Unable to parse number")

proc parseVar(ls) =
    let skipped = parseIdent(ls.buf, ls.lexeme, ls.bufpos)
    if skipped > 0:
        skip(ls, skipped)
    else:
        syntaxError(ls.linenumber, "Unable to parse variable")


proc parseLiteral(ls): Token =
    var kind = TK_ERROR

    case advance(ls):
        of ',': kind = TK_COMMA
        of '~':
            skip(ls)
            if match(ls,'='):
                kind = TK_NE
            else:
                kind = TK_TILDE
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
            skip(ls)
            if match(ls,':'):
                kind = TK_DBCOLON
            else:
                kind = TK_COLON
        of '-': kind = TK_MINUS
        of '=':
            skip(ls)
            if match(ls,'='):
                kind = TK_EQEQ
            else:
                kind = TK_EQ
        of '>':
            skip(ls)
            if match(ls,'='):
                kind = TK_GE
            else:
                kind = TK_GREATER
        of '<':
            skip(ls)
            if match(ls,'='):
                kind = TK_LE
            else:
                kind = TK_LESS
        of '[': kind = TK_RIGHTSTAPLE
        of '.':
            skip(ls)
            if match(ls,'.'):
                skip(ls)
                if match(ls,'.'):
                    kind = TK_DOTS
                else:
                    kind = TK_CONCAT
            else:
                kind = TK_DOT
        else:
            kind = TK_ERROR

    if kind == TK_ERROR:
        syntaxError(ls.lineNumber, fmt"Invalid character {$peek(ls)}")

    return createToken(ls.lineNumber, kind, $kind)



const LITERALS = {',', '(', ')', '{', '}', '+', '/', '*', ';', '#', '^',
        '%', '.', '=', '>', '<', '-', ':', '~', '[', ']'}


proc getToken(ls): Token =
    resetLexeme(ls)

    let skipped = skipWhitespace(ls.buf, ls.bufpos)
    if skipped > 0:
        skip(ls, skipped)

    if peek(ls) in lexbase.Newlines:
        handleNewline(ls)
        return getToken(ls)


    let ch = peek(ls)
    echo "ch is: ",ch
    case ch:
        of ' ':
            skip(ls)
            result = getToken(ls)
        of '"', '\'':
            parseString(ls)
            result = createToken(ls.linenumber, TK_STRING, ls.lexeme)
        of Digits:
            parseNumeral(ls)
            result = createToken(ls.linenumber, TK_NUMBER, ls.lexeme)
        of Literals:
            if peek(ls) == '[' and peek(ls, 1) == '[':
                parseLongString(ls)
                result = createToken(ls.linenumber, TK_STRING, ls.lexeme)
            elif peek(ls) == '-' and peek(ls, 1) == '-':
                if peek(ls, 2) == '[' and peek(ls, 3) == '[':
                    skipLongComment(ls)
                    result = getToken(ls)
                else:
                    skipComment(ls)
                    result = getToken(ls)
            else:
                result = parseLiteral(ls)
        of Letters:
            parseVar(ls)
            result = createToken(ls.linenumber, getReserved(ls), ls.lexeme)
        else:
            syntaxError(ls.linenumber, fmt"Invalid character: {ch}")

proc lex*(ls) =
    
    while not isEOF(ls):
        ls.tokens.add(getToken(ls))

    ls.tokens.add(createEOFToken(ls.linenumber))
    close(ls)
