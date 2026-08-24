import std/[lexbase, tables, streams, strutils, parseutils]
import lerror

type
  TokenKind* = enum
    # Single-character tokens
    tkPlus, tkMinus, tkStar, tkSlash, tkAssign, tkLeftParen, tkRightParen,
    tkTilde, tkAmp, tkPipe, tkComma, tkLeftBracket, tkRightBracket,
    tkLeftBrace, tkRightBrace, tkDot, tkLess, tkGreater, tkCaret, tkPercent,
      tkHash, tkColon

    # Two-character tokens
    tkEquals, tkNotEquals, tkLessEqual, tkGreaterEqual, tkConcat, tkLeftShift,
      tkRightShift, tkDoubleSlash, tkDbColon

    # Three character tokens
    tkDots
    # Literals
    tkIdent, tkString, tkNumber, tkTrue, tkFalse, tkNil

    # Keywords
    tkLocal, tkFunction, tkIf, tkElseIf, tkElse, tkThen, tkEnd, tkReturn,
      tkGlobal,
    tkWhile, tkRepeat, tkFor, tkDo, tkBreak, tkAnd, tkNot, tkOr, tkGoto, tkIn,
      tkEnum, tkUntil

    # Special
    tkEOF, tkError

type
  Token* = object
    kind*: TokenKind
    lexeme*: string
    line*: int
  LuaLexer* = object of BaseLexer
    lineNum: int

func kind*(t: Token): TokenKind = t.kind
func lexeme*(t: Token): string = t.lexeme
func line*(t: Token): int = t.line

func createToken(line: int, kind: TokenKind, lexeme: string): Token = Token(
    kind: kind, lexeme: lexeme, line: line)

func createEOFToken(line: int): Token = result = createToken(line, tkEOF, "eof")


const keywords = {
  "local": tkLocal,
  "function": tkFunction,
  "if": tkIf,
  "elseif": tkElseIf,
  "else": tkElse,
  "then": tkThen,
  "end": tkEnd,
  "while": tkWhile,
  "for": tkFor,
  "repeat": tkRepeat,
  "return": tkReturn,
  "global": tkGlobal,
  "true": tkTrue,
  "false": tkFalse,
  "do": tkDo,
  "nil": tkNil,
  "break": tkBreak,
  "not": tkNot,
  "and": tkAnd,
  "or": tkOr,
  "goto": tkGoto,
  "in": tkIn,
  "enum": tkEnum,
  "until": tkUntil
}.toTable

using
  l: LuaLexer
  vl: var LuaLexer

proc initLexer(source: string): LuaLexer =
  result = LuaLexer()
  result.open(newStringStream(source))
  result.lineNum = 1

proc atEnd(l): bool = l.buf[l.bufpos] == EndOfFile
proc peek(l): char = l.buf[l.bufpos]
proc peek(l; step: int): char = l.buf[l.bufpos + step]

proc advance(vl): char =
  result = peek(vl)
  inc(vl.bufpos)

proc match(vl; c: char): bool =
  result = false
  if vl.peek() == c:
    discard vl.advance()
    result = true

proc parseWhile(vl; whle: set[char]): string = inc(vl.bufpos, parseWhile(vl.buf,
    result, whle, vl.bufpos))


proc scanLineComment(vl) =
  while true:
    let c = vl.peek()
    if c == EndOfFile or c in lexbase.NewLines:
      return # leave the newline itself for scanToken's own (now-fixed) handling
    discard vl.advance()

proc scanQuotedString(vl; quote: char): string =
  result = ""
  while true:
    let c = vl.peek()
    if c == EndOfFile or c in lexbase.NewLines:
      raise newException(LuaSyntaxError, "Unterminated string")
    if c == quote:
      discard vl.advance()
      return result
    if c == '\\':
      discard vl.advance()   # consume the backslash
      let esc = vl.peek()
      case esc
      of 'n': result.add('\n'); discard vl.advance()
      of 't': result.add('\t'); discard vl.advance()
      of 'r': result.add('\r'); discard vl.advance()
      of 'a': result.add('\a'); discard vl.advance()
      of 'b': result.add('\b'); discard vl.advance()
      of 'f': result.add('\f'); discard vl.advance()
      of 'v': result.add('\v'); discard vl.advance()
      of '\\': result.add('\\'); discard vl.advance()
      of '"': result.add('"'); discard vl.advance()
      of '\'': result.add('\''); discard vl.advance()
      of 'x':
        discard vl.advance()
        var hex = ""
        for _ in 0 ..< 2:
          if vl.peek() in HexDigits: hex.add(vl.advance())
          else: raise newException(LuaSyntaxError, "hexadecimal digit expected in \\x escape")
        result.add(char(parseHexInt(hex)))
      of '0'..'9':
        var dec = ""
        for _ in 0 ..< 3:
          if vl.peek() in Digits: dec.add(vl.advance())
          else: break
        let code = parseInt(dec)
        if code > 255:
          raise newException(LuaSyntaxError, "decimal escape too large")
        result.add(char(code))
      of 'z':
        # \z skips all following whitespace, including real newlines -- a
        # readability aid for breaking a long string across source lines
        discard vl.advance()
        while vl.peek() in {' ', '\t'} or vl.peek() in lexbase.NewLines:
          if vl.peek() in lexbase.NewLines:
            if vl.peek() == '\c': vl.bufpos = vl.handleCR(vl.bufpos)
            else: vl.bufpos = vl.handleLF(vl.bufpos)
            inc(vl.lineNum)
          else:
            discard vl.advance()
      of lexbase.NewLines:
        # backslash immediately followed by a real newline embeds ONE newline
        if esc == '\c': vl.bufpos = vl.handleCR(vl.bufpos)
        else: vl.bufpos = vl.handleLF(vl.bufpos)
        inc(vl.lineNum)
        result.add('\n')
      else:
        raise newException(LuaSyntaxError, "invalid escape sequence '\\" & esc & "'")
    else:
      result.add(vl.advance())

proc scanLongString(vl): string =
  result = ""
  while true:
    let c = vl.peek()
    if c == EndOfFile:
      raise newException(LuaSyntaxError, "Unterminated long string")
    if c == ']' and vl.peek(1) == ']':
      discard vl.advance()
      discard vl.advance()
      return result
    if c in lexbase.NewLines:
      if c == '\c':
        vl.bufpos = vl.handleCR(vl.bufpos)
      else:
        vl.bufpos = vl.handleLF(vl.bufpos)
      inc(vl.lineNum)
      result.add('\n')
    else:
      result.add(vl.advance())

proc scanToken(vl): Token =
  if vl.atEnd():
    return createEOFToken(vl.lineNum)

  let c = vl.advance()

  case c
  of ' ', '\t':
    # Ignore whitespace and just scan the next token
    return vl.scanToken()
  of lexbase.NewLines:
    if c == '\c':
      vl.bufpos = vl.handleCR(vl.bufpos - 1)
    else:
      vl.bufpos = vl.handleLF(vl.bufpos - 1)
    inc(vl.lineNum)
    return vl.scanToken()
  of '+': return createToken(vl.lineNum, tkPlus, "+")
  of ';':
    return vl.scanToken()
  of '-':
    if vl.match('-'):
      vl.scanLineComment()
      return vl.scanToken()
    else:
      return createToken(vl.lineNum, tkMinus, "-")
  of '(':
    return createToken(vl.lineNum, tkLeftParen, "(")
  of ')':
    return createToken(vl.lineNum, tkRightParen, ")")
  of ',':
    return createToken(vl.lineNum, tkComma, ",")
  of ']':
    return createtoken(vl.lineNum, tkRightBracket, "]")
  of '{':
    return createToken(vl.lineNum, tkLeftBrace, "{")
  of '}':
    return createToken(vl.lineNum, tkRightBrace, "}")
  of '&':
    return createToken(vl.lineNum, tkAmp, "&")
  of '|':
    return createToken(vl.lineNum, tkPipe, "|")
  of '^':
    return createToken(vl.lineNum, tkCaret, "^")
  of '*':
    return createToken(vl.lineNum, tkStar, "*")
  of '%':
    return createToken(vl.lineNum, tkPercent, "%")
  of '#':
    return createToken(vl.lineNum, tkHash, "#")
  of ':':
    if vl.match(':'):
      return createToken(vl.lineNum, tkDbColon, "::")
    else:
      return createToken(vl.lineNum, tkColon, ":")
  of '/':
    if vl.match('/'):
      return createToken(vl.lineNum, tkDoubleSlash, "//")
    else:
      return createToken(vl.lineNum, tkSlash, "/")
  of '<':
    if vl.match('='):
      return createToken(vl.lineNum, tkLessEqual, "<=")
    elif vl.match('<'):
      return createToken(vl.lineNum, tkLeftShift, "<<")
    else:
      return createToken(vl.lineNum, tkLess, "<")
  of '>':
    if vl.match('='):
      return createToken(vl.lineNum, tkGreaterEqual, ">=")
    elif vl.match('>'):
      return createToken(vl.lineNum, tkRightShift, ">>")
    else:
      return createToken(vl.lineNum, tkGreater, ">")
  of '.':
    if vl.peek(0) == '.' and vl.peek(1) == '.':

      inc(vl.bufpos, 2)
      return createToken(vl.lineNum, tkDots, "...")
    elif vl.peek(0) == '.':

      inc(vl.bufpos, 1)
      return createToken(vl.lineNum, tkConcat, "..")
    else:
      return createToken(vl.lineNum, tkDot, ".")
  of '[':
    if vl.match('['):
      let text = vl.scanLongString()
      return createToken(vl.lineNum, tkString, text)
    else:
      return createToken(vl.lineNum, tkLeftBracket, "[")
  of '"', '\'':
    let text = vl.scanQuotedString(c)
    return createToken(vl.lineNum, tkString, text)
  of '~':
    if vl.match('='):
      return createToken(vl.lineNum, tkNotEquals, "~=")
    else:
      return createToken(vl.lineNum, tkTilde, "~")
  of '=':
    if vl.match('='):
      return createToken(vl.lineNum, tkEquals, "==")
    else:
      return createToken(vl.lineNum, tkAssign, "=")
  else:
    # Multi-character tokens (Numbers and Identifiers)
    if c.isDigit():
      if c == '0' and (vl.peek() == 'x' or vl.peek() == 'X'):
        discard vl.advance()   # consume the 'x'/'X'
        let hexDigits = vl.parseWhile(HexDigits)
        if hexDigits.len == 0:
          raise newException(LuaSyntaxError, "malformed number near '0x'")
        let value = parseHexInt(hexDigits)
        return createToken(vl.lineNum, tkNumber, $value)
      else:
        dec vl.bufpos
        let numStr = vl.parseWhile(Digits + {'.', 'e', 'E'})
        return createToken(vl.lineNum, tkNumber, numStr)
    elif c.isAlphaAscii() or c == '_':
      dec vl.bufpos
      let ident = vl.parseWhile(IdentChars)

      if keywords.hasKey(ident):
        return createToken(vl.lineNum, keywords[ident], ident)
      else:
        return createToken(vl.lineNum, tkIdent, ident)

    else:
      # In a real VM, you'd throw a proper error here.
      let msg = "Unexpected character: " & $c & " at line " & $vl.lineNum
      raise newException(LuaSyntaxError, msg)

proc tokenize*(source: string): seq[Token] =
  var vl = initLexer(source)
  result = @[]
  while true:
    let tok = vl.scanToken()
    result.add(tok)
    if tok.kind == tkEOF: break
