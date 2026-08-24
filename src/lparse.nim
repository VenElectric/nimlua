import llex, lerror
from ltypes import ValueAttribute
import std/[strutils, logging]
type
  NodeKind* = enum
    nkNil,
    nkBool,
    nkNumber,
    nkInteger,
    nkString,
    nkIdent,
    nkBinaryOp,
    nkAnd,
    nkOr,
    nkUnaryOp,
    nkIfStmt,
    nkWhileStmt,
    nkRepeatStmt,
    nkCall,
    nkMethodCall,
    nkAssign,
    nkMultiAssign,
    nkBlock,
    nkExprStmt,
    nkFunctionDef,
    nkReturn,
    nkTableLiteral, # e.g., { } or tables with initial values
    nkIndexGet,     # e.g., t[k] or t.field
    nkIndexSet,
    nkVararg,
    nkNumericFor,
    nkGenericFor,
    nkBreak,
    nkGoto,
    nkLabel,
    nkDoBlock
  Node*{.acyclic.} = ref object
    line*: int
    case kind*: NodeKind
    of nkNil, nkVararg, nkBreak: discard
    of nkGoto, nkLabel: labelName*: string
    of nkNumber:
      nval*: float64
    of nkInteger:
      ival*: int64
    of nkString:
      sval*: string
    of nkBool:
      bval*: bool
    of nkIdent:
      name*: string
    of nkBinaryOp, nkUnaryOp, nkAnd, nkOr:
      left*: Node
      right*: Node
      op*: TokenKind         # From our Lexer (e.g., tkPlus, tkStar)
    of nkAssign:
      varName*: string
      value*: Node
      attrs*: set[ValueAttribute]
    of nkWhileStmt, nkRepeatStmt:
      loopCond*: Node
      loopBody*: Node
    of nkIfStmt:
      condition*: Node
      thenBranch*: Node
      elseBranch*: Node
    of nkCall:
      callee*: Node
      args*: seq[Node]
    of nkMethodCall:
      mcReceiver*: Node
      mcMethodName*: string
      mcArgs*: seq[Node]
    of nkBlock:
      stmts*: seq[Node]
    of nkExprStmt:
      expr*: Node
    of nkFunctionDef:
      fnName*: string
      params*: seq[string]
      body*: Node
      isLocal*: bool
      isExpr*: bool
      isVararg*: bool
    of nkReturn:
      retVals*: seq[Node]
    of nkTableLiteral:
      tableFields*: seq[tuple[key: Node, val: Node]]
    of nkIndexGet:
      getTbl*: Node
      getKey*: Node
    of nkIndexSet:
      setTbl*: Node
      setKey*: Node
      setValue*: Node
    of nkNumericFor:
      forVar*: string
      forStart*: Node
      forStop*: Node
      forStep*: Node         # nil if the third `, step` was omitted
      forBody*: Node
    of nkGenericFor:
      loopVars*: seq[string] # E.g., @["k", "v"]
      iterExprs*: seq[Node]  # E.g., the AST for `pairs(t)`
      genericBody*: Node     # The block inside the loop
    of nkMultiAssign:
      varNames*: seq[string]
      values*: seq[Node]
      mAttrs*: seq[set[ValueAttribute]]
    of nkDoBlock:
      doBody*: Node
  LuaParser* = object
    tokens*: seq[Token]
    current*: int


proc newNode(kind: NodeKind, line: int): Node = result = Node(kind: kind, line: line)

proc newNil(line: int): Node = result = newNode(nkNil, line)

proc newBool(v: bool, line: int): Node =
  result = newNode(nkBool, line)
  result.bval = v

proc newNumber(v: float64, line: int): Node =
  result = newNode(nkNumber, line)
  result.nval = v

proc newInteger(v: int64, line: int): Node =
  result = newNode(nkInteger, line)
  result.ival = v

proc newString(v: string, line: int): Node =
  result = newNode(nkString, line)
  result.sval = v

proc newIdent(name: string, line: int): Node =
  result = newNode(nkIdent, line)
  result.name = name

proc newBinop(op: TokenKind, left, right: Node, line: int): Node =
  result = Node(kind: nkBinaryOp, op: op, left: left, right: right, line: line)

proc newAnd(left, right: Node, line: int): Node =
  result = newNode(nkAnd, line)
  result.left = left
  result.right = right

proc newOr(left, right: Node, line: int): Node =
  result = newNode(nkOr, line)
  result.left = left
  result.right = right


proc newUnop(op: TokenKind, right: Node, line: int): Node =
  result = Node(kind: nkUnaryOp, op: op, right: right, line: line)

proc newAssign(name: string, value: Node, attrs: set[ValueAttribute],
    line: int): Node =
  result = newNode(nkAssign, line)
  result.varName = name
  result.value = value
  result.attrs = attrs

proc newCall(callee: Node, line: int): Node =
  result = newNode(nkCall, line)
  result.callee = callee
  result.args = @[]

proc newMethodCall(receiver: Node, methodName: string, line: int): Node =
  result = newNode(nkMethodCall, line)
  result.mcReceiver = receiver
  result.mcMethodName = methodName
  result.mcArgs = @[]

proc newIfStmt(condition, thenBranch: Node, line: int): Node =
  result = newNode(nkIfStmt, line)
  result.condition = condition
  result.thenBranch = thenBranch

proc newWhileStmt(condition, thenBranch: Node, line: int): Node =
  result = newNode(nkWhileStmt, line)
  result.loopCond = condition
  result.loopBody = thenBranch

proc newRepeatStmt(condition, thenBranch: Node, line: int): Node =
  result = newNode(nkRepeatStmt, line)
  result.loopCond = condition
  result.loopBody = thenBranch


proc newBlock(line: int): Node = Node(kind: nkBlock, stmts: @[], line: line)

proc newDoBlock(body: Node, line: int): Node =
  result = newNode(nkDoBlock, line)
  result.doBody = body

proc newExprStmt(expr: Node, line: int): Node = Node(kind: nkExprStmt,
    expr: expr, line: line)

proc newFunctionDef(name: string, params: seq[string], body: Node, line: int,
    isVararg: bool, isLocal: bool = false, isExpr: bool = false): Node =
  result = Node(kind: nkFunctionDef, fnName: name, params: params, body: body,
      isLocal: isLocal, isExpr: isExpr, line: line, isVararg: isVararg)

proc newVararg(line: int): Node = Node(kind: nkVararg, line: line)

proc newReturn(line: int, values: seq[Node] = @[]): Node = Node(kind: nkReturn,
    retVals: values, line: line)

proc newTableLit(fields: seq[tuple[key, val: Node]], line: int): Node =
  result = Node(kind: nkTableLiteral, tableFields: fields, line: line)

proc newTableSet(setTbl, setKey, setValue: Node, line: int): Node =
  result = Node(kind: nkIndexSet, setTbl: setTbl, setKey: setKey,
      setValue: setValue, line: line)

proc newTableGet(getTbl, getKey: Node, line: int): Node =
  result = Node(kind: nkIndexGet, getTbl: getTbl, getKey: getKey, line: line)

proc newNumericFor(firstName:string, startExpr, stopExpr, stepExpr, body:Node, line:int): Node = 
  Node(kind:nkNumericFor,forVar: firstName,forStart: startExpr, forStop: stopExpr,forStep: stepExpr,forBody: body,line: line)

proc newBreak(line: int): Node = newNode(nkBreak, line)

proc newLabel(name: string, line: int): Node =
  result = newNode(nkLabel, line)
  result.labelName = name

proc newGoto(name: string, line: int): Node =
  result = newNode(nkGoto, line)
  result.labelName = name

proc newMultiAssign(names: seq[string], values: seq[Node], attrs: seq[set[
    ValueAttribute]], line: int): Node =
  result = newNode(nkMultiAssign, line)
  result.varNames = names
  result.values = values
  result.mAttrs = attrs

proc newGenericFor(vars: seq[string], exprs: seq[Node], body: Node,
    line: int): Node =
  Node(kind: nkGenericFor, loopVars: vars, iterExprs: exprs, genericBody: body, line: line)

using
  p: LuaParser
  vp: var LuaParser

proc peek(p): Token = p.tokens[p.current]
proc previous(p): Token = p.tokens[p.current - 1]
proc isAtEnd(p): bool = p.peek().kind == tkEOF

proc advance(vp): Token =
  if not vp.isAtEnd(): inc(vp.current)
  return vp.previous()

proc match(vp; kinds: varargs[TokenKind]): bool =
  for kind in kinds:
    if vp.peek().kind == kind:
      discard vp.advance()
      return true
  return false

proc check(p; kind: TokenKind): bool =
  if p.isAtEnd(): return false
  return p.peek().kind == kind

proc consume(vp; kind: TokenKind; errorMsg: string) =
  if not vp.check(kind):
    raise newException(LuaSyntaxError, errorMsg)
  discard vp.advance()

proc parseExpression(vp): Node
proc parsePrimary(vp): Node
proc parseStatement(vp): Node
proc parseBlock*(vp): Node
proc parseBlockUntil(vp; terminators: varargs[TokenKind]): Node
proc parsePow(vp): Node
proc parseUnary(vp): Node
proc parseBinary(vp; minPrec: int): Node

proc finishCall(vp; callee: Node): Node =
  result = newCall(callee, vp.peek().line)

  # Check if there are arguments inside the parentheses
  if not vp.check(tkRightParen):
    while true:
      # Each argument is a full expression (e.g., `1 + 2`)
      result.args.add(vp.parseExpression())

      # If there's no comma, we've parsed the lnk argument
      if not vp.match(tkComma):
        break
  # Ensure the closing parenthesis is present
  vp.consume(tkRightParen, "Expected ')' after function arguments.")


proc parseCall(vp): Node =
  result = vp.parsePrimary()
  while true:
    if vp.match(tkLeftParen):
      result = vp.finishCall(result)
    elif vp.match(tkLeftBracket):
      let keyExpr = vp.parseExpression()
      vp.consume(tkRightBracket, "Expected ']' after index expression.")
      result = newTableGet(result, keyExpr, vp.peek().line)
    elif vp.match(tkDot):
      if not vp.match(tkIdent):
        raise newException(LuaSyntaxError, "Syntax Error: Expected identifier after '.'.")
      let fieldName = vp.previous().lexeme
      let keyExpr = newString(fieldName, vp.peek().line)
      result = newTableGet(result, keyExpr, vp.peek().line)
    elif vp.match(tkColon):
      if not vp.match(tkIdent):
        raise newException(LuaSyntaxError, "Expected method name after ':'.")
      let methodName = vp.previous().lexeme
      let mcLine = vp.peek().line
      vp.consume(tkLeftParen, "Expected '(' after method name.")
      var call = newMethodCall(result, methodName, mcLine)
      if not vp.check(tkRightParen):
        while true:
          call.mcArgs.add(vp.parseExpression())
          if not vp.match(tkComma): break
      vp.consume(tkRightParen, "Expected ')' after method call arguments.")
      result = call
    else:
      break

proc parseFunctionDef(vp; isLocal: bool): Node =
  let lineDef = vp.peek().line
  vp.consume(tkFunction, "Expect function ident")
  if not vp.match(tkIdent):
    raise newException(LuaSyntaxError, "Expected function name.")
  let firstName = vp.previous().lexeme

  var pathNames: seq[string] = @[]
  while vp.match(tkDot):
    if not vp.match(tkIdent):
      raise newException(LuaSyntaxError, "Expected identifier after '.' in function name.")
    pathNames.add(vp.previous().lexeme)

  var isMethod = false
  var methodName = ""
  if vp.match(tkColon):
    if not vp.match(tkIdent):
      raise newException(LuaSyntaxError, "Expected method name after ':'.")
    methodName = vp.previous().lexeme
    isMethod = true

  vp.consume(tkLeftParen, "Expected '(' after function name.")
  var isVararg = false
  var parameters: seq[string] = @[]
  if isMethod: parameters.add("self")
  if not vp.check(tkRightParen):
    while true:
      if vp.match(tkDots):
        isVararg = true
        break
      if not vp.match(tkIdent):
        raise newException(LuaSyntaxError, "Syntax Error: Expected parameter name.")
      parameters.add(vp.previous().lexeme)
      if not vp.match(tkComma):
        break
  vp.consume(tkRightParen, "Expected ')' after parameters.")

  var body = newBlock(vp.peek().line)
  while not vp.check(tkEnd) and not vp.check(tkEOF):
    body.stmts.add(vp.parseStatement())
  vp.consume(tkEnd, "Expected 'end' to close function body.")

  if pathNames.len == 0 and not isMethod:
    return newFunctionDef(firstName, parameters, body, lineDef, isVararg, isLocal)

  if isLocal:
    raise newException(LuaSyntaxError, "'local function' cannot use a dotted or method name.")

  let finalKey = if isMethod: methodName else: pathNames[^1]
  let tblSegments = if isMethod: pathNames else: pathNames[0 ..< pathNames.high]

  var target: Node = newIdent(firstName, lineDef)
  for seg in tblSegments:
    target = newTableGet(target, newString(seg, lineDef), lineDef)

  let displayName = firstName & (if pathNames.len > 0: "." & pathNames.join(".") else: "") &
                     (if isMethod: ":" & methodName else: "")
  let fnVal = newFunctionDef(displayName, parameters, body, lineDef, isVararg,
      false, isExpr = true)

  return newTableSet(target, newString(finalKey, lineDef), fnVal, lineDef)

proc parseWhileStmt(vp): Node =
  let line = vp.peek().line
  vp.consume(tkWhile, "Expect 'while'")
  let cond = vp.parseExpression()
  vp.consume(tkDo, "Expected 'do' after while condition.")
  let body = vp.parseBlockUntil(tkEnd)
  vp.consume(tkEnd, "Expected 'end' to close while loop.")
  return newWhileStmt(cond, body, line)

proc parseRepeatStmt(vp): Node =
  let line = vp.peek().line
  vp.consume(tkRepeat, "Expect 'repeat'")
  let body = vp.parseBlockUntil(tkUntil)
  vp.consume(tkUntil, "Expected 'until' to close repeat loop.")
  let cond = vp.parseExpression()
  return newRepeatStmt(cond, body, line)

proc parseForStmt(vp): Node =
  let line = vp.peek().line
  vp.consume(tkFor, "Expect 'for'")

  if not vp.match(tkIdent):
    raise newException(LuaSyntaxError, "Expected loop variable name after 'for'.")

  # 1. Collect all loop variable names (could be one, could be many)
  var loopVars: seq[string] = @[vp.previous().lexeme]

  while vp.match(tkComma):
    if not vp.match(tkIdent):
      raise newException(LuaSyntaxError, "Expected variable name after ','.")
    loopVars.add(vp.previous().lexeme)

  # 2. Branch: Numeric vs Generic
  if vp.match(tkAssign):
    # Numeric Loop: for i = 1, 10 do
    if loopVars.len > 1:
      raise newException(LuaSyntaxError, "Numeric for loops can only have one loop variable.")

    let startExpr = vp.parseExpression()
    vp.consume(tkComma, "Expected ',' after for-loop start value.")
    let stopExpr = vp.parseExpression()

    var stepExpr: Node
    if vp.match(tkComma):
      stepExpr = vp.parseExpression()

    vp.consume(tkDo, "Expected 'do' after for-loop header.")
    let body = vp.parseBlockUntil(tkEnd)
    vp.consume(tkEnd, "Expected 'end' to close for loop.")

    return newNumericFor(loopVars[0], startExpr, stopExpr, stepExpr, body, line)

  elif vp.match(tkIn):
    # Generic Loop: for k, v in pairs(t) do
    var iterExprs: seq[Node] = @[]
    iterExprs.add(vp.parseExpression())

    # In Lua, you can actually return multiple iterators: for a in f1(), f2() do
    while vp.match(tkComma):
      iterExprs.add(vp.parseExpression())

    vp.consume(tkDo, "Expected 'do' after generic for-loop header.")
    let body = vp.parseBlockUntil(tkEnd)
    vp.consume(tkEnd, "Expected 'end' to close for loop.")

    return newGenericFor(loopVars, iterExprs, body, line)

  else:
    raise newException(LuaSyntaxError, "Expected '=' or 'in' after for loop variables.")

proc parseAttributes(vp: var LuaParser): set[ValueAttribute] =
  result = {}
  # Check if the next token is '<'
  if vp.check(tkLess): # Assuming you have a token kind for '<'
    discard vp.advance() # consume '<'
    let attrToken = vp.peek()
    if attrToken.kind == tkIdent:
      discard vp.advance()
      case attrToken.lexeme
      of "const": result.incl(laConst)
      of "close": result.incl(laClose)
      else: raise newException(LuaSyntaxError, "Unknown attribute '" &
          attrToken.lexeme & "'")
    else:
      raise newException(LuaSyntaxError, "Expected attribute name after '<'")

    # Expect closing '>'
    if not vp.match(tkGreater):
      raise newException(LuaSyntaxError, "Expected '>' after attribute name")

proc parseVarDecl(vp: var LuaParser): Node =
  discard vp.advance()
  let isLocal = vp.previous().kind == tkLocal
  let baseAttr: ValueAttribute = if isLocal: laLocal else: laGlobal

  # Check for `local function ...`
  if vp.peek().kind == tkFunction:
    return vp.parseFunctionDef(isLocal)

  # Expect first variable name
  if not vp.match(tkIdent):
    raise newException(LuaSyntaxError, "Expected variable name after declaration.")

  let firstVarName = vp.previous().lexeme
  var firstAttrs = {baseAttr} + vp.parseAttributes()

  # Check if it's a multi-declaration (contains a comma)
  if vp.peek().kind == tkComma:
    var varNames = @[firstVarName]
    var allAttrs = @[firstAttrs]

    while vp.match(tkComma):
      if not vp.match(tkIdent):
        raise newException(LuaSyntaxError, "Expected variable name after ','.")
      varNames.add(vp.previous().lexeme)
      allAttrs.add({baseAttr} + vp.parseAttributes())

    # Parse multi-assignment values if present
    var values: seq[Node] = @[]
    if vp.match(tkAssign):
      values.add(vp.parseExpression())
      while vp.match(tkComma):
        values.add(vp.parseExpression())

    let line = vp.peek().line
    return newMultiAssign(varNames, values, allAttrs, line)
  else:
    # Single declaration
    var initValue: Node
    if vp.match(tkAssign):
      initValue = vp.parseExpression()

    let line = vp.peek().line
    return newAssign(firstVarName, initValue, firstAttrs, line)

proc parseEnum(vp): Node =
  let line = vp.peek().line
  vp.consume(tkEnum, "Expect 'enum'")
  vp.consume(tkLeftParen, "Expected '(' after 'enum'.")

  var fields: seq[tuple[key: Node, val: Node]] = @[]
  var nextValue: int64 = 1

  if not vp.check(tkRightParen):
    while true:
      if not vp.match(tkIdent):
        raise newException(LuaSyntaxError, "Expected enum member name.")
      let memberName = vp.previous().lexeme
      let memberLine = vp.previous().line

      var memberValue = nextValue
      if vp.match(tkAssign):
        var sign = 1
        if vp.match(tkMinus): sign = -1
        if not vp.match(tkNumber):
          raise newException(LuaSyntaxError,
              "Expected number after '=' in enum member '" & memberName & "'.")
        memberValue = sign * parseInt(vp.previous().lexeme)

      nextValue = memberValue + 1

      fields.add((newString(memberName, memberLine), newInteger(memberValue,
          memberLine))) # forward: name -> value
      fields.add((newInteger(memberValue, memberLine), newString(memberName,
          memberLine))) # reverse: value -> name

      if not vp.match(tkComma): break

  vp.consume(tkRightParen, "Expected ')' to close enum member list.")
  return newTableLit(fields, line)

proc infixPrecedence(kind: TokenKind): int =
  case kind
  of tkOr: 1
  of tkAnd: 2
  of tkLess, tkGreater, tkLessEqual, tkGreaterEqual, tkNotEquals, tkEquals: 3
  of tkPipe: 4
  of tkTilde: 5 # binary XOR here, distinct from unary ~
  of tkAmp: 6
  of tkLeftShift, tkRightShift: 7
  of tkConcat: 8 # ..
  of tkPlus, tkMinus: 9
  of tkStar, tkSlash, tkDoubleSlash, tkPercent: 10 # //  is floor-div
  # unary operators sit here, handled separately (see below)
  of tkCaret: 12 # ^  binds tighter than unary
  else: -1 # not an infix operator

proc isRightAssoc(kind: TokenKind): bool = kind in {tkCaret, tkConcat}

proc parseUnary(vp): Node =
  if vp.match(tkNot, tkMinus, tkHash, tkTilde):
    let op = vp.previous().kind
    let operand = vp.parseUnary() # recurse into itself: handles `not not x`, `- -x`
    return newUnop(op, operand, vp.previous().line)
  return vp.parsePow()

proc parsePow(vp): Node =
  result = vp.parseCall() # your existing tightest level (calls, indexing, literals)
  if vp.match(tkCaret):
    let right = vp.parseUnary() # right-assoc AND lets the exponent itself be unary
    result = newBinop(tkCaret, result, right, vp.peek().line)

proc parseBinary(vp; minPrec: int): Node =
  result = vp.parseUnary()
  let line = vp.peek().line
  while true:
    let opKind = vp.peek().kind
    let prec = infixPrecedence(opKind)
    if prec < minPrec: break
    discard vp.advance() # consume the operator
    # For right-assoc ops, recurse at the SAME precedence so it re-binds to the right.
    # For left-assoc ops, recurse at prec+1 so equal-precedence ops don't re-swallow us.
    let nextMinPrec = if isRightAssoc(opKind): prec else: prec + 1
    let right = vp.parseBinary(nextMinPrec)
    if opKind == tkAnd:
      result = newAnd(result, right, line)
    elif opKind == tkOr:
      result = newOr(result, right, line)
    else:
      result = newBinop(opKind, result, right, line)

proc parseExpression(vp): Node =
  return vp.parseBinary(1) # 1 = lowest precedence (or/and)

proc parsePrimary(vp): Node =

  if vp.match(tkNumber):
    let lexeme = vp.previous().lexeme
    let line = vp.peek().line
    if '.' in lexeme or 'e' in lexeme or 'E' in lexeme:
      return newNumber(parseFloat(lexeme), line)
    else:
      return newInteger(parseInt(lexeme), line)
  elif vp.match(tkNil):
    let line = vp.peek().line
    return newNil(line)
  elif vp.match(tkString):
    return newString(vp.previous().lexeme, vp.peek().line)
  elif vp.match(tkIdent):
    return newIdent(vp.previous().lexeme, vp.peek().line)
  elif vp.match(tkFalse):
    return newBool(false, vp.peek().line)
  elif vp.match(tkTrue):
    return newBool(true, vp.peek().line)
  elif vp.match(tkLeftParen):
    let expr = vp.parseExpression()

    # 2. Demand the closing parenthesis
    if not vp.match(tkRightParen):
      raise newException(LuaSyntaxError, "Expected ')' after expression.")

    # 3. Return the inner expression directly!
    return expr
  elif vp.match(tkLeftBrace):
    var fields: seq[tuple[key: Node, val: Node]] = @[]
    if not vp.check(tkRightBrace):
      while true:
        var keyNode: Node
        var valNode: Node

        # Check if it's a field assignment like { name = "value" }
        if vp.check(tkIdent) and vp.tokens[vp.current + 1].kind == tkAssign:
          let keyName = vp.advance().lexeme
          keyNode = newString(keyName, vp.peek().line)
          discard vp.advance() # consume tkAssign
          valNode = vp.parseExpression()
        elif vp.match(tkLeftBracket):
          # Bracketed key like { [1] = "value" }
          keyNode = vp.parseExpression()
          vp.consume(tkRightBracket, "Expected ']' after table key.")
          vp.consume(tkAssign, "Expected '=' after table key.")
          valNode = vp.parseExpression()
        else:
          # Array-style element (optional for basic tables)
          valNode = vp.parseExpression()

        fields.add((keyNode, valNode))
        if not vp.match(tkComma):
          break
    vp.consume(tkRightBrace, "Expected '}' after table literal.")
    return newTableLit(fields, vp.peek().line)
  elif vp.match(tkFunction):
    let defLine = vp.previous().line
    vp.consume(tkLeftParen, "Expected '(' after function keyword.")

    var parameters: seq[string] = @[]
    if not vp.check(tkRightParen):
      while true:
        if not vp.match(tkIdent):
          raise newException(LuaSyntaxError, "Syntax Error: Expected parameter name.")
        parameters.add(vp.previous().lexeme)
        if not vp.match(tkComma):
          break
    vp.consume(tkRightParen, "Expected ')' after parameters.")

    # Parse the function body statements until 'end'
    var body = newBlock(vp.peek().line)
    while not vp.check(tkEnd) and not vp.check(tkEOF):
      body.stmts.add(vp.parseStatement())

    vp.consume(tkEnd, "Expected 'end' to close function body.")

    # Pass "" as the name for anonymous/expression functions
    return newFunctionDef("<anonymous>", parameters, body, defLine, false, isExpr = true)
  elif vp.match(tkDots):
    return newVararg(vp.peek().line)
  elif vp.match(tkBreak):
    return newBreak(vp.peek().line)
  elif vp.check(tkEnum):
    return vp.parseEnum()
  raise newException(LuaSyntaxError, "Expected expression. Kind: " & $vp.peek().kind)



proc parseIfClause(vp; startLine: int): Node =
  # Called right after consuming either `if` or `elseif` — condition/then/body
  # parsing is identical for both, which is what makes the recursion work.
  let cond = vp.parseExpression()
  vp.consume(tkThen, "Expect then after if/elseif")
  let body = vp.parseBlockUntil(tkElseIf, tkElse, tkEnd)

  result = newIfStmt(cond, body, startLine)

  if vp.match(tkElseIf):
    let elseIfLine = vp.previous().line
    result.elseBranch = vp.parseIfClause(
        elseIfLine) # <- recurse; handles any number of elseifs
  elif vp.match(tkElse):
    result.elseBranch = vp.parseBlockUntil(tkEnd)
    vp.consume(tkEnd, "Expect end after else")
  else:
    vp.consume(tkEnd, "Expect end after if")

proc parseIfStmt(vp): Node =
  let startLine = vp.peek().line
  vp.consume(tkIf, "Expect if stmt")
  result = vp.parseIfClause(startLine)



proc parseStatement(vp): Node =
  case vp.peek().kind:
  of tkLocal, tkGlobal:
    return vp.parseVarDecl()
  of tkIdent:
    let startPos = vp.current
    let expr = vp.parseCall()

    if vp.peek().kind == tkComma and expr.kind == nkIdent:
      var varNames = @[expr.name]
      while vp.match(tkComma):
        if not vp.match(tkIdent):
          raise newException(LuaSyntaxError, "Expected variable name after ','.")
        varNames.add(vp.previous().lexeme)
      vp.consume(tkAssign, "Expected '=' in multi-assignment.")
      var values: seq[Node] = @[vp.parseExpression()]
      while vp.match(tkComma):
        values.add(vp.parseExpression())
      let attrs = newSeq[set[ValueAttribute]](varNames.len) # all empty -- plain reassignment
      return newMultiAssign(varNames, values, attrs, vp.peek().line)

    elif vp.match(tkAssign):
      # Handle single assignments (e.g., x = 5 or t.k = 10)
      if expr.kind == nkIdent:
        let value = vp.parseExpression()
        return newAssign(expr.name, value, {}, vp.peek().line)
      elif expr.kind == nkIndexGet:
        # If parseCall returned an index get, convert it to an index set
        let value = vp.parseExpression()
        return newTableSet(expr.getTbl, expr.getKey, value, vp.peek().line)
      elif vp.match(tkColon):
        if not vp.match(tkIdent):
          raise newException(LuaSyntaxError, "Expected method name after ':'.")
        let methodName = vp.previous().lexeme
        let mcLine = vp.peek().line
        vp.consume(tkLeftParen, "Expected '(' after method name.")
        var call = newMethodCall(result, methodName, mcLine)
        if not vp.check(tkRightParen):
          while true:
            call.mcArgs.add(vp.parseExpression())
            if not vp.match(tkComma): break
        vp.consume(tkRightParen, "Expected ')' after method call arguments.")
        result = call
      else:
        raise newException(LuaSyntaxError, "Invalid assignment target.")

    else:
      # Handle standalone function calls (e.g., setmetatable(...), print(...))
      return newExprStmt(expr, vp.peek().line)
  of tkFunction:
    return vp.parseFunctionDef(false)
  of tkReturn:
    var vals: seq[Node] = @[]
    vp.consume(tkReturn, "Expect return")
    if not vp.check(tkEnd) and not vp.check(tkElse) and not vp.check(
        tkElseIf) and not vp.check(tkEOF):
      vals.add(vp.parseExpression())
      while vp.match(tkComma):
        vals.add(vp.parseExpression())
    return newReturn(vp.peek().line, vals)
  of tkIf:
    return vp.parseIfStmt()
  of tkDo:
    let line = vp.peek().line
    vp.consume(tkDo, "Expect 'do'")
    let body = vp.parseBlockUntil(tkEnd)
    vp.consume(tkEnd, "Expected 'end' to close 'do' block.")
    return newDoBlock(body, line)
  of tkFor:
    return vp.parseForStmt()
  of tkWhile:
    return vp.parseWhileStmt()
  of tkRepeat:
    return vp.parseRepeatStmt()
  of tkBreak:
    let line = vp.peek().line
    vp.consume(tkBreak, "Expect break")
    return newBreak(line)
  of tkGoto:
    let line = vp.peek().line
    vp.consume(tkGoto, "Expect goto")
    if not vp.match(tkIdent):
      raise newException(LuaSyntaxError, "Expected label name after 'goto'")
    return newGoto(vp.previous().lexeme, line)
  of tkDbColon:
    let line = vp.peek().line
    discard vp.advance()
    if not vp.match(tkIdent):
      raise newException(LuaSyntaxError, "Expected label name after '::'")
    let name = vp.previous().lexeme
    vp.consume(tkDbColon, "Expected '::' to close label declaration")
    return newLabel(name, line)
  else:
    return newExprStmt(vp.parseExpression(), vp.peek().line)

proc parseBlockUntil(vp; terminators: varargs[TokenKind]): Node =
  result = newBlock(vp.peek().line)
  while vp.peek().kind notin terminators and vp.peek().kind != tkEOF:
    result.stmts.add(vp.parseStatement())

proc parseBlock*(vp): Node =
  result = newBlock(vp.peek().line)

  # Keep parsing statements until we run out of tokens
  while vp.peek().kind != tkEOF:
    let stmt = vp.parseStatement()
    result.stmts.add(stmt)

proc printNode*(node: Node, indent: string = "") =
  let prefix = indent

  if node == nil:
    echo prefix & "nil"
    return

  case node.kind
  of nkNumber:
    echo prefix & "nkNumber(" & $node.nval & ")"

  of nkString:
    echo prefix & "nkString(\"" & node.sval & "\")"

  of nkIdent:
    echo prefix & "nkIdent(" & node.name & ")"

  of nkBinaryOp:
    echo prefix & "nkBinaryOp[" & $node.op & "]"
    echo prefix & "  left:"
    printNode(node.left, indent & "    ")
    echo prefix & "  right:"
    printNode(node.right, indent & "    ")

  of nkAssign:
    echo prefix & "nkAssign(" & node.varName & ", attrs=" & $node.attrs & ")"
    if node.value != nil:
      echo prefix & "  value:"
      printNode(node.value, indent & "    ")
    else:
      echo prefix & "  value: (none)"

  of nkMultiAssign:
    echo prefix & "nkMultiAssign (" & $node.varNames.len & " variables)"
    for i, name in node.varNames:
      let attrStr = if i < node.mAttrs.len: $node.mAttrs[i] else: "{}"
      echo prefix & "  var[" & $i & "]: " & name & " (attrs: " & attrStr & ")"
    if node.values.len > 0:
      echo prefix & "  values:"
      for i, val in node.values:
        echo prefix & "    val[" & $i & "]:"
        printNode(val, indent & "      ")

  of nkIfStmt:
    echo prefix & "nkIfStmt"
    echo prefix & "  condition:"
    printNode(node.condition, indent & "    ")
    echo prefix & "  thenBranch:"
    printNode(node.thenBranch, indent & "    ")

  of nkCall:
    echo prefix & "nkCall("
    echo prefix & "  callee:"
    printNode(node.callee, indent & "    ")
    echo prefix & "  args: ["
    for i, arg in node.args:
      echo prefix & "    arg[" & $i & "]:"
      printNode(arg, indent & "      ")
    echo prefix & "  ]"
    echo prefix & ")"

  of nkBlock:
    echo prefix & "nkBlock (" & $node.stmts.len & " statements)"
    for i, stmt in node.stmts:
      echo prefix & "  stmt[" & $i & "]:"
      printNode(stmt, indent & "      ")

  of nkExprStmt:
    echo prefix & "nkExprStmt"
    echo prefix & "  expr:"
    printNode(node.expr, indent & "    ")

  of nkFunctionDef:
    echo prefix & "nkFunctionDef(local=" & $(
        if node.isLocal: "true" else: "false") & ", name=" & node.fnName &
        ", arity=" & $node.params.len & ")"
    if node.params.len > 0:
      echo prefix & "  params: [" & node.params.join(", ") & "]"
    echo prefix & "  body:"
    printNode(node.body, indent & "    ")

  of nkReturn:
    echo prefix & "nkReturn(returnValue: "
    for n in node.retVals:
      printNode(n, indent & "  ")

  of nkTableLiteral:
    echo prefix & "nkTableValues: "
    for idx, item in node.tableFields:
      let (key, val) = item
      printNode(key)
      printNode(val)

  of nkIndexGet:
    echo prefix & "nkIndexGet: "
    echo "table: "
    printNode(node.getTbl)
    echo "key: "
    printNode(node.getKey)

  of nkIndexSet:
    echo prefix & "nkIndexSet: "
    echo "table: "
    printNode(node.setTbl)
    echo "key: "
    printNode(node.setKey)
    echo "value: "
    printNode(node.setValue)

  of nkGenericFor:
    echo prefix & "nkGenericFor"
    echo prefix & "  loopVars: [" & node.loopVars.join(", ") & "]"
    echo prefix & "  iterExprs:"
    for i, expr in node.iterExprs:
      printNode(expr, indent & "    ")
    echo prefix & "  body:"
    printNode(node.genericBody, indent & "    ")
  of nkMethodCall:
    echo prefix & "nkMethodCall(:" & node.mcMethodName & ")"
    echo prefix & "  receiver:"
    printNode(node.mcReceiver, indent & "    ")
    for i, arg in node.mcArgs:
      echo prefix & "  arg[" & $i & "]:"
      printNode(arg, indent & "    ")
  else:
    echo prefix & "unknown kind: " & $node.kind

# Helper to print the full AST from a parser
proc printAST*(parser: LuaParser) =
  echo "=== Full AST Tree ==="
  var p = LuaParser(tokens: parser.tokens, current: 0)
  var ast = p.parseBlock()
  printNode(ast)
  echo "====================="


