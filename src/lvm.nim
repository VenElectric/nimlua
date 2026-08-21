import std/[tables, strutils, logging,math,bitops]
import lparse, llex, lvalue, lerror,ltypes
import modules/ltable

type
  OpCode* = enum
    opReturn,   # End of execution
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
    opGetGlobal,
    opSetGlobal,
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
    opAdjust

proc newLocal(name:string,depth:int,isCaptured:bool): Local = Local(name: name, depth: depth, isCaptured: isCaptured)

proc newCompiler*(fn: LuaClosure = nil,enclosing:Compiler = nil): Compiler =
  result = Compiler(locals: @[], scopeDepth: 0,enclosing: enclosing,fn: fn)
  result.locals.add(newLocal("",0,false))

proc beginScope(c: var Compiler) =
  inc(c.scopeDepth)

proc endScope(c: var Compiler, chunk: var Chunk, line: int) =
  dec(c.scopeDepth)
  # When leaving a scope, pop all locals declared inside that scope off the VM stack
  while c.locals.len > 0 and c.locals[^1].depth > c.scopeDepth:
    if c.locals[^1].isCaptured:
      chunk.writeChunk(uint8(opCloseUpvalue), line)
    else:
      chunk.writeChunk(uint8(opPop), line)
    discard c.locals.pop()

proc addLocal(c:var Compiler,name:string) = 
    if c.locals.len == int(uint8.high):
      raise newException(LuaCompileError,"Too many local variables in function")

    c.locals.add(Local(name: name,depth: c.scopeDepth,isCaptured: false))

proc addLoop(c: var Compiler) = 
  c.loops.add(LoopContext(scopeDepth: c.scopeDepth, breakJumps: @[]))

proc addBreakJump(c: var Compiler,offset:int) = 
  c.loops[^1].breakJumps.add(offset)

proc declareVariable(c: var Compiler, name: string) =

  for i in countdown(c.locals.high, 0):
    if c.locals[i].depth < c.scopeDepth: break
    if c.locals[i].name == name:
      raise newException(LuaCompileError, "Compiler Error: Variable '" & name & "' already declared in this scope.")

  c.addLocal(name)

proc resolveLocal(c: var Compiler, name: string): int =
  for i in countdown(c.locals.high, 0):
    if c.locals[i].name == name and c.locals[i].depth != -1:
      return i
  return -1

proc addUpvalue(c: var Compiler, index: int, isLocal: bool): int =
  # Check if this upvalue was already added to avoid duplicates
  for i, uv in c.fn.upvalues:
    if uv.location == index and uv.isLocal == isLocal:
      return i
  if len(c.fn.upvalues) > int(high(uint8)):
    raise newException(LuaCompileError,"Too many closure variables in function")
  
  c.fn.upvalues.add(newUpValue(index,isLocal))
  return c.fn.upvalues.len - 1

proc closeUpvalues(vm:var VM,lastIdx: int) = 
  for i in countdown(vm.openUpvalues.high, 0):
    let uv = vm.openUpvalues[i]
    
    # If the upvalue points to a stack slot being popped or left behind
    if uv.location >= lastIdx:
      uv.closed = vm.stack[uv.location] # 1. Copy value to heap
      uv.isOpen = false                      # 2. Mark as closed
      vm.openUpvalues.del(i)                 # 3. Remove from active open list

proc resolveUpvalue(c: var Compiler, name: string): int =
  if c.enclosing == nil:
    return -1

  # 1. Check if the variable is a local in the direct enclosing scope
  let localIdx = c.enclosing.resolveLocal(name)
  if localIdx != -1:
    return c.addUpvalue(localIdx, true)

  # 2. Check if the variable is an upvalue further up in outer scopes
  let outerUpvalueIdx = c.enclosing.resolveUpvalue(name)
  if outerUpvalueIdx != -1:
    return c.addUpvalue(outerUpvalueIdx, false)

  return -1

proc emitLoop(chunk: var Chunk, loopStart: int, line: int) =
  chunk.writeChunk(uint8(opLoop), line)
  let distance = chunk.code.len - loopStart + 2   # +2 for the two bytes about to be written
  if distance > 65535:
    raise newException(LuaCompileError, "Loop body too large to jump back over.")
  chunk.writeChunk(uint8((distance shr 8) and 0xFF), line)
  chunk.writeChunk(uint8(distance and 0xFF), line)

proc emitJump(chunk: var Chunk, instruction: OpCode, line: int): int =
  chunk.writeChunk(uint8(instruction), line)
  chunk.writeChunk(0xFF, line) # High byte dummy
  chunk.writeChunk(0xFF, line) # Low byte dummy
  return chunk.code.len - 2 # Return index of the high byte

# Helper to fix the dummy operand once we know the distance
proc patchJump(chunk: var Chunk, offsetIndex: int) =
  # Calculate how many bytes we emitted after the jump instruction
  let jumpDistance = chunk.code.len - offsetIndex - 2

  if jumpDistance > 65535:
    raise newException(LuaCompileError, "Error: Jump is too large to fit in 16 bits!")

  # Overwrite the dummy bytes
  chunk.code[offsetIndex] = uint8((jumpDistance shr 8) and 0xFF)
  chunk.code[offsetIndex + 1] = uint8(jumpDistance and 0xFF)

proc compile*(c: var Compiler, node: Node, chunk: var Chunk, line: int) =
  case node.kind
  of nkNumber:

    # 1. Create a LuaValue from the raw float
    let luaNum = newLuaNumber(node.nval)
    # 2. Add it to the chunk's constant pool
    let constIndex = chunk.addConstant(luaNum)
    # 3. Emit the instruction: opConstant followed by its index
    chunk.writeChunk(uint8(opConstant), node.line)
    chunk.writeChunk(constIndex, line)
  of nkString:
    let lunkr = newLuaString(node.sval)
    # 2. Add it to the constant pool
    let constIdx = chunk.addConstant(lunkr)

    # 3. Emit the opConstant instruction
    chunk.writeChunk(uint8(opConstant), node.line)
    chunk.writeChunk(constIdx, node.line)
  of nkBool:
    let bval = newLuaBool(node.bval)
    let constIdx = chunk.addConstant(bval)
    chunk.writeChunk(uint8(opConstant), node.line)
    chunk.writeChunk(constIdx, node.line)
  of nkNil:
    let constIdx = chunk.addConstant(newLuaNil())
    chunk.writeChunk(uint8(opConstant), node.line)
    chunk.writeChunk(constIdx, node.line)
  of nkBinaryOp:
    # --- POST-ORDER TRAVERSAL ---
    # Emit the left side instructions first
    c.compile(node.left, chunk, node.line)

    # Then emit the right side instructions
    c.compile(node.right, chunk, node.line)

    # Finally, emit the instruction that operates on them
    let op = node.op
    var i = case op
      of tkPlus: opAdd
      of tkMinus: opSubtract
      of tkStar: opMultiply
      of tkSlash: opDivide
      of tkConcat: opConcat
      of tkDoubleSlash: opFloorDiv
      of tkPercent: opModulo
      of tkCaret: opExponent
      of tkAmp: opBitAnd
      of tkPipe: opBitOr
      of tkTilde: opBitXor
      of tkLeftShift: opShl
      of tkRightShift: opShr
      of tkEquals: opEquals
      of tkNotEquals: opNotEqual
      of tkLess: opLess
      of tkLessEqual: opLessEqual
      of tkGreater: opGreater
      of tkGreaterEqual: opGreaterEqual
      else: raise newException(LuaCompileError,"Invalid op: " & $op)

    chunk.writeChunk(uint8(i), node.line)
  of nkUnaryOp:
    c.compile(node.right,chunk,node.line)
    let op = node.op
    let i = case op
      of tkNot: opNot
      of tkMinus: opNegate
      of tkTilde: opBitNot
      of tkHash: opLen
      else: raise newException(LuaCompileError,"Invalid unary op: " & $op)

    chunk.writeChunk(uint8(i), node.line)
  of nkAnd:
    c.compile(node.left, chunk, node.line)
    let shortCircuit = chunk.emitJump(opJumpIfFalse, node.line)  # left is falsy -> skip right entirely, left stays on stack
    chunk.writeChunk(uint8(opPop), node.line)                     # left was truthy -> discard it, evaluate right instead
    c.compile(node.right, chunk, node.line)
    chunk.patchJump(shortCircuit)
  of nkOr:
    c.compile(node.left, chunk, node.line)
    let elseJump = chunk.emitJump(opJumpIfFalse, node.line)   # left falsy -> go evaluate right
    let endJump = chunk.emitJump(opJump, node.line)           # left truthy -> skip straight past right, left stays as result
    chunk.patchJump(elseJump)
    chunk.writeChunk(uint8(opPop), node.line)                  # left was falsy -> only now do we discard it
    c.compile(node.right, chunk, node.line)
    chunk.patchJump(endJump)
  of nkIdent:
    let localSlot = c.resolveLocal(node.name)
    
    if localSlot > -1:
      # Local variable read
      chunk.writeChunk(uint8(opGetLocal), node.line)
      chunk.writeChunk(uint8(localSlot), node.line)
    else:
      let upvalueSlot = c.resolveUpvalue(node.name)
      if upvalueSlot > -1:
        chunk.writeChunk(uint8(opGetUpvalue), node.line)
        chunk.writeChunk(uint8(upvalueSlot), node.line)
      else:
        # Global variable read
        let nameIdx = chunk.addConstant(newLuaString(node.name))
        chunk.writeChunk(uint8(opGetGlobal), node.line)
        chunk.writeChunk(nameIdx, node.line)

  of nkLocalDecl:
    c.declareVariable(node.varName)
    let localSlot = c.resolveLocal(node.varName)
    if node.value != nil:
      c.compile(node.value, chunk, node.line)
    else:
      let nilIdx = chunk.addConstant(newLuaNil())
      chunk.writeChunk(uint8(opConstant), node.line)
      chunk.writeChunk(nilIdx, node.line)

    # 3. Emit opSetLocal to permanently store the value in the local's stack slot
    chunk.writeChunk(uint8(opSetLocal), node.line)
    chunk.writeChunk(uint8(localSlot), node.line)
    c.locals[localSlot].depth = c.scopeDepth 
    
  of nkGlobalDecl:
    if node.value != nil:
      c.compile(node.value, chunk, node.line)
    else:
      let nilIdx = chunk.addConstant(newLuaNil())
      chunk.writeChunk(uint8(opConstant), node.line)
      chunk.writeChunk(nilIdx, node.line)

    let nameIdx = chunk.addConstant(newLuaString(node.varName))
    chunk.writeChunk(uint8(opSetGlobal), node.line)
    chunk.writeChunk(nameIdx, node.line)

  of nkAssign:
    # Compile the right-hand side first (value to assign)
    c.compile(node.value, chunk, node.line)
    let localSlot = c.resolveLocal(node.varName)
    if localSlot > -1:
      chunk.writeChunk(uint8(opSetLocal), node.line)
      chunk.writeChunk(uint8(localSlot), node.line)
    else:
      let upvalueSlot = c.resolveUpvalue(node.varName)
      if upvalueSlot > -1:
        chunk.writeChunk(uint8(opSetUpvalue), node.line)
        chunk.writeChunk(uint8(upvalueSlot), node.line)
      else:
        let nameIdx = chunk.addConstant(newLuaString(node.varName))
        chunk.writeChunk(uint8(opSetGlobal), node.line)
        chunk.writeChunk(nameIdx, node.line)
  of nkIfStmt:
    # 1. Compile the condition
    c.compile(node.condition, chunk, node.line)
    
    # 2. If false, jump to the false-path landing spot (patched at step 5)
    let thenJump = chunk.emitJump(opJumpIfFalse, node.line)
    
    # 3. True path: pop the condition, run 'then'
    chunk.writeChunk(uint8(opPop), node.line)
    c.compile(node.thenBranch, chunk, node.line)
    
    # 4. After 'then' finishes, unconditionally skip over the else branch
    let elseJump = chunk.emitJump(opJump, node.line)
    
    # 5. False path lands here. Pop the condition -- this is the pop that was missing.
    chunk.patchJump(thenJump)
    chunk.writeChunk(uint8(opPop), node.line)
    
    # 6. Compile whatever's in elseBranch, if anything
    if node.elseBranch != nil:
      c.compile(node.elseBranch, chunk, node.line)
      
      # 7. True path lands here, having skipped the else branch entirely
    chunk.patchJump(elseJump)
  of nkCall:
    c.compile(node.callee, chunk, node.line)
    for arg in node.args:
      c.compile(arg, chunk, node.line)
    chunk.writeChunk(uint8(opCall), node.line)
    chunk.writeChunk(node.args.len.uint8, node.line)
    chunk.writeChunk(uint8(opAdjust), node.line)
    chunk.writeChunk(1'u8, node.line)
  of nkBlock:
    for stmt in node.stmts:
      # Compile each statement sequentially into the same chunk
      c.compile(stmt, chunk, node.line)
  of nkExprStmt:
    c.compile(node.expr, chunk, node.line)
    # The expression left a value on the stack.
    # Since we aren't assigning it to anything, pop it!
    chunk.writeChunk(uint8(opPop), node.line)
  of nkFunctionDef:
    # Declare + mark-initialized BEFORE compiling the body, so a local
    # function can see and call itself recursively via resolveUpvalue.
    if not node.isExpr and node.isLocal:
      c.declareVariable(node.fnName)
      c.locals[c.locals.high].depth = c.scopeDepth
      
    var fnChunk = initChunk()
    info "Node name: ", node.fnName
    info "Node vararg: ",node.isVararg
    var luaFn = newLuaClosure(node.fnName, node.params.len, fnChunk,node.isVararg)
    var fnCompiler = newCompiler(luaFn, c)
    
    # 1. Register parameters as local variables
    for param in node.params:
      fnCompiler.declareVariable(param)
      fnCompiler.locals[fnCompiler.locals.high].depth = fnCompiler.scopeDepth
      
      # 2. Compile the function's body into the NEW chunk
    fnCompiler.compile(node.body, fnChunk, node.line)
    if fnCompiler.gotos.len > 0:
      raise newException(LuaCompileError, "no visible label '" & fnCompiler.gotos[0].name & "' for goto")
        # 3. Implicit return (nil)
    let nilIdx = fnChunk.addConstant(newLuaNil())
    fnChunk.writeChunk(uint8(opConstant), node.line)
    fnChunk.writeChunk(nilIdx, node.line)
    fnChunk.writeChunk(uint8(opReturn), node.line)
    fnChunk.writeChunk(1'u8, node.line)
    
    # 4/5. Add function prototype to outer chunk's constant pool
    let constIdx = chunk.addConstant(wrapLuaClosure(luaFn))
    
    # 6. Emit opClosure
    chunk.writeChunk(uint8(opClosure), node.line)
    chunk.writeChunk(constIdx, node.line)
    
    # 7. Emit upvalue metadata
    for uv in fnCompiler.fn.upvalues:
      chunk.writeChunk(if uv.isLocal: 1'u8 else: 0'u8, node.line)
      chunk.writeChunk(uint8(uv.location), node.line)
          
         
    if not node.isExpr:    
      if node.isLocal:
        let localSlot = c.resolveLocal(node.fnName)
        chunk.writeChunk(uint8(opSetLocal), node.line)
        chunk.writeChunk(uint8(localSlot), node.line)
      else:
        let nameIdx = chunk.addConstant(newLuaString(node.fnName))
        chunk.writeChunk(uint8(opSetGlobal), node.line)
        chunk.writeChunk(nameIdx, node.line)
  of nkVararg:
    if isNil(c.fn) or not c.fn.fn.isVararg:
      raise newException(LuaCompileError, "cannot use '...' outside a vararg function")
    chunk.writeChunk(uint8(opVararg),node.line)
  of nkReturn:
    for v in node.retVals:
      c.compile(v, chunk, node.line)
    chunk.writeChunk(uint8(opReturn), node.line)
    chunk.writeChunk(uint8(node.retVals.len), node.line)
  of nkBreak:
    if c.loops.len == 0:
      raise newException(LuaCompileError, "<line " & $node.line & "> break outside loop")
    
    let currentLoop = c.loops[^1]
    
    # Pop local variables declared inside the loop prior to breaking
    for i in countdown(c.locals.high, 0):
      if c.locals[i].depth > currentLoop.scopeDepth:
        if c.locals[i].isCaptured:
          chunk.writeChunk(uint8(opCloseUpvalue), node.line)
        else:
          chunk.writeChunk(uint8(opPop), node.line)
      else:
        break

    # Emit dummy jump to loop end and save location for patching
    let jumpOffset = chunk.emitJump(opJump, node.line)
    c.addBreakJump(jumpOffset)
  of nkTableLiteral:
    # 1. Create a new empty table on the stack
    chunk.writeChunk(uint8(opNewTable), node.line)

    var arrayIndex = 1.0
    for i,field in node.tableFields:
      let isLast = (i == node.tableFields.high)
      if field.key == nil and field.val.kind == nkVararg and isLast:
        # Spread: hand the runtime the starting index: it knows the count.
        chunk.writeChunk(uint8(opSpreadVararg), node.line)
        chunk.writeChunk(uint8(arrayIndex.int), node.line)
        continue  # arrayIndex doesn't matter anymore -- this was the last field
        
      if field.key != nil:
        c.compile(field.key, chunk, node.line)
      else:
        chunk.writeChunk(uint8(opConstant), node.line)
        let constIdx = chunk.addConstant(newLuaNumber(arrayIndex))
        chunk.writeChunk(constIdx, node.line)
        arrayIndex += 1.0
      
      c.compile(field.val, chunk, node.line)
      chunk.writeChunk(uint8(opSetTable), node.line)
  of nkIndexGet:
    # Compile the table expression (pushes table onto stack)
    c.compile(node.getTbl, chunk, node.line)

    # Compile the key expression (pushes key onto stack)
    c.compile(node.getKey, chunk, node.line)

    # Emit the get table instruction
    chunk.writeChunk(uint8(opGetTable), node.line)
  of nkIndexSet:
    c.compile(node.setTbl, chunk, node.line)
    c.compile(node.setKey, chunk, node.line)
    c.compile(node.setValue, chunk, node.line)
    
    chunk.writeChunk(uint8(opSetTable), node.line)
    # Pop the table left behind by opSetTable so the stack remains balanced
    chunk.writeChunk(uint8(opPop), node.line)
  of nkWhileStmt:
    let loopStart = chunk.code.len
    c.compile(node.loopCond, chunk, node.line)
    let exitJump = chunk.emitJump(opJumpIfFalse, node.line)
    chunk.writeChunk(uint8(opPop), node.line)   

    c.addLoop()

    c.beginScope()
    c.compile(node.loopBody, chunk, node.line)
    c.endScope(chunk, node.line)                 

    chunk.emitLoop(loopStart, node.line)
    chunk.patchJump(exitJump)
    chunk.writeChunk(uint8(opPop), node.line)

    let poppedLoop = c.loops.pop()
    for breakJmp in poppedLoop.breakJumps:
      chunk.patchJump(breakJmp)
  of nkNumericFor:
    c.beginScope()

    # --- start ---
    c.compile(node.forStart, chunk, node.line)
    c.addLocal("(for start)")
    c.locals[c.locals.high].depth = c.scopeDepth
    let startSlot = c.locals.high
    chunk.writeChunk(uint8(opSetLocal), node.line)
    chunk.writeChunk(uint8(startSlot), node.line)

    # --- stop ---
    c.compile(node.forStop, chunk, node.line)
    c.addLocal("(for stop)")
    c.locals[c.locals.high].depth = c.scopeDepth
    let stopSlot = c.locals.high
    chunk.writeChunk(uint8(opSetLocal), node.line)
    chunk.writeChunk(uint8(stopSlot), node.line)

    # --- step -- figure out whether we know its sign right now, at compile time ---
    var knownStepSign = 0   # 1 = known ascending, -1 = known descending, 0 = unknown until runtime
    if node.forStep == nil:
      knownStepSign = 1
      let constIndex = chunk.addConstant(newLuaNumber(1.0))
      chunk.writeChunk(uint8(opConstant), node.line)
      chunk.writeChunk(constIndex, node.line)
    elif node.forStep.kind == nkNumber:
      knownStepSign = (if node.forStep.nval < 0: -1 else: 1)
      c.compile(node.forStep, chunk, node.line)
    else:
      c.compile(node.forStep, chunk, node.line)   # sign genuinely unknown until this runs

    c.addLocal("(for step)")
    c.locals[c.locals.high].depth = c.scopeDepth
    let stepSlot = c.locals.high
    chunk.writeChunk(uint8(opSetLocal), node.line)
    chunk.writeChunk(uint8(stepSlot), node.line)

  # --- the loop variable itself, seeded from "start" -- this was the missing piece ---
    chunk.writeChunk(uint8(opGetLocal), node.line)
    chunk.writeChunk(uint8(startSlot), node.line)
    c.addLocal(node.forVar)
    c.locals[c.locals.high].depth = c.scopeDepth
    let loopVarSlot = c.locals.high
    chunk.writeChunk(uint8(opSetLocal), node.line)
    chunk.writeChunk(uint8(loopVarSlot), node.line)

    let loopStart = chunk.code.len

    if knownStepSign != 0:
      # sign known -- exactly one comparison, no runtime branch at all
      chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(loopVarSlot), node.line)
      chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(stopSlot), node.line)
      chunk.writeChunk(uint8(if knownStepSign > 0: opLessEqual else: opGreaterEqual), node.line)
    else:
      # sign unknown -- check step's sign at runtime, then pick the matching comparison
      chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(stepSlot), node.line)
      let zeroIdx = chunk.addConstant(newLuaNumber(0.0))
      chunk.writeChunk(uint8(opConstant), node.line); chunk.writeChunk(zeroIdx, node.line)
      chunk.writeChunk(uint8(opGreaterEqual), node.line)
      let descJump = chunk.emitJump(opJumpIfFalse, node.line)
      chunk.writeChunk(uint8(opPop), node.line)
      chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(loopVarSlot), node.line)
      chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(stopSlot), node.line)
      chunk.writeChunk(uint8(opLessEqual), node.line)
      let skipDesc = chunk.emitJump(opJump, node.line)
      chunk.patchJump(descJump)
      chunk.writeChunk(uint8(opPop), node.line)
      chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(loopVarSlot), node.line)
      chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(stopSlot), node.line)
      chunk.writeChunk(uint8(opGreaterEqual), node.line)
      chunk.patchJump(skipDesc)

    let exitJump = chunk.emitJump(opJumpIfFalse, node.line)
    chunk.writeChunk(uint8(opPop), node.line)
    c.addLoop()
    c.beginScope()
    c.compile(node.forBody, chunk, node.line)
    c.endScope(chunk, node.line)
    
    # loopVar += step
    chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(loopVarSlot), node.line)
    chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(stepSlot), node.line)
    chunk.writeChunk(uint8(opAdd), node.line)
    chunk.writeChunk(uint8(opSetLocal), node.line); chunk.writeChunk(uint8(loopVarSlot), node.line)

    chunk.emitLoop(loopStart, node.line)
    chunk.patchJump(exitJump)
    chunk.writeChunk(uint8(opPop), node.line)
    c.endScope(chunk, node.line)
    let poppedLoop = c.loops.pop()
    for breakJmp in poppedLoop.breakJumps:
      chunk.patchJump(breakJmp)
  of nkLabel:
    for l in c.labels:
      if l.name == node.labelName and l.scopeDepth == c.scopeDepth:
        raise newException(LuaCompileError, "label '" & node.labelName & "' already defined in scope")

    let labelPc = chunk.code.len
    c.labels.add(LabelSymbol(name: node.labelName, pc: labelPc, scopeDepth: c.scopeDepth))

    # Resolve any pending forward gotos targeting this label
    var i = c.gotos.len - 1
    while i >= 0:
      if c.gotos[i].name == node.labelName:
        let g = c.gotos[i]
        if g.scopeDepth < c.scopeDepth:
          raise newException(LuaCompileError, "goto '" & g.name & "' jumps into local scope")
        chunk.patchJump(g.pc)
        c.gotos.delete(i)
      dec i

  of nkGoto:
    var targetIdx = -1
    for i in countdown(c.labels.high, 0):
      if c.labels[i].name == node.labelName:
        targetIdx = i
        break

    if targetIdx != -1: # Backward jump
      let target = c.labels[targetIdx]
      # Pop scope locals created between jump and label
      for idx in countdown(c.locals.high, 0):
        if c.locals[idx].depth > target.scopeDepth:
          if c.locals[idx].isCaptured:
            chunk.writeChunk(uint8(opCloseUpvalue), node.line)
          else:
            chunk.writeChunk(uint8(opPop), node.line)
        else:
          break

      chunk.emitLoop(target.pc, node.line)
    else: # Forward jump
      let jumpOffset = chunk.emitJump(opJump, node.line)
      c.gotos.add(PendingGoto(name: node.labelName, pc: jumpOffset, scopeDepth: c.scopeDepth, line: node.line))
  of nkMultiLocalDecl, nkMultiGlobalDecl:
    let n = node.varNames.len
    let m = node.values.len

    for i, expr in node.values:
      if i == m - 1 and expr.kind == nkCall:
        let remaining = max(1, n - i)
        c.compile(expr.callee, chunk, node.line)
        for arg in expr.args: c.compile(arg, chunk, node.line)
        chunk.writeChunk(uint8(opCall), node.line)
        chunk.writeChunk(expr.args.len.uint8, node.line)
        chunk.writeChunk(uint8(opAdjust), node.line)
        chunk.writeChunk(uint8(remaining), node.line)
      else:
        c.compile(expr, chunk, node.line)

        if m < n and (m == 0 or node.values[^1].kind != nkCall):
          for i in m ..< n:
            let nilIdx = chunk.addConstant(newLuaNil())
            chunk.writeChunk(uint8(opConstant), node.line)
            chunk.writeChunk(nilIdx, node.line)

        var slots: seq[int] = @[]
        if node.kind == nkMultiLocalDecl:
          for name in node.varNames:
            c.declareVariable(name)
            c.locals[c.locals.high].depth = c.scopeDepth
            slots.add(c.locals.high)

        for i in countdown(node.varNames.high, 0):
          if node.kind == nkMultiLocalDecl:
            chunk.writeChunk(uint8(opSetLocal), node.line)
            chunk.writeChunk(uint8(slots[i]), node.line)
          else:
            let nameIdx = chunk.addConstant(newLuaString(node.varNames[i]))
            chunk.writeChunk(uint8(opSetGlobal), node.line)
            chunk.writeChunk(nameIdx, node.line)
  of nkGenericFor:
    c.beginScope()

    let n = 3   # generator, state, initial control
    let m = node.iterExprs.len
    for i, expr in node.iterExprs:
      if i == m - 1 and expr.kind == nkCall:
        let remaining = max(1, n - i)
        c.compile(expr.callee, chunk, node.line)
        for arg in expr.args: c.compile(arg, chunk, node.line)
        chunk.writeChunk(uint8(opCall), node.line)
        chunk.writeChunk(expr.args.len.uint8, node.line)
        chunk.writeChunk(uint8(opAdjust), node.line)
        chunk.writeChunk(uint8(remaining), node.line)
      else:
        c.compile(expr, chunk, node.line)
    if m < n and (m == 0 or node.iterExprs[^1].kind != nkCall):
      for i in m ..< n:
        let nilIdx = chunk.addConstant(newLuaNil())
        chunk.writeChunk(uint8(opConstant), node.line)
        chunk.writeChunk(nilIdx, node.line)

    # 1. Register the 3 hidden iterator variables
    c.addLocal("(generator)")
    c.locals[^1].depth = c.scopeDepth
    let genSlot = c.locals.high

    c.addLocal("(state)")
    c.locals[^1].depth = c.scopeDepth
    let stateSlot = c.locals.high

    c.addLocal("(control)")
    c.locals[^1].depth = c.scopeDepth
    let controlSlot = c.locals.high

    # 2. Register explicit loop variables (k, v) BEFORE loop entry and push placeholders
    var varSlots = newSeq[int]()
    for varName in node.loopVars:
      c.addLocal(varName)
      c.locals[^1].depth = c.scopeDepth
      varSlots.add(c.locals.high)
      let nilIdx = chunk.addConstant(newLuaNil())
      chunk.writeChunk(uint8(opConstant), node.line)
      chunk.writeChunk(nilIdx, node.line)

    let loopStart = chunk.code.len
    
    # 3. Call generator: (generator)((state), (control))
    chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(genSlot), node.line)
    chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(stateSlot), node.line)
    chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(controlSlot), node.line)
    
    chunk.writeChunk(uint8(opCall), node.line)
    chunk.writeChunk(2'u8, node.line)
    chunk.writeChunk(uint8(opAdjust), node.line)
    chunk.writeChunk(uint8(node.loopVars.len), node.line)

    # 4. Pop returned values from top of stack into varSlots in reverse order
    for i in countdown(varSlots.high, 0):
      chunk.writeChunk(uint8(opSetLocal), node.line)
      chunk.writeChunk(uint8(varSlots[i]), node.line)

    # 5. Loop exit check: stop if control var (first loop var) is nil
    let firstVarSlot = varSlots[0]
    chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(firstVarSlot), node.line)
    
    let nilIdx = chunk.addConstant(newLuaNil())
    chunk.writeChunk(uint8(opConstant), node.line); chunk.writeChunk(nilIdx, node.line)
    chunk.writeChunk(uint8(opNotEqual), node.line)
    
    let exitJump = chunk.emitJump(opJumpIfFalse, node.line)
    chunk.writeChunk(uint8(opPop), node.line)

    # 6. Update hidden control variable for next iteration
    chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(firstVarSlot), node.line)
    chunk.writeChunk(uint8(opSetLocal), node.line); chunk.writeChunk(uint8(controlSlot), node.line)

    # 7. Execute loop body
    c.addLoop()
    c.beginScope()
    c.compile(node.genericBody, chunk, node.line)
    c.endScope(chunk, node.line)

    chunk.emitLoop(loopStart, node.line)
    chunk.patchJump(exitJump)
    chunk.writeChunk(uint8(opPop), node.line)

    let poppedLoop = c.loops.pop()
    for breakJmp in poppedLoop.breakJumps:
      chunk.patchJump(breakJmp)

    c.endScope(chunk, node.line)
  else: raise newException(LuaCompileError,"Kind not handled: " & $node.kind)

proc newVM*(): VM =
  # We pre-allocate a reasonable stack size to avoid constant memory reallocations
  VM(ip: 0, stack: newSeqOfCap[LuaValue](256))

proc push*(vm: var VM, value: LuaValue) =
  vm.stack.add(value)

proc pop*(vm: var VM): LuaValue =
  return vm.stack.pop()

proc peek*(vm: VM, distance: int): LuaValue = vm.stack[vm.stack.len - 1 - distance]

proc chunk(cf: CallFrame): Chunk = cf.closure.fn.chunk
  # We define a helper macro or proc to read a byte and advance the IP
proc readByte(vm: var VM): uint8 =
  let frameIp = vm.frames[^1].ip
  result = vm.frames[^1].chunk().code[frameIp]
  inc(vm.frames[^1].ip)
  

proc readShort(vm: var VM): uint16 =
  let frameIp = vm.frames[^1].ip
  let highByte = uint16(vm.frames[^1].chunk.code[frameIp])
  let lowByte = uint16(vm.frames[^1].chunk.code[frameIp+1])
  vm.frames[^1].ip += 2
  return (highByte shl 8) or lowByte


# add in metatables later

proc traceInstruction(vm: VM, ip: int, opName: OpCode) =
  if not vm.traceExecution: return

  # 1. Format the stack state
  var stackDump = "["
  for i, val in vm.stack:
    # Assuming your LuaValue has a `$` (to string) operator defined
    debug "Kind: ", val.kind
    stackDump.add($val)
    if i < vm.stack.high: stackDump.add(", ")
  stackDump.add("]")

  # 2. Log the IP, OpCode, and Stack
  # You can cast the uint8 op to your OpCode enum for a readable name

  # Using debug level from std/logging
  debug "IP: ", align($ip, 4), " | OP: ", align($opName, 12), " | Stack: ", stackDump

proc captureUpvalue*(vm: var VM, location: int): LuaUpvalue =
  # 1. Check if an open upvalue already points to this exact stack slot.
  # If it does, reuse it so multiple closures share the same variable reference!
  for uv in vm.openUpvalues:
    if uv.location == location:
      return uv

  # 2. Otherwise, create a new open upvalue pointing to the stack slot
  let createdUv = newUpvalue(location,true)
  vm.openUpvalues.add(createdUv)
  return createdUv

type BinopProc = proc(l,r:float64): float64

template binop(vm:var VM,bop:BinopProc,op:string):untyped =
  let r = vm.pop()
  let l = vm.pop()
  if isNumber(l) and isNumber(r):
    vm.push(newLuaNumber(bop(l.nval,r.nval)))
  else:
    raise newException(LuaRuntimeError,"Cannot perform " & op & " " & $l.kind & " and " & $r.kind)

proc floorDiv(l,r:float64): float64 =
  result = floor(l / r)

proc luaMod(l, r: float64): float64 = l - floor(l / r) * r

proc toInteger(l:float64): int64 =
  let (intPart,fltPart) = splitDecimal(l)
  if fltPart == 0.0:
    return int64(intPart)
  else:
    raise newException(LuaRuntimeError,"Number has no integer representation")

proc band(l,r:float64): float64 = float64(bitand(toInteger(l),toInteger(r)))
proc bor(l,r:float64): float64 = float64(bitor(toInteger(l),toInteger(r)))
proc bxor(l,r:float64): float64 = float64(bitxor(toInteger(l),toInteger(r)))
proc bnot(r:float64): float64 = float64(bitnot(toInteger(r)))
proc `shr`(l,r:float64): float64 = float64(toInteger(l) shr toInteger(r))
proc `shl`(l,r:float64): float64 = float64(toInteger(l) shl toInteger(r))

proc compareEqual(vm:var VM) =
  let r = vm.pop()
  let l = vm.pop()
  vm.push(newLuaBool(l == r))

proc compareNotEqual(vm:var VM) = 
  let r = vm.pop()
  let l = vm.pop()
  vm.push(newLuaBool(not(l == r)))

type CompareProc = proc(l,r:float64): bool

template comparison(vm:var VM,comp:CompareProc):untyped = 
  let r = vm.pop()
  let l = vm.pop()
  if isNumber(l) and isNumber(r):
    vm.push(newLuaBool(comp(l.nval,r.nval)))
  else:
    raise newException(LuaRuntimeError,"Cannot compare " & $l.kind & " and " & $r.kind)

proc greater(l,r:float64): bool = l > r
proc greaterEq(l,r:float64): bool = l >= r

proc concat(vm:var VM) =
  let r = vm.pop()
  let l = vm.pop()
  if isString(l) and isString(r):
    vm.push(newLuaString(l.sval & r.sval))
  else:
    raise newException(LuaRuntimeError,"Cannot concat: " & $l.kind & " and " & $r.kind)

proc run*(vm: var VM,stopDepth:int = 0): int =
  # The giant loop
  while vm.frames.len > stopDepth:
    
    var frame = vm.frames[^1]
    let instruction = OpCode(vm.readByte())
 
    vm.traceInstruction(frame.ip, instruction)
    case instruction
    of opPop:
      discard vm.pop()
    of opConstant:
      let constIndex = vm.readByte()
      let val = frame.chunk.constants[constIndex]
      vm.push(val)

    of opAdd:
      vm.binop(`+`,"addition")
    of opSubtract:
      vm.binop(`-`,"subtraction")
    of opMultiply: 
      vm.binop(`*`,"multiplication")
    of opDivide:
      vm.binop(`/`,"division")
      # Inside the VM's main case statement:
    of opFloorDiv:
      vm.binop(floorDiv,"floor division")
    of opModulo:
      vm.binop(luaMod,"modulus")
    of opExponent:
      vm.binop(`pow`,"exponentiation")
    of opBitAnd:
      vm.binop(band,"bitwise and")
    of opBitOr:
      vm.binop(bor,"bitwise or")
    of opBitXor:
      vm.binop(bxor,"bitwise exclusive or")
    of opShl:
      vm.binop(`shl`,"left shift")
    of opShr:
      vm.binop(`shr`,"right shift")
    of opEquals:
      vm.compareEqual()
    of opNotEqual:
      vm.compareNotEqual()
    of opLess:
      vm.comparison(`<`)
    of opLessEqual:
      vm.comparison(`<=`)
    of opGreater:
      vm.comparison(greater)
    of opGreaterEqual:
      vm.comparison(greaterEq)
    of opConcat:
      vm.concat()
    of opNot:
      let r = vm.pop()
      vm.push(newLuaBool(not truthy(r)))
    of opNegate:
      let r = vm.pop()
      if isNumber(r):
        vm.push(newLuaNumber(-r.nval))
      else:
        raise newException(LuaRuntimeError,"Cannot negate " & $r.kind)
    of opBitNot:
      let r = vm.pop()
      if isNumber(r):
        vm.push(newLuaNumber(bnot(r.nval)))
      else:
        raise newException(LuaRuntimeError,"Cannot perform bitwise not on " & $r.kind)
    of opLen:
      let r = vm.pop()
      if isTable(r):
        vm.push(newLuaNumber(len(r.tval).float64))
      elif isString(r):
        vm.push(newLuaNumber(len(r.sval).float64))
      else:
        raise newException(LuaRuntimeError,"Cannnot get the length of " & $r.kind)
    of opGetLocal:
      let slot = vm.readByte()
      vm.push(vm.stack[frame.slotBase + int(slot)])

    of opSetLocal:
      let slot = vm.readByte()
      let idx = frame.slotBase + int(slot)
      let val = vm.pop()
      if idx >= vm.stack.len:
        vm.stack.add(val)      # first time this slot is created
      else:
        vm.stack[idx] = val 
    of opGetGlobal:
      let nameIdx = int(vm.readByte())

  # CRITICAL: Read from the current function's chunk, NOT vm.chunk
  # (Adjust "closure.chunk" to match whatever your CallFrame/Function struct uses)
      let constant = frame.closure.chunk().constants[nameIdx]

      if constant.kind != ltString:
        raise newException(LuaRuntimeError, "Expected string constant for global name!")

      let name = constant.sval
      if vm.globals.hasKey(name):
        vm.push(vm.globals[name])
      else:
        vm.push(newLuaNil()) # Lua returns nil for missing globals

    of opSetGlobal:
      let nameIdx = vm.readByte()
      let name = frame.chunk.constants[nameIdx]
      if name.kind != ltString:
        raise newException(LuaRuntimeError, "Expected string constant for global name at index " & $nameIdx & " but got kind " & $name.kind)
      let val = vm.pop() # Pop the value being assigned
      vm.globals[name.sval] = val
    of opNewTable:
      vm.stack.add(newLuaTable())

    of opGetTable:
      let key = vm.pop()
      let tblVal = vm.pop()
      vm.push(luaIndexGet(tblVal, key))

    of opSetTable:
      let val = vm.pop()
      let key = vm.pop()
      let tblVal = vm.stack[^1]
      if tblVal.kind != ltTable:
        raise newException(LuaRuntimeError, "Attempt to index a " & $tblVal.kind & " value")
      if key.kind == ltNil:
        raise newException(LuaRuntimeError, "Table index is nil")
      luaIndexSet(tblVal, key, val)
    of opCall:
      let argCount = int(vm.readByte())
      # --- DUMP ENTIRE STACK ---
      let fnIndex = vm.stack.len - argCount - 1

      let callee = vm.stack[fnIndex]


      if callee.kind == ltClosure:

        let luaFn = callee.fnVal

        var varargTable = newLuaTable()
        if luaFn.fn.isVararg:
          let extraCount = max(0, argCount - luaFn.fn.arity)
          for i in 0 ..< extraCount:
            # Grab extra args off the stack (Lua tables are conventionally 1-indexed)
            let argVal = vm.stack[fnIndex + 1 + luaFn.fn.arity + i]
            varargTable.tval[newLuaNumber(float64(i + 1))] = argVal

        if argCount > luaFn.fn.arity:
          # Trim excess arguments off the stack so slotBase stays perfectly aligned
          vm.stack.setLen(fnIndex + 1 + luaFn.fn.arity)
        elif argCount < luaFn.fn.arity:
          # Pad missing named arguments with nil
          let missing = luaFn.fn.arity - argCount
          for _ in 0 ..< missing: vm.push(newLuaNil())
        if argCount != luaFn.fn.arity and not luaFn.fn.isVararg:
          debug luaFn.fn.name
          debug "Not vararg: ",luaFn.fn.isVararg
          raise newException(LuaRuntimeError, "Expected " &
              $luaFn.fn.arity & " args but got " & $argCount)

        let newFrame = CallFrame(
          closure: luaFn,
          ip: 0,
          slotBase: fnIndex, 
          vararg: varargTable
        )

        vm.frames.add(newFrame)

      elif callee.kind == ltNativeFn:
        var args = newSeq[LuaValue](argCount)
        for i in countdown(argCount - 1, 0): args[i] = vm.pop()
        discard vm.pop()
        let results = callee.nativeFn(args)
        for r in results: vm.push(r)
        vm.lastReturnCount = results.len
      elif callee.kind == ltNativeFnVM:
        var args = newSeq[LuaValue](argCount)
        for i in countdown(argCount - 1, 0): args[i] = vm.pop()
        discard vm.pop()
        let results = callee.nativeFnVM(vm, args)
        for r in results: vm.push(r)
        vm.lastReturnCount = results.len

      else:
        raise newException(LuaRuntimeError, "Attempt to call a non-function value!")

    of opReturn:
      let n = int(vm.readByte())
      discard vm.frames.pop()
      var results = newSeq[LuaValue](n)
      for i in countdown(n - 1, 0):
        results[i] = vm.pop()
      vm.closeUpvalues(frame.slotBase)
      vm.lastReturnCount = n
      vm.stack.setLen(frame.slotBase)
      for r in results: vm.stack.add(r)
      if vm.frames.len == stopDepth:
        return 0
    of opJumpIfFalse:
      let offset = vm.readShort()
      let conditionVal = vm.peek(0) # Look at top of stack WITHOUT popping i
                                    # In Lua, only `false` and `nil` are falsy. Everything else is true.
      let isTruthy = not (conditionVal.kind == ltNil or
                         (conditionVal.kind == ltBool and conditionVal.bval == false))
      if not isTruthy:
        # If it's false, we take the jump!
        let frameCount = vm.frames.len
        vm.frames[frameCount - 1].ip += int(offset)

    of opJump:
      let offset = vm.readShort()
      let frameCount = vm.frames.len
      vm.frames[frameCount - 1].ip += int(offset)
    of opGetUpvalue:
      let slot = vm.readByte()
      let uv = frame.closure.upvalues[int(slot)]
      if uv.isOpen:
        vm.push(vm.stack[uv.location])   # still live on the stack
      else:
        vm.push(uv.closed)               # promoted to the heap

    of opSetUpvalue:
      let slot = vm.readByte()
      let uv = frame.closure.upvalues[int(slot)]
      let val = vm.pop()
      if uv.isOpen:
        vm.stack[uv.location] = val
      else:
        uv.closed = val

    of opClosure:
      let constIdx = vm.readByte()
      # Retrieve the function   prototype/template from the constant pool
      let protoVal = frame.chunk.constants[int(constIdx)]
      let protoClosure = protoVal.fnVal # Assumes ltClosure holds closureVal
      
      # Create a new runtime closure instance sharing the function prototype
      var runtimeClosure = LuaClosure(fn: protoClosure.fn, upvalues: @[])
      
      # Read the upvalue metadata emitted right after opClosure in the bytecode
      let upvalueCount = protoClosure.upvalues.len
      for i in 0 ..< upvalueCount:
        let isLocal = vm.readByte()
        let index = vm.readByte()
        
        if isLocal == 1:
          # Capture a local variable from the current stack frame
          let location = frame.slotBase + int(index)
          runtimeClosure.upvalues.add(vm.captureUpvalue(location))
        else:
          # Pass down an existing upvalue from the enclosing closure
          runtimeClosure.upvalues.add(frame.closure.upvalues[int(index)])
          
      vm.push(wrapLuaClosure(runtimeClosure))
    of opCloseUpvalue:
      vm.closeUpvalues(vm.stack.high)
      discard vm.pop()
    of opVararg:
      vm.push(frame.vararg)
    of opSpreadVararg:
      let startIdx = int(vm.readByte())
      let tbl = vm.peek(0)
      if tbl.kind != ltTable:
        raise newException(LuaRuntimeError, "opSpreadVararg: expected table under construction")
      let count = frame.vararg.tval.len
      for i in 1 .. count:
        let val = frame.vararg.tval[newLuaNumber(float64(i))]
        tbl.tval[newLuaNumber(float64(startIdx + i - 1))] = val
    of opLoop:
      let offset = vm.readShort()
      frame.ip -= int(offset)
    of opAdjust:
      let want = int(vm.readByte())
      let have = vm.lastReturnCount
      if have > want:
        vm.stack.setLen(vm.stack.len - (have - want))
      elif have < want:
        for i in 0 ..< (want - have):
          vm.push(newLuaNil())
          
