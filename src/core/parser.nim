import lexer, tokens, errors, ast, types

type Parser* = object
  file: string
  lexer: Lexer

proc newParser*(text, file: string): Parser =
  Parser(file: file, lexer: newLexer(text, file))

proc newError(self: var Parser,
  kind: ErrorKind, token: Token, 
  args: varargs[string, `$`]) =
  if not self.lexer.wasError:
    newError(kind, token, args)

  let currentLine = token.line
  while self.lexer.peekToken().line == currentLine and self.lexer.peekToken().kind != tkEOF:
    discard self.lexer.nextToken()

proc nextToken(self: var Parser): Token {.inline.} = self.lexer.nextToken()
proc peekToken(self: var Parser): Token {.inline.} = self.lexer.peekToken()
proc skipToken(self: var Parser) {.inline.} = discard self.lexer.nextToken()

proc expectToken(self: var Parser, expected: TokenKind): Token =
  let token = self.nextToken()
  if token.kind != expected:
    self.newError(errExpectedSyntax, token, expected.mean, token.mean)
    return token.copy(kind = tkInvalid)
  return token

proc isExpression(self: Parser, token: Token): bool =
  token.kind in {tkLParen, tkNumber, tkTrue, tkFalse, tkIdent, tkBang, tkMinus, tkPlus}

proc isType(self: Parser, token: Token): bool =
  token.kind in {tkInt64, tkBool, tkUnder}

proc parseType(self: var Parser, token: Token): Type =
  case token.kind:
  of tkInt64: result = getInt64Type()
  of tkBool: result = getBoolType()
  of tkUnder: result = getUndefinedType()
  else:
    newError(errType, token, token.mean)
    result = getUndefinedType()

  while self.peekToken().kind in {tkLParen}:
    let tok = self.nextToken()

    if tok.kind == tkLParen:
      var argTypes: seq[Type]

      while self.peekToken().kind != tkRParen:
        argTypes.add(self.parseType(self.nextToken()))

        if self.peekToken().kind == tkRParen: break
        discard self.expectToken(tkComma)

      discard self.expectToken(tkRParen)
      result = getFuncType(argTypes, result)

proc parseExpression(self: var Parser): Expression

proc parsePrimary(self: var Parser): Expression =
  let token = self.nextToken()

  if token.kind == tkLParen:
    result = self.parseExpression()
    discard self.expectToken(tkRParen)
    return result

  elif token.kind == tkNumber:
    return newNumberExpression(token)

  elif token.kind in {tkTrue, tkFalse}:
    return newBoolExpression(token)

  elif token.kind == tkIdent:
    return newIdentExpression(token)

  self.newError(errExpression, token, token.mean)
  return newInvalidExpression(token)

proc parsePrefix(self: var Parser): Expression =
  let token = self.peekToken()
  if token.kind in {tkPlus, tkMinus, tkBang}:
    self.skipToken()
    return newUnaryExpression(token, self.parsePrefix())

  return self.parsePrimary()

proc parsePostfix(self: var Parser): Expression =
  result = self.parsePrefix()

  while (let token = self.peekToken(); token.kind in {tkLParen}):
    if token.kind == tkLParen:
      self.skipToken()

      var args: seq[Expression]

      while self.peekToken().kind != tkRParen:
        args.add(self.parseExpression())

        if self.peekToken().kind == tkRParen: break
        discard self.expectToken(tkComma)

      discard self.expectToken(tkRParen)
      result = newCallExpression(token, result, args)

proc parseMulDiv(self: var Parser): Expression =
  result = self.parsePostfix()

  while self.peekToken().kind in {tkStar, tkSlash, tkPercent}:
    let op = self.nextToken()
    let right = self.parsePostfix()
    result = newBinaryExpression(op, result, right)

proc parseAddSub(self: var Parser): Expression =
  result = self.parseMulDiv()

  while self.peekToken().kind in {tkPlus, tkMinus}:
    let op = self.nextToken()
    let right = self.parseMulDiv()
    result = newBinaryExpression(op, result, right)

proc parseComparison(self: var Parser): Expression =
  result = self.parseAddSub()

  while self.lexer.peekToken().kind in {tkGT, tkLT, tkGTE, tkLTE, tkEqualsEquals, tkBangEquals}:
    let op = self.lexer.nextToken()
    let right = self.parseAddSub()
    result = newBinaryExpression(op, result, right)

proc parseAnd(self: var Parser): Expression =
  result = self.parseComparison()

  while self.lexer.peekToken().kind == tkAnd:
    let op = self.lexer.nextToken()
    let right = self.parseComparison()
    result = newBinaryExpression(op, result, right)

proc parseOr(self: var Parser): Expression =
  result = self.parseAnd()

  while self.lexer.peekToken().kind == tkOr:
    let op = self.lexer.nextToken()
    let right = self.parseAnd()
    result = newBinaryExpression(op, result, right)

proc parseExpression(self: var Parser): Expression =
  return self.parseOr()

proc parseStatement(self: var Parser): Statement

proc parseDeclaration(self: var Parser): Statement =
  let valueType = self.parseType(self.nextToken())
  let name = self.expectToken(tkIdent)
  let token = self.expectToken(tkEquals)
  let value = self.parseExpression()

  return newDeclarationStatement(token, valueType, name, value)

proc parseBlock(self: var Parser, endKinds: varargs[TokenKind], consume: bool = true): BlockStatement =
  discard self.expectToken(tkDo)

  var stmts: seq[Statement]
  
  while self.peekToken().kind notin endKinds and self.peekToken().kind != tkEOF:
    stmts.add(self.parseStatement())
  
  let endToken = if consume:
    self.nextToken()
  else:
    self.peekToken()
  
  result = newBlockStatement(endToken, stmts)

proc parseBranching(self: var Parser): Statement =
  let token = self.nextToken()

  let cond = self.parseExpression()
  let ifBlock = self.parseBlock(tkEnd, tkElif, tkElse, consume=false)

  var elifBranches: seq[tuple[cond: Expression, elifBlock: BlockStatement]]
  while self.peekToken().kind == tkElif:
    self.skipToken()

    elifBranches.add((
      cond: self.parseExpression(), 
      elifBlock: self.parseBlock(tkEnd, tkElif, tkElse, consume=false)
    ))

  var elseBlock: BlockStatement = nil
  if self.peekToken().kind == tkElse:
    self.skipToken()
    elseBlock = self.parseBlock(tkEnd, consume=false)

  discard self.expectToken(tkEnd)

  return newBranchingStatement(token, cond, ifBlock, elifBranches, elseBlock)

proc parseWhile(self: var Parser): Statement =
  let token = self.nextToken()
  
  let cond = self.parseExpression()
  let whileBlock = self.parseBlock(tkEnd)
  
  return newWhileStatement(token, cond, whileBlock)

proc parseFunc(self: var Parser): Statement =
  let token = self.nextToken()

  var funcType = getUndefinedType()

  if self.isType(self.peekToken()):
    funcType = self.parseType(self.nextToken())

  let name = self.expectToken(tkIdent)

  discard self.expectToken(tkLParen)

  var args: seq[FuncArg]

  while self.peekToken().kind != tkRParen:
    args.add(self.parseType(self.nextToken()), self.expectToken(tkIdent))

    if self.peekToken().kind == tkRParen: break
    discard self.expectToken(tkComma)

  discard self.expectToken(tkRParen)

  let funcBlock = self.parseBlock(tkEnd)

  return newFuncStatement(token, funcType, name, args, funcBlock)

proc parseReturn(self: var Parser): Statement =
  let token = self.nextToken()
  var expression: Expression = nil

  if self.isExpression(self.peekToken()):
    expression = self.parseExpression()

  return newReturnStatement(token, expression)

proc parseStatement(self: var Parser): Statement =
  let token = self.lexer.peekToken()

  if self.isType(token):
    return self.parseDeclaration()

  elif token.kind == tkIf:
    return self.parseBranching()

  elif token.kind == tkWhile:
    return self.parseWhile()

  elif token.kind == tkContinue:
    return newContinueStatement(self.nextToken())

  elif token.kind == tkBreak:
    return newBreakStatement(self.nextToken())

  elif token.kind == tkFunc:
    return self.parseFunc()

  elif token.kind == tkReturn:
    return self.parseReturn()

  elif self.isExpression(token):
    let expr = self.parseExpression()

    if expr.kind in {exprIdent} and self.peekToken().kind == tkEquals:
      return newAssignmentStatement(self.nextToken(), expr, self.parseExpression())

  self.newError(errStatement, token, token.mean())
  return newInvalidStatement(token)

proc parse*(self: var Parser): BlockStatement =
  var statements: seq[Statement]

  while true:
    statements.add(self.parseStatement())
    if self.lexer.peekToken().kind == tkEOF:
      break

  return newBlockStatement(self.peekToken(), statements)