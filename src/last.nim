import std/[lists,options]
import lobject,token

type
    StmtKind* = enum 
        STBlock
        STExpression
        # STCall
        # STLabel
        # STGoto
        # STDo
        # STWhile
        # STIf
        # STFor
        # STFuncDecl
        # STVarDecl
        # STLocal
    ExprKind* = enum
        EKLiteral
        EKBinary
        EKUnary


type 
    BinaryExpr = ref object
        left: Expression
        right: Expression
        op: Token
    UnaryExpr = ref object
        right: Expression
        op: Token
    Statement* = ref object
        case kind*:StmtKind
            of STBlock:
                body: DoublyLinkedList[Statement]
            of STExpression:
                expression: Expression
    Expression* = ref object
        case kind*: ExprKind
            of EKLiteral:
                literal: LuaValue
            of EKBinary:
                binary: BinaryExpr
            of EKUnary:
                unary: UnaryExpr

proc evaluate(exp:Expression):LuaValue
proc evaluate(s:Statement): LuaValue

proc expect(l,r:StmtKind) = discard

proc add*(parent:Statement,child:Statement) =
    expect(parent.kind,STBlock)
    parent.body.add(child)

proc newExpression(kind:ExprKind): Expression = 
    result = new Expression
    result.kind = kind

proc newLiteralImpl(): Expression = result = newExpression(EKLiteral)

proc newLiteral*(): Expression = 
    result = newLiteralImpl()
    result.literal = newLNil()

proc newLiteral*(value:int64): Expression = 
    result = newLiteralImpl()
    result.literal = newLInteger(value)

proc newLiteral*(value:float64): Expression = 
    result = newLiteralImpl()
    result.literal = newLFloat(value)

proc newLiteral*(value:string): Expression = 
    result = newLiteralImpl()
    result.literal = newLString(value)

proc newLiteral*(value:bool): Expression = 
    result = newLiteralImpl()
    result.literal = newLBool(value)

proc newBinary*(lhs,rhs:Expression,op:Token): Expression = 
    result = newExpression(EKBinary)
    result.binary = BinaryExpr(left:lhs,right:rhs,op:op)

proc newUnary*(rhs:Expression,op:char): Expression = 
    result = newExpression(EKUnary)
    result.unary = UnaryExpr(right:rhs,op:op)

proc newStatement(kind:StmtKind): Statement =
    result = new Statement
    result.kind = kind

proc newBlock*(): Statement =
    result = newStatement(STBlock)

proc newExpressionStmt*(exp:Expression): Statement =
    result = newStatement(STExpression)
    result.expression = exp


proc evaluate(v:LuaValue): LuaValue = v

proc evaluate(b:BinaryExpr): LuaValue = 
    let lhs = evaluate(b.left)
    let rhs = evaluate(b.right)
    let op = b.op.kind
    case op:
        of TK_PLUS: 
            let total = lhs + rhs
            if isSome(total):
                result = get(total)
            else:
                result = newLNil()
        of TK_MINUS: 
            let total = lhs - rhs
            if isSome(total):
                result = get(total)
            else:
                result = newLNil()
        of TK_STAR:
            let total = lhs * rhs
            if isSome(total):
                result = get(total)
            else:
                result = newLNil()
        of TK_SLASH:
            let total = lhs / rhs
            if isSome(total):
                result = get(total)
            else:
                result = newLNil()
        of TK_DBSLASH:
            let total = lhs // rhs
            if isSome(total):
                result = get(total)
            else:
                result = newLNil()
        of TK_AND,TK_BAND:
            let total = lhs and rhs
            if isSome(total):
                result = get(total)
            else:
                result = newLNil()
        of TK_OR,TK_BOR:
            let total = lhs or rhs
            if isSome(total):
                result = get(total)
            else:
                result = newLNil()
        of TK_CONCAT:
            let total = lhs .. rhs
            if isSome(total):
                result = get(total)
            else:
                result = newLNil()
        of TK_EQEQ:
            let total = lhs == rhs
            if isSome(total):
                result = get(total)
            else:
                result = newLNil()
        of TK_LESS:
            let total = lhs < rhs
            if isSome(total):
                result = get(total)
            else:
                result = newLNil()
        of TK_LE:
            let total = lhs <= rhs
            if isSome(total):
                result = get(total)
            else:
                result = newLNil()
        of TK_GREATER:
            let total = lhs > rhs
            if isSome(total):
                result = get(total)
            else:
                result = newLNil()
        of TK_GE:
            let total = lhs >= rhs
            if isSome(total):
                result = get(total)
            else:
                result = newLNil()
        of TK_CARROT:
            let total = pow(lhs,rhs)
            if isSome(total):
                result = get(total)
            else:
                result = newLNil()
        of TK_MOD:
            let total = `mod`(lhs,rhs)
            if isSome(total):
                result = get(total)
            else:
                result = newLNil()
        of TK_NE:
            let total = lhs ~= rhs
            if isSome(total):
                result = get(total)
            else:
                result = newLNil()
        else: discard

proc evaluate(u:UnaryExpr): LuaValue =
    let rhs = evaluate(u.right)
    let op = u.op
    case op.kind:
        of TK_HASH: 
            let r = len(rhs)
            if isSome(r):
                result = get(r)
            else:
                result = newLNil()
        of TK_MINUS: 
            let r = `-`(rhs)
            if isSome(r):
                result = get(r)
            else:
                result = newLNil()
        of TK_NOT:
            let r = `not`(rhs)
            if isSome(r):
                result = get(r)
            else:
                result = newLNil()
        else: discard

proc evaluate(exp:Expression):LuaValue = 
    let kind = exp.kind
    case kind:
        of EKBinary: result = evaluate(exp.binary)
        of EKUnary: result = evaluate(exp.unary)
        else: discard

proc evaluate(stm:Statement): Expression =
    let kind = stm.kind
    case kind:
        of STBlock: discard
        of STExpression: discard
        else: discard