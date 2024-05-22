
type
    OpMode = enum
        iABC,
        iABx,
        iAsBx,
        iAx
    OpCodes = enum
        OP_MOVE,
        OP_LOADK,
        OP_LOADKX,
        OP_LOADBOOL,
        OP_LOADNIL,
        OP_GETUPVAL,
        OP_GETTABUP,
        OP_GETTABLE,
        OP_SETTABUP,
        OP_SETUPVAL,
        OP_SETTABLE,
        OP_NEWTABLE,
        OP_SELF,
        OP_ADD,
        OP_SUB,
        OP_MUL,
        OP_DIV,
        OP_MOD,
        OP_POW,
        OP_UNM,
        OP_NOT,
        OP_LEN,
        OP_CONCAT,
        OP_JMP,
        OP_EQ,
        OP_LT,
        OP_LE,
        OP_TEST,
        OP_TESTSET,
        OP_CALL,
        OP_TAILCALL,
        OP_RETURN,
        OP_FORLOOP,
        OP_FORPREP,
        OP_TFORCALL,
        OP_TFORLOOP,
        OP_SETLIST,
        OP_CLOSURE,
        OP_VARARG,
        OP_EXTRAARG
    OpArgMask = enum
        OpArgN,
        OpArgU,
        OpArgR,
        OpArgK

const SIZE_C = 9
const SIZE_B = 9
const SIZE_Bx = SIZE_C + SIZE_B
const SIZE_A = 8
const SIZE_Ax = SIZE_C + SIZE_B + SIZE_A

const SIZE_OP = 6

const POS_OP = 0
const POS_A = POS_OP + SIZE_OP
const POS_C = POS_A + SIZE_A
const POS_B = POS_C + SIZE_C
const POS_Ax = POS_A
const POS_Bx = POS_C

const MAXARG_Ax = (1 shl SIZE_Ax) - 1
const MAXARG_Bx = (1 shl SIZE_Bx) - 1
const MAXARG_sBx = MAXARG_Bx shr 1

proc MASK1(n:int,p:int): int = result = 0

proc GET_OPCODE(i:int): OpCodes = discard

