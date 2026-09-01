import lexer, tokens, errors, ast, types
import std/[strutils, sequtils]

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

proc expectToken(self: var Parser, expected: varargs[TokenKind]): Token =
  let token = self.nextToken()
  if token.kind notin expected:
    let expectedStr = (if expected.len > 1: "one of " else: "") & expected.mapIt(it.mean).join(", ")
    self.newError(errExpectedSyntax, token, expectedStr, token.mean)
    return token.copy(kind = tkInvalid)
  return token

proc isExpression(self: Parser, token: Token): bool =
  token.kind in {tkLParen, tkNumber, tkTrue, tkFalse, tkIdent, tkBang, tkMinus, tkPlus, tkType}

proc isType(self: Parser, token: Token): bool =
  token.kind in {tkType}

proc parseType(self: var Parser, token: Token): Type =
  case token.kind:
  of tkType: 
    result = if token.lexeme == "Unset": getUnsetType(token) else: getBaseType(token)
  else:
    newError(errType, token, token.mean)
    result = getUnsetType(token)

  while self.peekToken().kind in {tkLParen}:
    let tok = self.nextToken()

    if tok.kind == tkLParen:
      var argTypes: seq[ArgType]

      while self.peekToken().kind != tkRParen and self.peekToken().kind != tkEOF:
        var argType = ArgType(argType: self.parseType(self.nextToken()))
        argType.name = self.expectToken(tkIdent).lexeme
        if self.peekToken().kind == tkDollar:
          self.skipToken()
          argType.mutable = true
        elif self.peekToken().kind == tkBang:
          self.skipToken()
          argType.mutable = false

        argTypes.add(argType)

        if self.peekToken().kind == tkRParen: break
        discard self.expectToken(tkComma)

      discard self.expectToken(tkRParen)
      result = getFuncType(token, argTypes, result)

proc parseExpression(self: var Parser): Expression

proc parseStatement(self: var Parser): Statement

proc parseBlock(self: var Parser, endKinds: varargs[TokenKind], consume: bool = true): BlockStatement =
  discard self.expectToken(tkDo)

  var stmts: seq[Statement]
  
  while self.peekToken().kind notin endKinds and self.peekToken().kind != tkEOF:
    stmts.add(self.parseStatement())
  
  let endToken = if consume:
    self.expectToken(endKinds)
  else:
    self.peekToken()
  
  result = newBlockStatement(endToken, stmts)

proc parseFuncExpression(self: var Parser, funcType: Type): Expression =
  let funcToken = self.peekToken()
  let funcBlock = self.parseBlock(tkEnd)
  result = newFuncExpression(funcToken, funcBlock)
  result.exprType = funcType

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

  elif token.kind in {tkIdent}:
    var requireImmutable = false
    if self.peekToken().kind == tkBang:
      self.skipToken()
      requireImmutable = true
    return newIdentExpression(token, requireImmutable)

  elif token.kind == tkType:
    let typ = self.parseType(token)
    if typ.eq(typeFunc) and self.peekToken().kind == tkDo:
      return self.parseFuncExpression(typ)
    result = newTypeExpression(token)
    result.exprType = getTypeType(token, typ)
    return result

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

      while self.peekToken().kind != tkRParen and self.peekToken().kind != tkEOF:
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

proc parseDeclaration(self: var Parser): Statement =
  let valueType = self.parseType(self.nextToken())
  let name = self.expectToken(tkIdent)

  var mutable = true
  if self.peekToken().kind == tkDollar:
    self.skipToken()
    mutable = true
  elif self.peekToken().kind == tkBang:
    self.skipToken()
    mutable = false

  let token = self.expectToken(tkEquals)
  let value = self.parseExpression()

  return newDeclarationStatement(token, valueType, name, value, mutable)

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

proc parseReturn(self: var Parser): Statement =
  let token = self.nextToken()
  var expression: Expression = nil

  if self.isExpression(self.peekToken()):
    expression = self.parseExpression()

  return newReturnStatement(token, expression)
  
proc parseDef(self: var Parser): Statement =
  let token = self.nextToken()
  let name = self.expectToken(tkIdent, tkType)
  discard self.expectToken(tkEquals)
  let value = self.parseExpression()

  return newDefStatement(token, name, value)

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

  elif token.kind == tkReturn:
    return self.parseReturn()

  elif token.kind == tkDef:
    return self.parseDef()

  elif self.isExpression(token):
    let expr = self.parseExpression()

    if expr.kind in {exprIdent, exprDeref} and self.peekToken().kind == tkEquals:
      return newAssignmentStatement(self.nextToken(), expr, self.parseExpression())

    elif expr.kind == exprCall:
      return newCallStatement(expr.token, CallExpression(expr))

  self.newError(errStatement, token, token.mean())
  return newInvalidStatement(token)

proc parse*(self: var Parser): BlockStatement =
  var statements: seq[Statement]

  while true:
    statements.add(self.parseStatement())
    if self.lexer.peekToken().kind == tkEOF:
      break

  return newBlockStatement(self.peekToken(), statements)