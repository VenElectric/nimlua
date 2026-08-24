import std/[tables,logging]
import lparse, llex, lvalue, lerror, ltypes

proc compile*(c: var Compiler, node: Node, chunk: var Chunk, line: int)

proc newLocal(name: string, depth: int, isCaptured: bool): Local = Local(
    name: name, depth: depth, isCaptured: isCaptured)

proc newCompiler*(fn: LuaClosure = nil, enclosing: Compiler = nil): Compiler =
  result = Compiler(locals: @[], scopeDepth: 0, enclosing: enclosing, fn: fn)
  result.locals.add(newLocal("", 0, false))
  if enclosing == nil:
    result.locals.add(newLocal("_ENV", 0, false))

proc beginScope(c: var Compiler) =
  inc(c.scopeDepth)

proc emitScopeCleanup(c: Compiler, chunk: var Chunk, targetDepth: int, line: int) =
  var i = c.locals.high
  while i >= 0 and c.locals[i].depth > targetDepth:
    if c.locals[i].isClosed:
      chunk.writeChunk(uint8(opCloseValue), line)
      chunk.writeChunk(uint8(i), line)
    elif c.locals[i].isCaptured:
      chunk.writeChunk(uint8(opCloseUpvalue), line)
    else:
      chunk.writeChunk(uint8(opPop), line)
    dec i

proc endScope(c: var Compiler, chunk: var Chunk, line: int) =
  dec(c.scopeDepth)
  c.emitScopeCleanup(chunk, c.scopeDepth, line)
  while c.locals.len > 0 and c.locals[^1].depth > c.scopeDepth:
    discard c.locals.pop()

proc addLocal(c: var Compiler, name: string) =
  if c.locals.len == int(uint8.high):
    raise newException(LuaCompileError, "Too many local variables in function")

  c.locals.add(Local(name: name, depth: c.scopeDepth, isCaptured: false))

proc addLoop(c: var Compiler) =
  c.loops.add(LoopContext(scopeDepth: c.scopeDepth, breakJumps: @[]))

proc addBreakJump(c: var Compiler, offset: int) =
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

proc addUpvalue(c: var Compiler, index: int, isLocal: bool,
    isConst: bool): int =
  for i, uv in c.fn.upvalues:
    if uv.location == index and uv.isLocal == isLocal:
      return i
  if len(c.fn.upvalues) > int(high(uint8)):
    raise newException(LuaCompileError, "Too many closure variables in function")

  c.fn.upvalues.add(newUpValue(nil, index, isLocal))
  c.upvalues.add(CompilerUpvalue(index: uint8(index), isLocal: isLocal,
      isConst: isConst))
  return c.fn.upvalues.len - 1

proc captureUpvalue*(vm: var VM, location: int): LuaUpvalue =
  for uv in vm.stack.openUpvalues:
    if uv.isOpen and uv.location == location: return uv
  result = LuaUpvalue(isOpen: true, stack: vm.stack, location: location)
  vm.stack.openUpvalues.add(result)

proc closeUpvalues*(vm: var VM, threshold: int) =
  var kept: seq[LuaUpvalue] = @[]
  for uv in vm.stack.openUpvalues:
    if uv.isOpen and uv.location >= threshold:
      uv.closed = vm.stack.values[uv.location]
      uv.isOpen = false
      uv.stack = nil          # drop the reference; it's heap-resident now
    else:
      kept.add(uv)
  vm.stack.openUpvalues = kept

proc resolveUpvalue(c: var Compiler, name: string): int =
  if c.enclosing == nil:
    return -1
  let localIdx = c.enclosing.resolveLocal(name)
  if localIdx != -1:
    let isConst = c.enclosing.locals[localIdx].isConst
    c.enclosing.locals[localIdx].isCaptured = true   # <-- add this
    return c.addUpvalue(localIdx, true, isConst)
  let outerUpvalueIdx = c.enclosing.resolveUpvalue(name)
  if outerUpvalueIdx != -1:
    let isConst = c.enclosing.upvalues[outerUpvalueIdx].isConst
    return c.addUpvalue(outerUpvalueIdx, false, isConst)
  return -1

proc resolveEnvSlot(c: var Compiler, chunk: var Chunk, line: int) =
  let envLocal = c.resolveLocal("_ENV")
  if envLocal > -1:
    chunk.writeChunk(uint8(opGetLocal), line)
    chunk.writeChunk(uint8(envLocal), line)
    return
  let envUpval = c.resolveUpvalue("_ENV")
  if envUpval > -1:
    chunk.writeChunk(uint8(opGetUpvalue), line)
    chunk.writeChunk(uint8(envUpval), line)
    return
  raise newException(LuaCompileError, "no _ENV visible (internal error -- every chunk should have one)")

proc compileValueOrNil(c: var Compiler, valueNode: Node, chunk: var Chunk, line: int) =
  if not isNil(valueNode): c.compile(valueNode, chunk, line)
  else:
    let nilIdx = chunk.addConstant(newLuaNil())
    chunk.writeChunk(uint8(opConstant), line)
    chunk.writeChunk(nilIdx, line)

proc emitLoop(chunk: var Chunk, loopStart: int, line: int) =
  chunk.writeChunk(uint8(opLoop), line)
  let distance = chunk.code.len - loopStart + 2 # +2 for the two bytes about to be written
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
  of nkInteger:
    let luaInt = newLuaInteger(node.ival)
    let constIndex = chunk.addConstant(luaInt)
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
      else: raise newException(LuaCompileError, "Invalid op: " & $op)

    chunk.writeChunk(uint8(i), node.line)
  of nkUnaryOp:
    c.compile(node.right, chunk, node.line)
    let op = node.op
    let i = case op
      of tkNot: opNot
      of tkMinus: opNegate
      of tkTilde: opBitNot
      of tkHash: opLen
      else: raise newException(LuaCompileError, "Invalid unary op: " & $op)

    chunk.writeChunk(uint8(i), node.line)
  of nkAnd:
    c.compile(node.left, chunk, node.line)
    let shortCircuit = chunk.emitJump(opJumpIfFalse,
        node.line) # left is falsy -> skip right entirely, left stays on stack
    chunk.writeChunk(uint8(opPop), node.line) # left was truthy -> discard it, evaluate right instead
    c.compile(node.right, chunk, node.line)
    chunk.patchJump(shortCircuit)
  of nkOr:
    c.compile(node.left, chunk, node.line)
    let elseJump = chunk.emitJump(opJumpIfFalse, node.line) # left falsy -> go evaluate right
    let endJump = chunk.emitJump(opJump,
        node.line) # left truthy -> skip straight past right, left stays as result
    chunk.patchJump(elseJump)
    chunk.writeChunk(uint8(opPop), node.line) # left was falsy -> only now do we discard it
    c.compile(node.right, chunk, node.line)
    chunk.patchJump(endJump)
  of nkIdent:
    let localSlot = c.resolveLocal(node.name)
    if localSlot > -1:
      chunk.writeChunk(uint8(opGetLocal), node.line)
      chunk.writeChunk(uint8(localSlot), node.line)
    else:
      let upvalueSlot = c.resolveUpvalue(node.name)
      if upvalueSlot > -1:
        chunk.writeChunk(uint8(opGetUpvalue), node.line)
        chunk.writeChunk(uint8(upvalueSlot), node.line)
      else:
        c.resolveEnvSlot(chunk, node.line)
        let nameIdx = chunk.addConstant(newLuaString(node.name))
        chunk.writeChunk(uint8(opConstant), node.line)
        chunk.writeChunk(nameIdx, node.line)
        chunk.writeChunk(uint8(opGetTable), node.line)
  of nkAssign:
    if laLocal in node.attrs:
      c.compileValueOrNil(node.value, chunk, node.line)
      c.addLocal(node.varName)
      let localIdx = c.locals.len - 1
      if laConst in node.attrs: c.locals[localIdx].isConst = true
      if laClose in node.attrs: c.locals[localIdx].isClosed = true
      chunk.writeChunk(uint8(opSetLocal), node.line)
      chunk.writeChunk(uint8(localIdx), node.line)

    elif laGlobal in node.attrs:
    # `global` ALWAYS routes through _ENV, ignoring any local/upvalue shadow
      c.resolveEnvSlot(chunk, node.line)
      let nameIdx = chunk.addConstant(newLuaString(node.varName))
      chunk.writeChunk(uint8(opConstant), node.line)
      chunk.writeChunk(nameIdx, node.line)
      c.compileValueOrNil(node.value, chunk, node.line)
      chunk.writeChunk(uint8(opSetTable), node.line)
      chunk.writeChunk(uint8(opPop), node.line)
      if laConst in node.attrs:
        let constNameIdx = chunk.addConstant(newLuaString(node.varName))
        chunk.writeChunk(uint8(opMarkGlobalConst), node.line)
        chunk.writeChunk(constNameIdx, node.line)
    else:
      let localSlot = c.resolveLocal(node.varName)
      if localSlot > -1:
        c.compileValueOrNil(node.value, chunk, node.line)
        if c.locals[localSlot].isConst:
          raise newException(LuaCompileError, "Attempt to reassign constant local '" & node.varName & "'")
        chunk.writeChunk(uint8(opSetLocal), node.line)
        chunk.writeChunk(uint8(localSlot), node.line)
      else:
        let upvalueSlot = c.resolveUpvalue(node.varName)
        if upvalueSlot > -1:
          c.compileValueOrNil(node.value, chunk, node.line)
          if c.upvalues[upvalueSlot].isConst:
            raise newException(LuaCompileError, "Attempt to reassign constant upvalue '" & node.varName & "'")
          chunk.writeChunk(uint8(opSetUpvalue), node.line)
          chunk.writeChunk(uint8(upvalueSlot), node.line)
        else:
          if c.globals.hasKey(node.varName) and c.globals[node.varName]:
            raise newException(LuaCompileError, "Attempt to reassign constant global '" & node.varName & "'")
          c.resolveEnvSlot(chunk, node.line)
          let nameIdx = chunk.addConstant(newLuaString(node.varName))
          chunk.writeChunk(uint8(opConstant), node.line)
          chunk.writeChunk(nameIdx, node.line)
          c.compileValueOrNil(node.value, chunk, node.line)
          chunk.writeChunk(uint8(opSetTable), node.line)
          chunk.writeChunk(uint8(opPop), node.line)
  of nkMultiAssign:
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

    var allLocal = true
    for i in 0 ..< n:
      let attrs = if i < node.mAttrs.len: node.mAttrs[i] else: {}
      if laLocal notin attrs:
        allLocal = false
        break

    if allLocal:
    # Values already sit exactly where addLocal's sequential numbering expects
    # them -- forward order, no opSetLocal needed, nothing has to move.
      for i in 0 ..< n:
        let attrs = if i < node.mAttrs.len: node.mAttrs[i] else: {}
        c.addLocal(node.varNames[i])
        let localIdx = c.locals.len - 1
        if laConst in attrs: c.locals[localIdx].isConst = true
        if laClose in attrs: c.locals[localIdx].isClosed = true
    else:
      let baseSlot = c.locals.len

      for i in countdown(n - 1, 0):
        let varName = node.varNames[i]
        let attrs = if i < node.mAttrs.len: node.mAttrs[i] else: {}
        let valueSlot = baseSlot + i

        if laLocal in attrs:
          c.addLocal(varName)
          let localIdx = c.locals.len - 1
          if laConst in attrs: c.locals[localIdx].isConst = true
          if laClose in attrs: c.locals[localIdx].isClosed = true
          chunk.writeChunk(uint8(opSetLocal), node.line)
          chunk.writeChunk(uint8(localIdx), node.line)

        elif laGlobal in attrs:
          c.resolveEnvSlot(chunk, node.line)
          let nameIdx = chunk.addConstant(newLuaString(varName))
          chunk.writeChunk(uint8(opConstant), node.line)
          chunk.writeChunk(nameIdx, node.line)
          chunk.writeChunk(uint8(opGetLocal), node.line)
          chunk.writeChunk(uint8(valueSlot), node.line)
          chunk.writeChunk(uint8(opSetTable), node.line)
          chunk.writeChunk(uint8(opPop), node.line)
          if laConst in attrs:
            let constNameIdx = chunk.addConstant(newLuaString(varName))
            chunk.writeChunk(uint8(opMarkGlobalConst), node.line)
            chunk.writeChunk(constNameIdx, node.line)

        else:
          let localSlot = c.resolveLocal(varName)
          if localSlot > -1:
            if c.locals[localSlot].isConst:
              raise newException(LuaCompileError, "Attempt to reassign constant local '" & varName & "'")
            chunk.writeChunk(uint8(opGetLocal), node.line)
            chunk.writeChunk(uint8(valueSlot), node.line)
            chunk.writeChunk(uint8(opSetLocal), node.line)
            chunk.writeChunk(uint8(localSlot), node.line)
          else:
            let upvalueSlot = c.resolveUpvalue(varName)
            if upvalueSlot > -1:
              if c.upvalues[upvalueSlot].isConst:
                raise newException(LuaCompileError, "Attempt to reassign constant upvalue '" & varName & "'")
              chunk.writeChunk(uint8(opGetLocal), node.line)
              chunk.writeChunk(uint8(valueSlot), node.line)
              chunk.writeChunk(uint8(opSetUpvalue), node.line)
              chunk.writeChunk(uint8(upvalueSlot), node.line)
            else:
              if c.globals.hasKey(varName) and c.globals[varName]:
                raise newException(LuaCompileError, "Attempt to reassign constant global '" & varName & "'")
              c.resolveEnvSlot(chunk, node.line)
              let nameIdx = chunk.addConstant(newLuaString(varName))
              chunk.writeChunk(uint8(opConstant), node.line)
              chunk.writeChunk(nameIdx, node.line)
              chunk.writeChunk(uint8(opGetLocal), node.line)
              chunk.writeChunk(uint8(valueSlot), node.line)
              chunk.writeChunk(uint8(opSetTable), node.line)
              chunk.writeChunk(uint8(opPop), node.line)
      for i in 0 ..< n:
        chunk.writeChunk(uint8(opPop), node.line)
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
    let m = node.args.len
    if m > 0 and node.args[^1].kind in {nkCall, nkVararg, nkMethodCall}:
      let prefixCount = m - 1
      for i in 0 ..< prefixCount:
        c.compile(node.args[i], chunk, node.line)
      let last = node.args[^1]
      case last.kind
      of nkCall:
        c.compile(last.callee, chunk, node.line)
        for arg in last.args: c.compile(arg, chunk, node.line)
        chunk.writeChunk(uint8(opCall), node.line)
        chunk.writeChunk(last.args.len.uint8, node.line)
      of nkMethodCall:
        c.compile(last.mcReceiver, chunk, node.line)
        let nameIdx = chunk.addConstant(newLuaString(last.mcMethodName))
        chunk.writeChunk(uint8(opGetMethod), node.line)
        chunk.writeChunk(nameIdx, node.line)
        for arg in last.mcArgs: c.compile(arg, chunk, node.line)
        chunk.writeChunk(uint8(opCall), node.line)
        chunk.writeChunk((last.mcArgs.len + 1).uint8, node.line)
      else: # nkVararg
        if c.fn == nil or not c.fn.fn.isVararg:
          raise newException(LuaCompileError, "cannot use '...' outside a vararg function")
        chunk.writeChunk(uint8(opSpreadVarargValues), node.line)
      chunk.writeChunk(uint8(opCallSpread), node.line)
      chunk.writeChunk(uint8(prefixCount), node.line)
    else:
      for arg in node.args: c.compile(arg, chunk, node.line)
      chunk.writeChunk(uint8(opCall), node.line)
      chunk.writeChunk(m.uint8, node.line)
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
    if not node.isExpr and node.isLocal:
      c.declareVariable(node.fnName)
      c.locals[c.locals.high].depth = c.scopeDepth

    let needsEnvRouting = not node.isExpr and not node.isLocal
    if needsEnvRouting:
      c.resolveEnvSlot(chunk, node.line)
      let preNameIdx = chunk.addConstant(newLuaString(node.fnName))
      chunk.writeChunk(uint8(opConstant), node.line)
      chunk.writeChunk(preNameIdx, node.line)

    var fnChunk = initChunk()
    var luaFn = newLuaClosure(node.fnName, node.params.len, fnChunk, node.isVararg)
    var fnCompiler = newCompiler(luaFn, c)

    # 1. Register parameters as local variables
    for param in node.params:
      fnCompiler.declareVariable(param)
      fnCompiler.locals[fnCompiler.locals.high].depth = fnCompiler.scopeDepth

    fnCompiler.beginScope()
    fnCompiler.compile(node.body, fnChunk, node.line)
    fnCompiler.endScope(fnChunk, node.line)
    if fnCompiler.gotos.len > 0:
      raise newException(LuaCompileError, "no visible label '" &
          fnCompiler.gotos[0].name & "' for goto")
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
        chunk.writeChunk(uint8(opSetTable), node.line)
        chunk.writeChunk(uint8(opPop), node.line)
  of nkVararg:
    if isNil(c.fn) or not c.fn.fn.isVararg:
      raise newException(LuaCompileError, "cannot use '...' outside a vararg function")
    chunk.writeChunk(uint8(opVararg), node.line)
  of nkReturn:
    let m = node.retVals.len
    if m > 0 and node.retVals[^1].kind in {nkCall, nkVararg, nkMethodCall}:
      let prefixCount = m - 1
      for i in 0 ..< prefixCount:
        c.compile(node.retVals[i], chunk, node.line)
      let last = node.retVals[^1]
      case last.kind
      of nkCall:
        c.compile(last.callee, chunk, node.line)
        for arg in last.args: c.compile(arg, chunk, node.line)
        chunk.writeChunk(uint8(opCall), node.line)
        chunk.writeChunk(last.args.len.uint8, node.line)
      of nkMethodCall:
        c.compile(last.mcReceiver, chunk, node.line)
        let nameIdx = chunk.addConstant(newLuaString(last.mcMethodName))
        chunk.writeChunk(uint8(opGetMethod), node.line)
        chunk.writeChunk(nameIdx, node.line)
        for arg in last.mcArgs: c.compile(arg, chunk, node.line)
        chunk.writeChunk(uint8(opCall), node.line)
        chunk.writeChunk((last.mcArgs.len + 1).uint8, node.line)
      else:
        if c.fn == nil or not c.fn.fn.isVararg:
          raise newException(LuaCompileError, "cannot use '...' outside a vararg function")
        chunk.writeChunk(uint8(opSpreadVarargValues), node.line)
      chunk.writeChunk(uint8(opReturnSpread), node.line)
      chunk.writeChunk(uint8(prefixCount), node.line)
    else:
      for v in node.retVals: c.compile(v, chunk, node.line)
      chunk.writeChunk(uint8(opReturn), node.line)
      chunk.writeChunk(uint8(m), node.line)
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
    for i, field in node.tableFields:
      let isLast = (i == node.tableFields.high)
      if field.key == nil and field.val.kind == nkVararg and isLast:
        # Spread: hand the runtime the starting index: it knows the count.
        chunk.writeChunk(uint8(opSpreadVararg), node.line)
        chunk.writeChunk(uint8(arrayIndex.int), node.line)
        continue # arrayIndex doesn't matter anymore -- this was the last field

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

  # --- start / stop / step: unchanged ---
    c.compile(node.forStart, chunk, node.line)
    c.addLocal("(for start)")
    c.locals[c.locals.high].depth = c.scopeDepth
    let startSlot = c.locals.high
    chunk.writeChunk(uint8(opSetLocal), node.line)
    chunk.writeChunk(uint8(startSlot), node.line)

    c.compile(node.forStop, chunk, node.line)
    c.addLocal("(for stop)")
    c.locals[c.locals.high].depth = c.scopeDepth
    let stopSlot = c.locals.high
    chunk.writeChunk(uint8(opSetLocal), node.line)
    chunk.writeChunk(uint8(stopSlot), node.line)

    var knownStepSign = 0
    if isNil(node.forStep):
      knownStepSign = 1
      let constIndex = chunk.addConstant(newLuaInteger(1))
      chunk.writeChunk(uint8(opConstant), node.line)
      chunk.writeChunk(constIndex, node.line)
    elif node.forStep.kind == nkNumber:
      knownStepSign = (if node.forStep.nval < 0: -1 else: 1)
      c.compile(node.forStep, chunk, node.line)
    else:
      c.compile(node.forStep, chunk, node.line)
    c.addLocal("(for step)")
    c.locals[c.locals.high].depth = c.scopeDepth
    let stepSlot = c.locals.high
    chunk.writeChunk(uint8(opSetLocal), node.line)
    chunk.writeChunk(uint8(stepSlot), node.line)

    # --- hidden internal counter -- NOT the user-visible loop variable anymore ---
    chunk.writeChunk(uint8(opGetLocal), node.line)
    chunk.writeChunk(uint8(startSlot), node.line)
    c.addLocal("(for counter)")
    c.locals[c.locals.high].depth = c.scopeDepth
    let counterSlot = c.locals.high
    chunk.writeChunk(uint8(opSetLocal), node.line)
    chunk.writeChunk(uint8(counterSlot), node.line)
    
    let loopStart = chunk.code.len

    if knownStepSign != 0:
      chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(counterSlot), node.line)
      chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(stopSlot), node.line)
      chunk.writeChunk(uint8(if knownStepSign > 0: opLessEqual else: opGreaterEqual), node.line)
    else:
      chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(stepSlot), node.line)
      let zeroIdx = chunk.addConstant(newLuaNumber(0.0))
      chunk.writeChunk(uint8(opConstant), node.line); chunk.writeChunk(zeroIdx, node.line)
      chunk.writeChunk(uint8(opGreaterEqual), node.line)
      let descJump = chunk.emitJump(opJumpIfFalse, node.line)
      chunk.writeChunk(uint8(opPop), node.line)
      chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(counterSlot), node.line)
      chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(stopSlot), node.line)
      chunk.writeChunk(uint8(opLessEqual), node.line)
      let skipDesc = chunk.emitJump(opJump, node.line)
      chunk.patchJump(descJump)
      chunk.writeChunk(uint8(opPop), node.line)
      chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(counterSlot), node.line)
      chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(stopSlot), node.line)
      chunk.writeChunk(uint8(opGreaterEqual), node.line)
      chunk.patchJump(skipDesc)

    let exitJump = chunk.emitJump(opJumpIfFalse, node.line)
    chunk.writeChunk(uint8(opPop), node.line)
    
    c.addLoop()
    c.beginScope()

  # --- NEW: the user-visible loop variable -- a fresh local, every single iteration ---
    chunk.writeChunk(uint8(opGetLocal), node.line)
    chunk.writeChunk(uint8(counterSlot), node.line)
    c.addLocal(node.forVar)
    c.locals[c.locals.high].depth = c.scopeDepth
    let loopVarSlot = c.locals.high
    chunk.writeChunk(uint8(opSetLocal), node.line)
    chunk.writeChunk(uint8(loopVarSlot), node.line)

    c.compile(node.forBody, chunk, node.line)
    c.endScope(chunk, node.line)   # closes THIS iteration's scope -- loopVarSlot included
    
    # counter += step (note: counterSlot, not loopVarSlot -- that's out of scope now)
    chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(counterSlot), node.line)
    chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(stepSlot), node.line)
    chunk.writeChunk(uint8(opAdd), node.line)
    chunk.writeChunk(uint8(opSetLocal), node.line); chunk.writeChunk(uint8(counterSlot), node.line)

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
    c.labels.add(LabelSymbol(name: node.labelName, pc: labelPc,
        scopeDepth: c.scopeDepth))

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
      c.gotos.add(PendingGoto(name: node.labelName, pc: jumpOffset,
          scopeDepth: c.scopeDepth, line: node.line))
  of nkGenericFor:
    c.beginScope()

    let n = 3 # generator, state, initial control
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
    chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(
        genSlot), node.line)
    chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(
        stateSlot), node.line)
    chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(
        controlSlot), node.line)

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
    chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(
        firstVarSlot), node.line)

    let nilIdx = chunk.addConstant(newLuaNil())
    chunk.writeChunk(uint8(opConstant), node.line); chunk.writeChunk(nilIdx, node.line)
    chunk.writeChunk(uint8(opNotEqual), node.line)

    let exitJump = chunk.emitJump(opJumpIfFalse, node.line)
    chunk.writeChunk(uint8(opPop), node.line)

    # 6. Update hidden control variable for next iteration
    chunk.writeChunk(uint8(opGetLocal), node.line); chunk.writeChunk(uint8(
        firstVarSlot), node.line)
    chunk.writeChunk(uint8(opSetLocal), node.line); chunk.writeChunk(uint8(
        controlSlot), node.line)

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
  of nkRepeatStmt:
    let loopStart = chunk.code.len
    c.addLoop() # before the body, so `break` inside it resolves correctly
    c.beginScope()
    c.compile(node.loopBody, chunk, node.line)
    c.compile(node.loopCond, chunk, node.line) # body's locals still visible here

    let targetDepth = c.scopeDepth - 1
    let exitJump = chunk.emitJump(opJumpIfFalse, node.line)

    # condition TRUE (falls through here) -- exit the loop
    chunk.writeChunk(uint8(opPop), node.line)
    c.emitScopeCleanup(chunk, targetDepth, node.line)
    let doneJump = chunk.emitJump(opJump, node.line)

    # condition FALSE -- loop back
    chunk.patchJump(exitJump)
    chunk.writeChunk(uint8(opPop), node.line)
    c.emitScopeCleanup(chunk, targetDepth, node.line)
    chunk.emitLoop(loopStart, node.line)

    chunk.patchJump(doneJump)

  # Only now update the compiler's own bookkeeping -- the bytecode for both
  # paths above is already emitted; this just closes the scope conceptually.
    dec(c.scopeDepth)
    while c.locals.len > 0 and c.locals[^1].depth > c.scopeDepth:
      discard c.locals.pop()

    let poppedLoop = c.loops.pop()
    for breakJmp in poppedLoop.breakJumps:
      chunk.patchJump(breakJmp)
  of nkMethodCall:
    c.compile(node.mcReceiver, chunk, node.line)
    let nameIdx = chunk.addConstant(newLuaString(node.mcMethodName))
    chunk.writeChunk(uint8(opGetMethod), node.line)
    chunk.writeChunk(nameIdx, node.line)
    for arg in node.mcArgs: c.compile(arg, chunk, node.line)
    chunk.writeChunk(uint8(opCall), node.line)
    chunk.writeChunk((node.mcArgs.len + 1).uint8, node.line) # +1 for the injected receiver
    chunk.writeChunk(uint8(opAdjust), node.line)
    chunk.writeChunk(1'u8, node.line)
  of nkDoBlock:
    c.beginScope()
    c.compile(node.doBody, chunk, node.line)
    c.endScope(chunk, node.line)
  else: raise newException(LuaCompileError, "Kind not handled: " & $node.kind)
