import ../core/[ast, types, tokens, errors]
import std/[tables, sequtils, strutils, options, macros]
import builtins

type
  Symbol = object
    definitionToken: Token
    symbolType: Type
    mutable: bool = true

  Scope = ref object
    depth: Natural
    symbolTable: Table[string, Symbol]
    case isGlobal: bool
    of false: parent: Scope
    of true: discard

  Context = ref object
    currentScope: Scope
    symbolScopeStack: Table[string, seq[Scope]]

    loopDepth: Natural
    funcDepth: Natural

    expectedReturnType: Type
    expectedRegion: Type

    builtins: Builtins[Symbol]

proc newSymbol(self: Context, name: Token, symbolType: Type, mutable: bool) =
  self.currentScope.symbolTable[name.lexeme] = Symbol(definitionToken: name, symbolType: symbolType, mutable: mutable)
  self.symbolScopeStack.mgetOrPut(name.lexeme, @[]).add(self.currentScope)

proc newSymbolGet(self: Context, name: Token, symbolType: Type, mutable: bool): Symbol =
  result = Symbol(definitionToken: name, symbolType: symbolType, mutable: mutable)
  self.currentScope.symbolTable[name.lexeme] = result
  self.symbolScopeStack.mgetOrPut(name.lexeme, @[]).add(self.currentScope)

proc pushScope(self: Context) =
  let depth = self.currentScope.depth
  self.currentScope = Scope(isGlobal: false, symbolTable: initTable[string, Symbol](), 
    parent: self.currentScope, depth: depth + 1)

proc popScope(self: Context) =
  let scope = self.currentScope
  for name in scope.symbolTable.keys:
    discard self.symbolScopeStack[name].pop()
  self.currentScope = scope.parent

proc getSymbol(self: Context, name: string): Symbol =
  let scope = self.symbolScopeStack[name][^1]
  result = scope.symbolTable[name]

proc symbolExists(self: Context, name: string): bool =
  let exists = name in self.symbolScopeStack and self.symbolScopeStack[name].len > 0
  return exists

proc symbolExistsInCurrentScope(self: Context, name: string): bool =
  let exists = name in self.currentScope.symbolTable
  return exists

proc visit(ctx: Context, node: Expression)
proc visit(ctx: Context, node: Statement)

proc setType(node: Expression, ctx: Context, exprType: Type) {.inline.} =
  node.exprType = exprType

macro builtinType(name: untyped): untyped =
  return quote do:
    ctx.builtins.`name`.symbolType.baseType

proc visitNumberExpression(ctx: Context, node: NumberExpression) =
  node.setType(ctx, builtinType(Number))

proc visitBoolExpression(ctx: Context, node: BoolExpression) =
  node.setType(ctx, builtinType(Bool))

template isNumber(typ: Type): bool =
  typ.eq(builtinType(Number)) or
    typ.eq(builtinType(Int))

proc visitUnaryExpression(ctx: Context, node: UnaryExpression) =
  ctx.visit(node.value)
  let op  = node.token.kind
  let typ = node.value.exprType

  if typ.isNumber() and op in {tkPlus, tkMinus}:
    node.setType(ctx, node.value.exprType)

  elif typ.eq(builtinType(Bool)) and op == tkBang:
    node.setType(ctx, node.value.exprType)

  else:
    newError(errUnaryTypeMismatch, node.token, node.token.lexeme, typ)

proc isMutableExpression(ctx: Context, node: Expression): Option[bool] =
  case node.kind:
  of exprIdent:
    let name = node.token.lexeme
    if not ctx.symbolExists(name): 
      return none(bool)
    let sym = ctx.getSymbol(name)
    return some(sym.mutable and not IdentExpression(node).requireImmutable)

  of exprDeref:
    return ctx.isMutableExpression(DerefExpression(node).value)

  else:
    return some(false)

template isArithmetizable(typ: Type): bool =
  typ.isNumber()

template isСomparable(typ: Type): bool =
  typ.isNumber() or typ.eq(builtinType(Bool))

proc visitBinaryExpression(ctx: Context, node: BinaryExpression) =
  ctx.visit(node.left)
  ctx.visit(node.right)

  block typeSemantics:
    var typ = node.left.exprType
    let op  = node.token.kind

    block opSemantics:
      if   typ.isArithmetizable() and op in {tkPlus, tkMinus, tkStar, tkSlash, tkPercent}: 
        break opSemantics
      elif typ.isСomparable() and op in {tkGT, tkLT, tkGTE, tkLTE, tkEqualsEquals, tkBangEquals}: 
        typ = builtinType(Bool)
        break opSemantics
      elif typ.eq(builtinType(Bool)) and op in {tkAnd, tkOr, tkEqualsEquals, tkBangEquals}: 
        break opSemantics
      elif typ.eq(typeRegion) and op == tkAt: # DEPRECATED
        let isMutable = ctx.isMutableExpression(node.left)
        if isMutable.isSome and not isMutable.get():
          newError(errExpectedMutable, node.left.token)
          break typeSemantics
        typ = getPtrType(node.right.exprType, typ)
        break opSemantics

      newError(errBinaryTypeMismatch, node.token, node.token.lexeme, node.left.exprType, node.right.exprType)
      break typeSemantics
    
    node.setType(ctx, typ)

proc visitIdentExpression(ctx: Context, node: IdentExpression) =
  let name = node.token.lexeme

  if not ctx.symbolExists(name):
    newError(errUndeclaredSymbol, node.token, name)

  else:
    node.setType(ctx, ctx.getSymbol(name).symbolType)
    
  node.token.lexeme = node.token.lexeme

proc toArgTypes(ctx: Context, args: seq[Expression]): seq[ArgType] =
  result = newSeq[ArgType](args.len)
  for i, arg in args:
    var isMutable = ctx.isMutableExpression(arg)
    if not isMutable.isSome:
      isMutable = some(false)
    result[i] = ArgType(
      name: "",
      argType: arg.exprType,
      mutable: isMutable.get()
    )

proc visitCallExpression(ctx: Context, node: CallExpression) =
  ctx.visit(node.value)

  let valueType = node.value.exprType

  block semantics:
    if valueType.neq typeFunc:
      newError(errCallNonFunc, node.value.token, valueType)
      break semantics

    # TODO: overrides

    let expectedArgTypes = @[valueType]

    for arg in node.args:
      ctx.visit(arg)

    let givenArgTypes = ctx.toArgTypes(node.args)

    if givenArgTypes notin expectedArgTypes.mapIt(it.argTypes):
      let funcName = if node.value.kind == exprIdent:
        "'" & node.value.token.lexeme & "'"
      else:
        "function"
      
      newError(
        errNoMatchesCallForm, node.token,
        funcName, "T" & $givenArgTypes, expectedArgTypes.mapIt("- " & $it).join("\n")
      )
      break semantics

    node.setType(ctx, valueType.returnType)

proc visitDerefExpression(ctx: Context, node: DerefExpression) =
  ctx.visit(node.value)

  if node.value.exprType.neq typePtr:
    newError(errTypeMismatch, node.value.token, typePtr, node.value.exprType)

  else:
    node.setType(ctx, node.value.exprType.ptrBase)


# STATEMENTS


proc visitBlockStatement(ctx: Context, node: BlockStatement) =
  for stmt in node.statements:
    ctx.visit(stmt)

proc visitDeclarationStatement(ctx: Context, node: DeclarationStatement) =
  block semantics:
    ctx.visit(node.value)

    if node.value.exprType.neq(node.valueType) and 
      not (node.valueType.isNumber() and node.value.exprType.eq(builtinType(Number))):
      newError(errDeclarationTypeMismatch, node.token, node.valueType, node.name.lexeme, node.value.exprType)
      break semantics

    if ctx.symbolExistsInCurrentScope(node.name.lexeme):
      let symbol = ctx.getSymbol(node.name.lexeme)
      let symbolToken = symbol.definitionToken
      newError(errRedeclaration, node.name, symbolToken.lexeme, symbolToken.file, symbolToken.line, symbolToken.col)
      break semantics

    ctx.newSymbol(node.name, node.valueType, node.mutable)

proc visitAssignmentStatement(ctx: Context, node: AssignmentStatement) =
  ctx.visit(node.left)
  ctx.visit(node.right)
  
  block semantics:
    if node.left.exprType.eq(typeUnset):
      break semantics

    var isMutable = ctx.isMutableExpression(node.left)
    if isMutable.isSome and not isMutable.get():
      newError(errExpectedMutable, node.left.token)
      break semantics

    case node.left.kind:
    of exprIdent, exprDeref:
      if node.left.exprType.neq(node.right.exprType) and 
        not (node.left.exprType.isNumber() and node.right.exprType.eq(builtinType(Number))):
        newError(errTypeMismatch, node.token, node.left.exprType, node.right.exprType)

    else:
      echo "Unhandled assignment"
      quit(1)

proc visitBranchingStatement(ctx: Context, node: BranchingStatement) =
  ctx.visit(node.condition)
  if node.condition.exprType.neq(builtinType(Bool)):
    newError(errTypeMismatch, node.condition.token, node.condition.exprType, builtinType(Bool))
  
  else:
    ctx.pushScope()
    ctx.visit(node.ifBlock)
    ctx.popScope()
  
  for elifBranch in node.elifBranches:
    ctx.visit(elifBranch.cond)
    if elifBranch.cond.exprType.neq(builtinType(Bool)):
      newError(errTypeMismatch, elifBranch.cond.token, elifBranch.cond.exprType, builtinType(Bool))

    else:
      ctx.pushScope()
      ctx.visit(elifBranch.elifBlock)
      ctx.popScope()
  
  if node.elseBlock != nil:
    ctx.pushScope()
    ctx.visit(node.elseBlock)
    ctx.popScope()

proc visitWhileStatement(ctx: Context, node: WhileStatement) =
  ctx.visit(node.condition)
  if node.condition.exprType.neq(builtinType(Bool)):
    newError(errTypeMismatch, node.condition.token, node.condition.exprType, builtinType(Bool))

  else:
    ctx.pushScope()
    ctx.loopDepth.inc
    ctx.visit(node.whileBlock)
    ctx.loopDepth.dec
    ctx.popScope()

proc visitContinueStatement(ctx: Context, node: ContinueStatement) =
  if ctx.loopDepth == 0:
    newError(errControlFlowOutsideLoop, node.token, "continue")

proc visitBreakStatement(ctx: Context, node: BreakStatement) =
  if ctx.loopDepth == 0:
    newError(errControlFlowOutsideLoop, node.token, "break")

proc checkReturnPaths(stmt: Statement): bool =
  case stmt.kind:
  of stmtReturn:
    return true
  of stmtBlock:
    let blockStmt = BlockStatement(stmt)
    for s in blockStmt.statements:
      if checkReturnPaths(s):
        return true
    return false
  of stmtBranching:
    let branchStmt = BranchingStatement(stmt)
    var hasElse = branchStmt.elseBlock != nil
    for elifBranch in branchStmt.elifBranches:
      if checkReturnPaths(elifBranch.elifBlock):
        return true
    if branchStmt.ifBlock != nil and checkReturnPaths(branchStmt.ifBlock):
      return true
    if hasElse and checkReturnPaths(branchStmt.elseBlock):
      return true
    return false
  of stmtWhile:
    return false
  of stmtRegion:
    let regionStmt = RegionStatement(stmt)
    if checkReturnPaths(regionStmt.regionBlock):
      newError(errReturnInsideRegion, regionStmt.token)
    return false
  else:
    return false

proc toArgTypes*(args: seq[FuncArg]): seq[ArgType] =
  result = newSeq[ArgType](args.len)
  for i, arg in args:
    result[i] = ArgType(
      name: arg.argToken.lexeme,
      argType: arg.argType,
      mutable: arg.mutable
    )

proc visitFuncStatement(ctx: Context, node: FuncStatement) =
  if ctx.symbolExistsInCurrentScope(node.name.lexeme):
    let symbol = ctx.getSymbol(node.name.lexeme)
    newError(errRedeclaration, node.name, symbol.definitionToken.lexeme, symbol.definitionToken.file, symbol.definitionToken.line, symbol.definitionToken.col)
    return

  let funcType = getFuncType(node.args.toArgTypes(), node.returnType)
  ctx.newSymbol(node.name, funcType, false)
  let name = node.name.lexeme

  ctx.pushScope()
  ctx.funcDepth.inc
  
  for arg in node.args:
    ctx.newSymbol(arg.argToken, arg.argType, arg.mutable)
  
  let expected = ctx.expectedReturnType
  ctx.expectedReturnType = node.returnType

  if not ctx.expectedReturnType.eq(unsetType):
    if not checkReturnPaths(node.funcBlock):
      newError(errMissingReturn, node.name, name)

  ctx.visit(node.funcBlock)

  ctx.expectedReturnType = expected
  
  ctx.funcDepth.dec
  ctx.popScope()

proc visitReturnStatement(ctx: Context, node: ReturnStatement) =
  if ctx.funcDepth == 0:
    newError(errReturnOutsideFunc, node.token)
    return

  if ctx.expectedReturnType.eq(unsetType):
    if node.value != nil:
      newError(errReturnValue, node.token)
  else:
    if node.value == nil:
      newError(errReturnTypeMismatch, node.token, ctx.expectedReturnType, unsetType)
    else:
      ctx.visit(node.value)
      if node.value.exprType.neq(ctx.expectedReturnType):
        newError(errReturnTypeMismatch, node.token, ctx.expectedReturnType, node.value.exprType)

proc visitCallStatement(ctx: Context, node: CallStatement) =
  ctx.visit(node.expr)

proc visitRegionStatement(ctx: Context, node: RegionStatement) =
  ctx.pushScope()

  let temp = ctx.expectedRegion

  block semantics:
    if ctx.symbolExistsInCurrentScope(node.name.lexeme):
      let symbol = ctx.getSymbol(node.name.lexeme)
      let symbolToken = symbol.definitionToken
      newError(errRedeclaration, node.name, symbolToken.lexeme, symbolToken.file, symbolToken.line, symbolToken.col)
      break semantics

    ctx.expectedRegion = getRegionType(node.name)
    ctx.newSymbol(node.name, ctx.expectedRegion, true)

  ctx.visit(node.regionBlock)

  ctx.expectedRegion = temp
  
  ctx.popScope()

proc visit(ctx: Context, node: Expression) =
  case node.kind:
  of exprNumber: visitNumberExpression(ctx, NumberExpression(node))
  of exprBool: visitBoolExpression(ctx, BoolExpression(node))
  of exprUnary: visitUnaryExpression(ctx, UnaryExpression(node))
  of exprBinary: visitBinaryExpression(ctx, BinaryExpression(node))
  of exprIdent: visitIdentExpression(ctx, IdentExpression(node))
  of exprCall: visitCallExpression(ctx, CallExpression(node))
  of exprDeref: visitDerefExpression(ctx, DerefExpression(node))
  else: discard

proc visit(ctx: Context, node: Statement) =
  case node.kind:
  of stmtBlock: visitBlockStatement(ctx, BlockStatement(node))
  of stmtDeclaration: visitDeclarationStatement(ctx, DeclarationStatement(node))
  of stmtAssignment: visitAssignmentStatement(ctx, AssignmentStatement(node))
  of stmtBranching: visitBranchingStatement(ctx, BranchingStatement(node))
  of stmtWhile: visitWhileStatement(ctx, WhileStatement(node))
  of stmtContinue: visitContinueStatement(ctx, ContinueStatement(node))
  of stmtBreak: visitBreakStatement(ctx, BreakStatement(node))
  of stmtFunc: visitFuncStatement(ctx, FuncStatement(node))
  of stmtReturn: visitReturnStatement(ctx, ReturnStatement(node))
  of stmtCall: visitCallStatement(ctx, CallStatement(node))
  of stmtRegion: visitRegionStatement(ctx, RegionStatement(node))
  else: discard

macro newTypeSymbol(name: untyped): untyped =
  let strName = $name
  return quote do:
    newSymbolGet(ctx, Token(kind: tkType, lexeme: `strName`), getTypeType(getBaseType(`strName`)), false)

proc checkSemantics*(node: Statement) =
  var ctx = Context(
    currentScope: Scope(
      depth: 0,
      isGlobal: true,
      symbolTable: initTable[string, Symbol]()
    ),
    symbolScopeStack: initTable[string, seq[Scope]](),
  )

  ctx.builtins = newBuiltins[Symbol](
    IntSym    = newTypeSymbol(Int),
    NumberSym = newTypeSymbol(Number),
    BoolSym   = newTypeSymbol(Bool)
  )

  let regionToken = Token(kind: tkIdent, lexeme: "region")
  ctx.newSymbol(regionToken, getRegionType(regionToken), true)
  ctx.expectedRegion = getRegionType(regionToken)

  ctx.visit(node)
