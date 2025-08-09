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

proc evaluate(b:BinaryExpr): LuaValue
proc evaluate(u:UnaryExpr): LuaValue
proc evaluate(stm:Statement): Expression
proc evaluate(exp:Expression):LuaValue


proc add*(parent:Statement,child:Statement) =
    expect(parent.kind,STBlock)
    parent.body.add(child)

proc newExpression(kind:ExprKind): Expression = 
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

proc newUnary*(rhs:Expression,op:Token): Expression = 
    result = newExpression(EKUnary)
    result.unary = UnaryExpr(right:rhs,op:op)

proc newStatement(kind:StmtKind): Statement = 
    result.kind = kind

proc newBlock*(): Statement =
    result = newStatement(STBlock)

proc newExpressionStmt*(exp:Expression): Statement =
    result = newStatement(STExpression)
    result.expression = exp


proc evaluate(v:LuaValue): LuaValue = v

template binop(op:untyped):untyped = 
    let total = `op`(lhs,rhs)
    if isSome(total):
        result = get(total)
    else:
        result = newLNil()

proc evaluate(b:BinaryExpr): LuaValue = 
    let lhs = evaluate(b.left)
    let rhs = evaluate(b.right)
    let op = b.op.kind
    case op:
        of TK_PLUS: 
            binop(`+`)
        of TK_MINUS: 
            binop(`-`)
        of TK_STAR:
            binop(`*`)
        of TK_SLASH:
            binop(`/`)
        of TK_DBSLASH:
            binop(`//`)
        of TK_AND,TK_BAND:
            binop(`and`)
        of TK_OR,TK_BOR:
            binop(`or`)
        of TK_CONCAT:
            binop(`..`)
        of TK_EQEQ:
            binop(`==`)
        of TK_LESS:
            binop(`<`)
        of TK_LE:
            binop(`<=`)
        of TK_GREATER:
            binop(`>`)
        of TK_GE:
            binop(`>=`)
        of TK_CARROT:
            binop(`pow`)
        of TK_MOD:
            binop(`mod`)
        of TK_NE:
            binop(`~=`)
        else: discard

template unop(op:untyped):untyped =
    let r = `op`(rhs)
    if isSome(r):
        result = get(r)
    else:
        result = newLNil()

proc evaluate(u:UnaryExpr): LuaValue =
    let rhs = evaluate(u.right)
    let op = u.op
    case op.kind:
        of TK_HASH: 
            unop(`len`)
        of TK_MINUS: 
            unop(`-`)
        of TK_NOT:
            unop(`not`)
        else: discard

proc evaluate(exp:Expression):LuaValue = 
    let kind = exp.kind
    case kind:
        of EKBinary: result = evaluate(exp.binary)
        of EKUnary: result = evaluate(exp.unary)
        of EKLiteral: result = evaluate(exp.literal)

proc evaluate(body:DoublyLinkedList[Statement]) = 
    for b in items(body):
        discard evaluate(b)

proc evaluate(stm:Statement) =
    let kind = stm.kind
    case kind:
        of STBlock: evaluate(stm.body)
        of STExpression: discard evaluate(stm.expression)