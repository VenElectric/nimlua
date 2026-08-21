from std/tables import TableRef,Table

type 
  ValueAttribute* = enum
    laConst,
    laClose,
    laLocal,
    laGlobal

type
  LuaUpValue* = ref object
    location*: int
    value*: LuaValue
    isOpen*: bool
    isLocal*: bool
    closed*: LuaValue
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
    ltString = "string", 
    ltTable = "table", 
    ltNativeFn = "nim function", 
    ltClosure = "lua function",
    ltNativeFnVM = "nim function"
  LuaFunction* = ref object
    name*: string 
    arity*: int  
    chunk*: Chunk
    isVararg*: bool
  NativeFunc* = proc(args: varargs[LuaValue]): seq[LuaValue]
  NativeFuncVM* = proc(vm: var VM, args: varargs[LuaValue]): seq[LuaValue]
  LuaTable* = TableRef[LuaValue, LuaValue]
  LuaValue* = ref object
    case kind*: LuaKind
    of ltNil: discard
    of ltBool: bval*: bool
    of ltNumber: nval*: float64
    of ltString: sval*: string
    of ltTable: 
      tval*: LuaTable
      mt*: LuaValue
    of ltClosure: fnVal*: LuaClosure
    of ltNativeFn: nativeFn*: NativeFunc
    of ltNativeFnVM: nativeFnVM*: NativeFuncVM
  Local* = object
    name*: string
    depth*: int
    isCaptured*: bool
    slot*: int
    attr*: ValueAttribute
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
    scopeDepth*: int
    loops*: seq[LoopContext]    # <--- Loop stack for break tracking
    labels*: seq[LabelSymbol]   # <--- Declared labels in current function
    gotos*: seq[PendingGoto]
  CallFrame* = ref object
    closure*: LuaClosure 
    ip*: int           
    slotBase*: int
    vararg*: LuaValue
  VM* = object
    chunk*: Chunk
    ip*: int                # Instruction Pointer
    stack*: seq[LuaValue]   # The evaluation stack
    globals*: Table[string, LuaValue]
    frames*: seq[CallFrame] # NEW: The Call Stack!
    traceExecution*: bool
    openUpValues*: seq[LuaUpValue]
    lastReturnCount*: int