from llex import Token
import types
# expressions
    # Literal (nil|bool|int|float|string)
    # '...' variadic
    # Binary
    # Unary
    # TableConstructor
    # Call
# statements
    # ExpressionStmt (varlist) (grouping?)
    # FunctionCall
    # Label
    # Break
    # goto
    # do block
    # while block
    # repeat block
    # if then block
    # for block
    # function declaration
    # local declaration (func/variable)

type
    LuaValueKind = enum 
        LVNone = -1
        LVNil
        LVBoolean
        LVNumber
        LVFloat
        LVString
        LVTable
        LVUserdata
        LVFunction
        LVThread
        LVProto
    LuaNodeKind = enum
        LKLiteral
        LKVariadic
        LKBinary
        LKUnary
        LKTabConstruct
        LKCall
        LKExprStmt
        LKFunction
        LKLabel
        LKBreak
        LKGoto
        LKDo
        LKWhile
        LKRepeat
        LKIf
        LKFor
        LKLocal


type 
    LuaNode {.acyclic.} = ref object
        case kind*: LuaNodeKind
            of LKLiteral:
                literalv*: LuaValue
            of LKLocal:
                localv*: LuaValue
            of LKVariadic:
                variadic*: LuaValue
            of LKBinary:
                bleft*: LuaExpr
                bright*: LuaExpr
                bop*: Token
            of LKUnary:
                uleft*: LuaExpr
                uop*: Token
            of LKTabConstruct:
                table*: LuaValue
            of LKCall:
                cName*: string
                callee*: LuaValue
                cparams*: seq[LuaValue]
            of LKExprStmt:
                expression*: LuaExpr
            of LKFunction:
                fName*: string
                fparams*: seq[Token]
                fBody*: LuaStmt
            of LKLabel,LKGoto,LKBreak:
                goto*: int
            of LKDo:
                doto*: int
            of LKWhile,LKFor,LKRepeat:
                cond*: LuaExpr
                bBody*: LuaStmt
            of LKIf:
                ifBranch*: LuaExpr
                elseBranch*: LuaExpr # need to support multiple branches
    LuaExpr = ref object
    LuaStmt = ref object
