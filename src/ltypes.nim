from std/tables import TableRef, Table
from std/sets import HashSet
from std/streams import Stream

type
  CoroutineStatus* = enum
    csSuspended, csRunning, csNormal, csDead
  ValueAttribute* = enum
    laConst,
    laClose,
    laLocal,
    laGlobal
  OpCode* = enum
    opReturn,   # End of execution
    opReturnSpread,
    opConstant, # Load a constant value onto the stack
    opAdd,      # Pop two values, add them, push the result
    opSubtract,
    opMultiply,
    opDivide,
    opFloorDiv,
    opModulo,
    opExponent,
    opNegate,
    opBitAnd,
    opBitOr,
    opBitXor,
    opShr,
    opShl,
    opBitNot,
    opNot,
    opEquals,
    opLess,
    opLessEqual,
    opGreater,
    opGreaterEqual,
    opNotEqual,
    opLen,
    opConcat,
    opNewTable, # Creates an empty {} and pushes it to the stack
    opGetTable, # table["key"] -> retrieves value
    opSetTable, # table["key"] = value -> stores value
    opCall,
    opCallSpread,
    opGetMethod,
    opSetLocal,
    opGetLocal,
    opJumpIfFalse,
    opJump,
    opPop,
    opClosure,
    opGetUpvalue,
    opSetUpvalue,
    opCloseUpvalue,
    opVararg,
    opSpreadVararg,
    opLoop,
    opAdjust,
    opCloseValue,
    opSpreadVarargValues,
    opMarkGlobalConst

type
  LuaStack* = ref object
    values*: seq[LuaValue]
    openUpvalues*: seq[LuaUpvalue]
  LuaCoroutine* = ref object of LuaUserData
    frames*: seq[CallFrame]
    stack*: LuaStack
    status*: CoroutineStatus
    fn*: LuaValue
    hasStarted*: bool
    ownRunDepth*: int 
  ProcessCapabilities* = object
    allowExecute*: bool   # d
  LuaUserData* = ref object of RootObj
  LuaUpValue* = ref object
    isOpen*: bool
    stack*: LuaStack        # NEW: which stack `location` indexes into
    location*: int
    closed*: LuaValue
    isLocal*: bool
    isConst*: bool
  CompilerUpvalue* = object
    index*: uint8
    isLocal*: bool
    isConst*: bool
  LuaClosure* = ref object
    fn*: LuaFunction
    upvalues*: seq[LuaUpValue]
  Chunk* = ref object
    code*: seq[uint8]         # The flat array of instructions
    constants*: seq[LuaValue] # The pool of raw values (from Phase 1!)
    lines*: seq[int]
  LuaKind* = enum
    ltNil = "nil",
    ltBool = "bool",
    ltNumber = "number",
    ltInteger = "integer",
    ltString = "string",
    ltTable = "table",
    ltNativeFn = "nim function",
    ltClosure = "lua function",
    ltNativeFnVM = "nim function"
    ltUserData = "user data"
  LuaFunction* = ref object
    name*: string
    arity*: int
    chunk*: Chunk
    isVararg*: bool
  NativeFunc* = proc(args: varargs[LuaValue]): seq[LuaValue]
  NativeFuncVM* = proc(vm: var VM, args: varargs[LuaValue]): seq[LuaValue]
  LuaTable* = TableRef[LuaValue, LuaValue]
  LuaValue* = ref object
    mt*: LuaValue
    case kind*: LuaKind
    of ltNil: discard
    of ltBool: bval*: bool
    of ltNumber: nval*: float64
    of ltInteger: ival*: int64
    of ltString: sval*: string
    of ltTable: tval*: LuaTable
    of ltClosure: fnVal*: LuaClosure
    of ltNativeFn: nativeFn*: NativeFunc
    of ltNativeFnVM: nativeFnVM*: NativeFuncVM
    of ltUserData: ud*: LuaUserData
  Local* = object
    name*: string
    depth*: int
    isCaptured*: bool
    slot*: int
    isConst*: bool
    isClosed*: bool
  LoopContext* = object
    scopeDepth*: int
    breakJumps*: seq[int]
  PendingGoto* = object
    name*: string
    pc*: int
    scopeDepth*: int
    line*: int
  LabelSymbol* = object
    name*: string
    pc*: int
    scopeDepth*: int
  Compiler* = ref object
    enclosing*: Compiler
    fn*: LuaClosure
    locals*: seq[Local]
    globals*: Table[string, bool]
    upvalues*: seq[CompilerUpvalue]
    scopeDepth*: int
    loops*: seq[LoopContext]  # <--- Loop stack for break tracking
    labels*: seq[LabelSymbol] # <--- Declared labels in current function
    gotos*: seq[PendingGoto]
  CallFrame* = ref object
    closure*: LuaClosure
    ip*: int
    slotBase*: int
    vararg*: LuaValue
  VM* = object
    chunk*: Chunk
    stack*: LuaStack   # The evaluation stack
    globals*: Table[string, LuaValue]
    globalConsts*: HashSet[string]
    frames*: seq[CallFrame] # NEW: The Call Stack!
    traceExecution*: bool
    lastReturnCount*: int
    metaDepth*: int
    lastError*: LuaValue
    output*: Stream
    processCaps*: ProcessCapabilities
    yieldRequested*: bool
    yieldValues*: seq[LuaValue]
    currentCoroutine*: LuaCoroutine   # nil means "the main thread"
    nestedRunDepth*: int   

proc `[]`*(s:LuaStack,index:int): LuaValue = s.values[index]
proc `[]=`*(s:var LuaStack,index:int,v:sink LuaValue) = s.values[index] = v
proc len*(s:LuaStack):int = len(s.values)
proc high*(s:LuaStack): int = s.values.high
proc setLen*(s:var LuaStack,newLen:Natural) = s.values.setLen(newLen)
proc add*(s: var LuaStack,v:sink LuaValue) = s.values.add(v)