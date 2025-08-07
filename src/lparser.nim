import token,last
from last import newBinary
from state import LuaState,ParseState
import std/strformat



using
    L: var LuaState
    vp: var ParseState

func check(vp; kindB: TokenKind): bool = vp.currentToken.kind == kindB
func check(vp; kinds: set[TokenKind]): bool = vp.currentToken.kind in kinds

func peek(vp): Token = vp.tokens[vp.cursor]

func atEnd(vp): bool = check(vp,TK_EOF)

proc next(vp) = 
    if atEnd(vp):
        return
    vp.previousToken = peek(vp)
    inc(vp.cursor)
    vp.currentToken = peek(vp)

proc match(vp;kind:TokenKind): bool = 
    result = false
    if check(vp,kind):
        next(vp)
        result = true

proc match(vp;kinds:set[TokenKind]): bool = 
    result = false
    if check(vp,kinds):
        next(vp)
        result = true

proc constructor(vp): Expression = discard

proc primary(vp): Expression = 
    
    if match(vp,TK_TRUE):
        result = newLiteral(true)
    elif match(vp,TK_FALSE):
        result = newLiteral(false)
    elif match(vp,TK_NIL):
        result = newLiteral()
    elif match(vp,TK_NUMBER):
        result = newLiteral(0)
    elif match(vp,TK_STRING):
        result = newLiteral(vp.previousToken.lexeme)
    else:
        discard

proc pow(vp): Expression = 
    result = primary(vp)

proc unary(vp): Expression = 
    result = pow(vp)

proc factor(vp): Expression = 
    result = unary(vp)
   
proc term(vp): Expression = 
    result = factor(vp)
    while vp.currentToken.kind in {TK_PLUS,TK_MINUS}:
        let op = vp.previousToken
        let right = factor(vp)
        result = newBinary(result,right,op)


proc concat(vp): Expression = 
    result = term(vp)

proc shiftexpr(vp): Expression = 
    result = concat(vp)

proc bandexpr(vp): Expression = 
    result = shiftexpr(vp)

proc notexpr(vp): Expression = 
    result = bandexpr(vp)

proc borexpr(vp): Expression = 
    result = notexpr(vp)

proc comparison(vp): Expression = 
    result = borexpr(vp)

proc andexpr(vp): Expression = 
    result = comparison(vp)

proc orexpr(vp): Expression = 
    result = andexpr(vp)

proc assignment(vp): Expression = 
    result = orexpr(vp)
    while vp.currentToken.kind == TK_EQ:
        discard

proc expression(vp): Statement = result = newExpressionStmt(assignment(vp))

proc returnstmt(vp) = discard

proc gotostmt(vp) = discard

proc localstmt(vp) = discard

proc functionstmt(vp) = discard

proc forstmt(vp) = discard

proc repeatstmt(vp) = discard

proc whilestmt(vp) = discard

proc blockstmt(vp) = discard

proc ifstmt(vp) = discard

proc statement(vp): Statement =

    case vp.currentToken.kind:
        of TK_SEMCOL: return statement(vp)
        of TK_IF:
            discard
        of TK_WHILE: discard
        of TK_DO: discard
        of TK_FOR: discard
        of TK_REPEAT: discard
        of TK_FUNCTION: discard
        of TK_LOCAL: discard
        of TK_DBCOLON: discard
        of TK_RETURN: discard
        of TK_BREAK, TK_GOTO: discard
        else: return expression(vp)



proc statlist(vp): Statement =
    result = newBlock()
    while vp.currentToken.kind != TK_EOF:
        result.add(statement(vp))

proc initParser(tokens:seq[Token]): ParseState =
    result = ParseState(tokens: tokens)

proc parse*(L): Statement =
    L.parser = initParser(L.lexer.tokens)
    result = statlist(L.parser)


