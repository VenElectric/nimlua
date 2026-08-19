import llex, lerror
import std/[strutils,logging]
type
  NodeKind* = enum
    nkNil,
    nkBool,
    nkNumber,
    nkString, 
    nkIdent, 
    nkBinaryOp, 
    nkAnd,
    nkOr,
    nkUnaryOp,
    nkAssign, 
    nkIfStmt,
    nkWhileStmt,
    nkRepeatStmt,
    nkCall,
    nkLocalDecl, 
    nkGlobalDecl, 
    nkMultiLocalDecl,
    nkMultiGlobalDecl,
    nkBlock, 
    nkExprStmt,
    nkFunctionDef, 
    nkReturn, 
    nkTableLiteral, # e.g., { } or tables with initial values
    nkIndexGet, # e.g., t[k] or t.field
    nkIndexSet,
    nkVararg,
    nkNumericFor,
    nkBreak,
    nkGoto,
    nkLabel
  Node*{.acyclic.} = ref object
    line*: int
    case kind*: NodeKind
    of nkNil,nkVararg,nkBreak: discard
    of nkGoto,nkLabel: labelName*: string
    of nkNumber:
      nval*: float64
    of nkString:
      sval*: string
    of nkBool:
      bval*: bool
    of nkIdent:
      name*: string
    of nkBinaryOp,nkUnaryOp,nkAnd,nkOr:
      left*: Node
      right*: Node
      op*: TokenKind       # From our Lexer (e.g., tkPlus, tkStar)
    of nkAssign, nkLocalDecl, nkGlobalDecl:
      varName*: string
      value*: Node
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
      forStep*: Node    # nil if the third `, step` was omitted
      forBody*: Node
    of nkMultiLocalDecl, nkMultiGlobalDecl:
      varNames*: seq[string]
      values*: seq[Node]
  LuaParser* = object
    tokens*: seq[Token]
    current*: int


proc newNode(kind:NodeKind,line:int): Node = result = Node(kind: kind, line: line)

proc newNil(line:int): Node = result = newNode(nkNil,line)

proc newBool(v:bool,line:int): Node = 
  result = newNode(nkBool,line)  
  result.bval = v

proc newNumber(v: float64,line:int): Node =
  result = newNode(nkNumber,line)
  result.nval = v

proc newString(v: string,line:int): Node =
  result = newNode(nkString,line)
  result.sval = v

proc newIdent(name: string,line:int): Node =
  result = newNode(nkIdent,line)
  result.name = name

proc newBinop(op: TokenKind, left, right: Node,line:int): Node =
  result = Node(kind: nkBinaryOp, op: op, left: left, right: right,line:line)

proc newAnd(left,right:Node,line:int): Node = 
  result = newNode(nkAnd,line)
  result.left = left
  result.right = right

proc newOr(left,right:Node,line:int): Node = 
  result = newNode(nkOr,line)
  result.left = left
  result.right = right
  

proc newUnop(op:TokenKind,right:Node,line:int): Node =
  result = Node(kind:nkUnaryOp,op:op,right:right,line:line)

proc newAssign(name: string, value: Node,line:int): Node =
  result = newNode(nkAssign,line)
  result.varName = name
  result.value = value

proc newLocalDecl(name: string, value: Node,line:int): Node =
  result = newNode(nkLocalDecl,line)
  result.varName = name
  result.value = value

proc newGlobalDecl(name: string, value: Node,line:int): Node =
  result = newNode(nkGlobalDecl,line)
  result.varName = name
  result.value = value

proc newCall(callee: Node,line:int): Node =
  result = newNode(nkCall,line)
  result.callee = callee
  result.args = @[]

proc newIfStmt(condition,thenBranch:Node,line:int): Node = 
  result = newNode(nkIfStmt,line)
  result.condition = condition
  result.thenBranch = thenBranch

proc newWhileStmt(condition, thenBranch: Node, line: int): Node =
  result = newNode(nkWhileStmt, line)
  result.loopCond = condition
  result.loopBody = thenBranch

proc newRepeatStmt(condition,thenBranch:Node,line:int): Node =
  result = newNode(nkRepeatStmt,line)
  result.loopCond = condition
  result.loopBody = thenBranch


proc newBlock(line:int): Node = Node(kind: nkBlock, stmts: @[],line:line)

proc newExprStmt(expr: Node,line:int): Node = Node(kind: nkExprStmt, expr: expr,line: line)

proc newFunctionDef(name: string, params: seq[string], body: Node, line: int,isVararg:bool,
    isLocal: bool = false, isExpr: bool = false): Node =
  result = Node(kind: nkFunctionDef, fnName: name, params: params, body: body,
      isLocal: isLocal, isExpr: isExpr, line: line,isVararg: isVararg)

proc newVararg(line:int): Node = Node(kind: nkVararg,line: line)

proc newReturn(line:int,values: seq[Node] = @[]): Node = Node(kind: nkReturn, retVals: values,line: line)

proc newTableLit(fields: seq[tuple[key, val: Node]],line:int): Node =
  result = Node(kind: nkTableLiteral, tableFields: fields,line:line)

proc newTableSet(setTbl, setKey, setValue: Node,line:int): Node =
  result = Node(kind: nkIndexSet, setTbl: setTbl, setKey: setKey,
      setValue: setValue,line: line)

proc newTableGet(getTbl, getKey: Node,line: int): Node =
  result = Node(kind: nkIndexGet, getTbl: getTbl, getKey: getKey,line: line)

proc newNumericFor(firstName:string, startExpr, stopExpr, stepExpr, body:Node, line:int): Node = 
  Node(kind:nkNumericFor,forVar: firstName,forStart: startExpr, forStop: stopExpr,forBody: body,line: line)

proc newBreak(line:int): Node = newNode(nkBreak,line)

proc newLabel(name:string,line:int): Node = 
  result = newNode(nkLabel,line)
  result.labelName = name

proc newGoto(name:string,line:int): Node = 
  result = newNode(nkGoto,line)
  result.labelName = name

proc newMultiLocalDecl(names:seq[string],values:seq[Node],line:int): Node = 
  result = newNode(nkMultiLocalDecl,line)
  result.varNames = names
  result.values = values

proc newMultiGlobalDecl(names:seq[string],values:seq[Node],line:int): Node = 
  result = newNode(nkMultiGlobalDecl,line)
  result.varNames = names
  result.values = values

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
  result = newCall(callee,vp.peek().line)

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
  # First, parse the primary expression (e.g., the name "print")
  result = vp.parsePrimary()

  # While we see a '(', parse it as a function call
  while true:
    if vp.match(tkLeftParen):

      result = vp.finishCall(result)
    elif vp.match(tkLeftBracket):
      let keyExpr = vp.parseExpression()
      vp.consume(tkRightBracket, "Expected ']' after index expression.")
      result = newTableGet(result, keyExpr,vp.peek().line)
    elif vp.match(tkDot):
      if not vp.match(tkIdent):
        raise newException(LuaSyntaxError, "Syntax Error: Expected identifier after '.'.")
      let fieldName = vp.previous().lexeme
      let keyExpr = newString(fieldName,vp.peek().line)
      result = newTableGet(result, keyExpr,vp.peek().line)
    else:
      break

proc parseFunctionDef(vp; isLocal: bool): Node =
  let lineDef = vp.peek().line
  vp.consume(tkFunction, "Expect function ident")

  if not vp.match(tkIdent):
    raise newException(LuaSyntaxError, "Expected function name.")
  let name = vp.previous().lexeme

  vp.consume(tkLeftParen, "Expected '(' after function name.")
  debug "Tkdots? ",vp.peek().kind
  var isVararg = false
  var parameters: seq[string] = @[]
  if not vp.check(tkRightParen):
    while true:
      if vp.match(tkDots):
        isVararg = true
        debug "Isvararg: ",isVararg
        break
      if not vp.match(tkIdent):
        raise newException(LuaSyntaxError, "Syntax Error: Expected parameter name.")
      parameters.add(vp.previous().lexeme)
      if not vp.match(tkComma):
        break
  vp.consume(tkRightParen, "Expected ')' after parameters.")

  # Parse the body until we hit 'end'
  var body = newBlock(vp.peek().line)
  while not vp.check(tkEnd) and not vp.check(tkEOF):
    body.stmts.add(vp.parseStatement())

  vp.consume(tkEnd, "Expected 'end' to close function body.")
  debug "Isvararg before fn def: ",isVararg
  return newFunctionDef(name, parameters, body, lineDef,isVararg,isLocal)

proc parseWhileStmt(vp): Node =
  let line = vp.peek().line
  vp.consume(tkWhile, "Expect 'while'")
  let cond = vp.parseExpression()
  vp.consume(tkDo, "Expected 'do' after while condition.")
  let body = vp.parseBlockUntil(tkEnd)
  vp.consume(tkEnd, "Expected 'end' to close while loop.")
  return newWhileStmt(cond, body, line)

proc parseForStmt(vp): Node =
  let line = vp.peek().line
  vp.consume(tkFor, "Expect 'for'")
  if not vp.match(tkIdent):
    raise newException(LuaSyntaxError, "Expected loop variable name after 'for'.")
  let firstName = vp.previous().lexeme

  if vp.match(tkAssign):
    let startExpr = vp.parseExpression()
    vp.consume(tkComma, "Expected ',' after for-loop start value.")
    let stopExpr = vp.parseExpression()
    var stepExpr: Node = nil
    if vp.match(tkComma):
      stepExpr = vp.parseExpression()
    vp.consume(tkDo, "Expected 'do' after for-loop header.")
    let body = vp.parseBlockUntil(tkEnd)
    vp.consume(tkEnd, "Expected 'end' to close for loop.")
    return newNumericFor(firstName, startExpr, stopExpr, stepExpr, body, line)
  else:
    discard
# local a,b,c = 1,2,3
proc parseVarDecl(vp): Node =
  # 1. Determine which keyword we just matched
  discard vp.advance()
  let isLocal = vp.previous().kind == tkLocal

  
  # FIX: Check if this is a `local function ...` declaration
  if vp.peek().kind == tkFunction:
    return vp.parseFunctionDef(isLocal)
  # 2. Expect the variable name
  if not vp.match(tkIdent):
    raise newException(LuaSyntaxError, "Expected variable name after local/global declaration.")

  
  if vp.peek().kind == tkComma:
    var varNames: seq[string] = @[vp.previous().lexeme]
    while vp.match(tkComma):
      if not vp.match(tkIdent):
        raise newException(LuaSyntaxError, "Expected variable name after ','.")
      varNames.add(vp.previous().lexeme)

      let line = vp.peek().line
      var values: seq[Node] = @[]
      if vp.match(tkAssign):
        values.add(vp.parseExpression())
        while vp.match(tkComma):
          values.add(vp.parseExpression())

      if isLocal:
        result = newMultiLocalDecl(varNames, values, line)
      else:
        result = newMultiGlobalDecl(varNames, values, line)
  else:
    let varName = vp.previous().lexeme
    var initValue: Node
    
    # 3. Check for an optional '=' assignment
    if vp.match(tkAssign):
      initValue = vp.parseExpression()
      
    if isLocal:
      result = newLocalDecl(varName, initValue,vp.peek().line)
    else:
      result = newGlobalDecl(varName, initValue,vp.peek().line)

proc infixPrecedence(kind: TokenKind): int =
  case kind
  of tkOr: 1
  of tkAnd: 2
  of tkLess, tkGreater, tkLessEqual, tkGreaterEqual, tkNotEquals, tkEquals: 3
  of tkPipe: 4
  of tkTilde: 5          # binary XOR here, distinct from unary ~
  of tkAmp: 6
  of tkLeftShift, tkRightShift: 7
  of tkConcat: 8          # ..
  of tkPlus, tkMinus: 9
  of tkStar, tkSlash, tkDoubleSlash, tkPercent: 10   # //  is floor-div
  # unary operators sit here, handled separately (see below)
  of tkCaret: 12          # ^  binds tighter than unary
  else: -1                # not an infix operator

proc isRightAssoc(kind: TokenKind): bool = kind in {tkCaret, tkConcat}

proc parseUnary(vp): Node =
  if vp.match(tkNot, tkMinus, tkHash, tkTilde):
    let op = vp.previous().kind
    let operand = vp.parseUnary()   # recurse into itself: handles `not not x`, `- -x`
    return newUnop(op, operand, vp.previous().line)
  return vp.parsePow()

proc parsePow(vp): Node =
  result = vp.parseCall()           # your existing tightest level (calls, indexing, literals)
  if vp.match(tkCaret):
    let right = vp.parseUnary()     # right-assoc AND lets the exponent itself be unary
    result = newBinop(tkCaret, result, right, vp.peek().line)

proc parseBinary(vp; minPrec: int): Node =
  result = vp.parseUnary()
  let line = vp.peek().line
  while true:
    let opKind = vp.peek().kind
    let prec = infixPrecedence(opKind)
    if prec < minPrec: break
    discard vp.advance()   # consume the operator
    # For right-assoc ops, recurse at the SAME precedence so it re-binds to the right.
    # For left-assoc ops, recurse at prec+1 so equal-precedence ops don't re-swallow us.
    let nextMinPrec = if isRightAssoc(opKind): prec else: prec + 1
    let right = vp.parseBinary(nextMinPrec)
    if opKind == tkAnd:
      result = newAnd(result,right,line)
    elif opKind == tkOr:
      result = newOr(result,right,line)
    else:
      result = newBinop(opKind, result, right, line)

proc parseExpression(vp): Node =
  return vp.parseBinary(1)   # 1 = lowest precedence (or/and)

proc parsePrimary(vp): Node =

  if vp.match(tkNumber):
    # Convert string lexeme "42.0" to a float64
    let val = parseFloat(vp.previous().lexeme)
    return newNumber(val,vp.peek().line)
  elif vp.match(tkString):
    return newString(vp.previous().lexeme,vp.peek().line)
  elif vp.match(tkIdent):
    return newIdent(vp.previous().lexeme,vp.peek().line)
  elif vp.match(tkFalse):
    return newBool(false,vp.peek().line)
  elif vp.match(tkTrue):
    return newBool(true,vp.peek().line)
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
          keyNode = newString(keyName,vp.peek().line)
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
          keyNode = nil

        fields.add((keyNode, valNode))
        if not vp.match(tkComma):
          break
    vp.consume(tkRightBrace, "Expected '}' after table literal.")
    return newTableLit(fields,vp.peek().line)
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
    result.elseBranch = vp.parseIfClause(elseIfLine)   # <- recurse; handles any number of elseifs
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
    let expr = vp.parseCall() # Parses identifiers, t[k], t.field, calls
    if vp.match(tkAssign):
      let assignVal = vp.parseExpression()
      if expr.kind == nkIdent:
        return newAssign(expr.name, assignVal,vp.peek().line)
      elif expr.kind == nkIndexGet:
        return newTableSet(expr.getTbl, expr.getKey, assignVal,vp.peek().line)
      else:
        raise newException(LuaSyntaxError, "Invalid assignment target.")
    else:
      vp.current = startPos # Backtrack if it wasn't an assignment
      return newExprStmt(vp.parseExpression(),vp.peek().line)
  of tkFunction:
    return vp.parseFunctionDef(false)
  of tkReturn:
    var vals: seq[Node] = @[]
    vp.consume(tkReturn, "Expect return")
    if not vp.check(tkEnd) and not vp.check(tkElse) and not vp.check(tkElseIf) and not vp.check(tkEOF):
      vals.add(vp.parseExpression())
      while vp.match(tkComma):
        vals.add(vp.parseExpression())
    return newReturn(vp.peek().line, vals)
  of tkIf:
    return vp.parseIfStmt()
  of tkDo:
    vp.consume(tkDo,"Expect Do")
    return vp.parseBlockUntil(tkEnd)
  of tkFor:
    return vp.parseForStmt()
  of tkWhile:
    return vp.parseWhileStmt()
  of tkBreak:
    let line = vp.peek().line
    vp.consume(tkBreak,"Expect break")
    return newBreak(line)
  of tkGoto:
    let line = vp.peek().line
    vp.consume(tkGoto,"Expect goto")
    if not vp.match(tkIdent):
      raise newException(LuaSyntaxError, "Expected label name after 'goto'")
    return newGoto(vp.previous().lexeme,line)
  of tkDbColon:
    let line = vp.peek().line
    discard vp.advance()
    if not vp.match(tkIdent):
      raise newException(LuaSyntaxError, "Expected label name after '::'")
    let name = vp.previous().lexeme
    vp.consume(tkDbColon, "Expected '::' to close label declaration")
    return newLabel(name,line)
  else:
    return newExprStmt(vp.parseExpression(),vp.peek().line)

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
    echo prefix & "nkAssign(" & node.varName & ")"
    echo prefix & "  value:"
    printNode(node.value, indent & "    ")

  of nkLocalDecl:
    echo prefix & "nkLocalDecl(" & node.varName & ")"
    if node.value != nil:
      echo prefix & "  value:"
      printNode(node.value, indent & "    ")
    else:
      echo prefix & "  value: (none)"

  of nkGlobalDecl:
    echo prefix & "nkGlobalDecl(" & node.varName & ")"
    if node.value != nil:
      echo prefix & "  value:"
      printNode(node.value, indent & "    ")
    else:
      echo prefix & "  value: (none)"

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
      printNode(n,indent & "  ")
  of nkTableLiteral:
    echo prefix & "nkTableValues: "
    for idx,item in node.tableFields:
      let (key,val) = item
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
  
  else:
    echo prefix & "unknown kind: " & $node.kind

# Helper to print the full AST from a parser
proc printAST*(parser: LuaParser) =
  echo "=== Full AST Tree ==="
  var p = LuaParser(tokens: parser.tokens, current: 0)
  var ast = p.parseBlock()
  printNode(ast)
  echo "====================="
