import std/[lists,options,tables]
import lobject,token

type
    StmtKind* = enum 
        STBlock
        STExpression
        STCall
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
    LuaState = ref object
    BinaryExpr = ref object
        left: Expression
        right: Expression
        op: Token
    UnaryExpr = ref object
        right: Expression
        op: Token
    CallStmt = ref object
        funcName*: string
        args*: Table[string,LuaValue]
    Statement* = ref object
        case kind*:StmtKind
            of STBlock:
                body: DoublyLinkedList[Statement]
            of STExpression:
                expression: Expression
            of STCall:
                call: CallStmt
    Expression* = ref object
        case kind*: ExprKind
            of EKLiteral:
                literal: LuaValue
            of EKBinary:
                binary: BinaryExpr
            of EKUnary:
                unary: UnaryExpr

proc evaluate*(b:BinaryExpr): LuaValue
proc evaluate*(u:UnaryExpr): LuaValue
proc evaluate*(stm:Statement)
proc evaluate*(exp:Expression):LuaValue



proc add*(parent:Statement,child:Statement) =
    parent.body.add(child)

proc newExpression(kind:ExprKind): Expression = 
    result.kind = kind

proc newLiteralImpl(): Expression = result = newExpression(EKLiteral)

proc newLiteral*(): Expression = 
    result = newLiteralImpl()

proc newLiteral*(value:int64): Expression = 
    result = newLiteralImpl()


proc newLiteral*(value:float64): Expression = 
    result = newLiteralImpl()

proc newLiteral*(value:string): Expression = 
    result = newLiteralImpl()

proc newLiteral*(value:bool): Expression = 
    result = newLiteralImpl()

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

proc newCallStmt*(funcName:string,args:Table[string,LuaValue]): Statement =
    result = newStatement(STCall)
    result.call = CallStmt(funcName: funcName, args: args)

proc evaluate(v:LuaValue): LuaValue = v


proc evaluate(b:BinaryExpr): LuaValue = 
    let lhs = evaluate(b.left)
    let rhs = evaluate(b.right)
    let op = b.op.kind
    result = LUANIL
    # case op:
    #     of TK_PLUS: 
    #         result = lhs + rhs
    #     of TK_MINUS: 
    #         result = lhs - rhs
    #     of TK_STAR:
    #         result = lhs * rhs
    #     of TK_SLASH:
    #         result = lhs / rhs
    #     of TK_DBSLASH:
    #         result = lhs // rhs
        # of TK_AND:
        #     result = lhs and rhs
        # of TK_BAND:
        #     result = lhs & rhs
        # of TK_OR:
        #     result = lhs or rhs
        # of TK_BOR:
        #     result = lhs | rhs
        # of TK_CONCAT:
        #     result = lhs .. rhs
        # of TK_EQEQ:
        #     result = `==`(lhs,rhs)
        # of TK_LESS:
        #     result = lhs < rhs
        # of TK_LE:
        #     result = lhs <= rhs
        # of TK_GREATER:
        #     result = lhs > rhs
        # of TK_GE:
        #     result = lhs >= rhs
        # of TK_CARROT:
        #     result = lhs ^ rhs
        # of TK_MOD:
        #     result = lhs % rhs
        # of TK_NE:
        #     result = lhs ~= rhs
        # else: discard

proc evaluate(u:UnaryExpr): LuaValue =
    let rhs = evaluate(u.right)
    let op = u.op
    result = LUANIL
    # case op.kind:
    #     of TK_HASH: 
    #         result = len(rhs)
    #     of TK_MINUS: 
    #         result = `-`(rhs)
    #     of TK_NOT:
    #         result = not rhs
    #     of TK_TILDE:
    #         result = `~`(rhs)
    #     else: discard

proc evaluate(exp:Expression):LuaValue = 
    let kind = exp.kind
    case kind:
        of EKBinary: result = evaluate(exp.binary)
        of EKUnary: result = evaluate(exp.unary)
        of EKLiteral: result = evaluate(exp.literal)

proc evaluate(body:DoublyLinkedList[Statement]) = 
    for b in items(body):
        evaluate(b)

proc evaluate*(stm:Statement) =
    let kind = stm.kind
    case kind:
        of STBlock: evaluate(stm.body)
        of STExpression: discard evaluate(stm.expression)
        of STCall: discard