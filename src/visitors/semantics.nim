import ../core/[ast, types, tokens, errors]
import std/[tables, sequtils, strutils, strformat, options, macros]
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

proc unwrapType(ctx: Context, typ: Type, error: static[bool] = true): Option[Type] =
  if typ.kind == typeBuiltin:
    return some(typ)

  elif typ.kind == typeBase: 
    if not ctx.symbolExists(typ.name):
      when error:
        newError(errUndeclaredSymbol, typ.token, typ.name)
      return none(Type)
    let sym = ctx.getSymbol(typ.name)
    return ctx.unwrapType(sym.symbolType, error)

  elif typ.kind == typeType:
    let unwrapped = ctx.unwrapType(typ.baseType, error)
    if unwrapped.isNone: return none(Type)
    return some(unwrapped.get())

  elif typ.kind == typeFunc:
    var newArgTypes: seq[ArgType]
    for arg in typ.argTypes:
      let unwrapped = ctx.unwrapType(arg.argType, error)
      if unwrapped.isNone: return none(Type)
      newArgTypes.add(ArgType(name: arg.name, argType: unwrapped.get(), mutable: arg.mutable))
    
    let returnUnwrapped = ctx.unwrapType(typ.returnType, error)
    if returnUnwrapped.isNone: return none(Type)
    
    return some(getFuncType(newArgTypes, returnUnwrapped.get()))

  else:
    return none(Type)

proc unwrappedType(ctx: Context, typ: Type): string =
  let unwrapped = ctx.unwrapType(typ, false).get(getUnsetType())
  if typ.kind == typeBase: 
    let defined = if unwrapped.kind != typeUnset: "alias " & $unwrapped
      else: "which undefined"
    return fmt"{typ.name} {defined}"
  return $unwrapped

proc eq*(ctx: Context, a: Type, b: Type): bool

proc eq*(ctx: Context, a: seq[ArgType], b: seq[ArgType]): bool =
  if a.len != b.len: return false
  for n in 0..a.high:
    let arg_a = a[n]
    let arg_b = b[n]
    if not(ctx.eq(arg_a.argType, arg_b.argType) and arg_a.mutable == arg_b.mutable):
      return false
  return true

proc eq*(ctx: Context, a: Type, b: Type): bool =
  var aTypeOption = ctx.unwrapType(a)
  if not aTypeOption.isSome: return false
  var aType = aTypeOption.get()

  var bTypeOption = ctx.unwrapType(b)
  if not bTypeOption.isSome: return false
  var bType = bTypeOption.get()

  if types.eq(aType, builtinType(Number)) and (
    types.eq(bType, builtinType(Number)) or 
    types.eq(bType, builtinType(Int))
  ): return true

  if types.eq(bType, builtinType(Number)) and ( 
    types.eq(aType, builtinType(Int))
  ): return true

  if aType.kind == typeFunc and bType.kind == typeFunc:
    if aType.argTypes.len != bType.argTypes.len: return false

    if not ctx.eq(aType.argTypes, bType.argTypes): return false

    return ctx.eq(aType.returnType, bType.returnType)

  return types.eq(aType, bType)

template neq*(ctx: Context, a: Type, b: Type): bool =
  not ctx.eq(a, b)

proc visitNumberExpression(ctx: Context, node: NumberExpression) =
  node.comptime = true
  node.setType(ctx, builtinType(Number))

proc visitBoolExpression(ctx: Context, node: BoolExpression) =
  node.comptime = true
  node.setType(ctx, builtinType(Bool))

proc visitUnaryExpression(ctx: Context, node: UnaryExpression) =
  ctx.visit(node.value)
  let op  = node.token.kind
  let typ = node.value.exprType

  if ctx.eq(typ, builtinType(Number)) and op in {tkPlus, tkMinus}:
    node.setType(ctx, node.value.exprType)

  elif ctx.eq(typ, builtinType(Bool)) and op == tkBang:
    node.setType(ctx, node.value.exprType)

  else:
    newError(errUnaryTypeMismatch, node.token, node.token.lexeme, ctx.unwrappedType(typ))

proc isMutableExpression(ctx: Context, node: Expression): Option[bool] =
  case node.kind:
  of exprIdent:
    let name = node.token.lexeme
    if not ctx.symbolExists(name): 
      return none(bool)
    let sym = ctx.getSymbol(name)
    return some(sym.mutable and not IdentExpression(node).requireImmutable)

  else:
    return some(false)

template isArithmetizable(typ: Type): bool =
  ctx.eq(typ, builtinType(Number))

template isСomparable(typ: Type): bool =
  ctx.eq(typ, builtinType(Number)) or ctx.eq(typ, builtinType(Bool))

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
      elif ctx.eq(typ, builtinType(Bool)) and op in {tkAnd, tkOr, tkEqualsEquals, tkBangEquals}: 
        break opSemantics

      newError(errBinaryTypeMismatch, node.token, node.token.lexeme, ctx.unwrappedType(node.left.exprType), ctx.unwrappedType(node.right.exprType))
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
      newError(errCallNonFunc, node.value.token, ctx.unwrappedType(valueType))
      break semantics

    let expectedArgTypes = @[valueType]

    for arg in node.args:
      ctx.visit(arg)

    let givenArgTypes = ctx.toArgTypes(node.args)

    var givenArgTypesNotInExpectedArgTypes = true
    for argTypes in expectedArgTypes.mapIt(it.argTypes):
      if ctx.eq(givenArgTypes, argTypes): 
        givenArgTypesNotInExpectedArgTypes = false
        break
    if givenArgTypesNotInExpectedArgTypes:
      let funcName = if node.value.kind == exprIdent:
        "'" & node.value.token.lexeme & "'"
      else:
        "function"
      
      newError(
        errNoMatchesCallForm, node.token,
        funcName, "T" & $givenArgTypes, expectedArgTypes.mapIt("- " & $ctx.unwrappedType(it)).join("\n")
      )
      break semantics

    node.setType(ctx, valueType.returnType)

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
  else:
    return false

proc visitFuncExpression(ctx: Context, node: FuncExpression) =
  ctx.pushScope()
  ctx.funcDepth.inc

  let expected = ctx.expectedReturnType
  ctx.expectedReturnType = node.exprType.returnType

  if not ctx.eq(ctx.expectedReturnType, getUnsetType()):
    if not checkReturnPaths(node.funcBlock):
      newError(errMissingReturn, node.token, ctx.unwrappedType(node.exprType))

  for arg in node.exprType.argTypes:
    ctx.newSymbol(copy(node.token, kind = tkIdent, lexeme = arg.name), arg.argType, arg.mutable)

  ctx.pushScope()  # The second level of nesting is needed to allow redefining (shadowing) the arguments
  ctx.visit(node.funcBlock)
  ctx.popScope()

  ctx.expectedReturnType = expected

  ctx.funcDepth.dec
  ctx.popScope()

proc visitBlockStatement(ctx: Context, node: BlockStatement) =
  for stmt in node.statements:
    ctx.visit(stmt)

proc visitDeclarationStatement(ctx: Context, node: DeclarationStatement) =
  block semantics:
    ctx.visit(node.value)

    if ctx.neq(node.value.exprType, node.valueType):
      newError(errDeclarationTypeMismatch, node.token, ctx.unwrappedType(node.valueType), node.name.lexeme, ctx.unwrappedType(node.value.exprType))
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
      if ctx.neq(node.left.exprType, node.right.exprType):
        newError(errTypeMismatch, node.token, ctx.unwrappedType(node.left.exprType), ctx.unwrappedType(node.right.exprType))

    else:
      echo "Unhandled assignment"
      quit(1)

proc visitBranchingStatement(ctx: Context, node: BranchingStatement) =
  ctx.visit(node.condition)
  if ctx.neq(node.condition.exprType, builtinType(Bool)):
    newError(errTypeMismatch, node.condition.token, ctx.unwrappedType(node.condition.exprType), builtinType(Bool))
  
  else:
    ctx.pushScope()
    ctx.visit(node.ifBlock)
    ctx.popScope()
  
  for elifBranch in node.elifBranches:
    ctx.visit(elifBranch.cond)
    if ctx.neq(elifBranch.cond.exprType, builtinType(Bool)):
      newError(errTypeMismatch, elifBranch.cond.token, ctx.unwrappedType(elifBranch.cond.exprType), builtinType(Bool))

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
  if ctx.neq(node.condition.exprType, builtinType(Bool)):
    newError(errTypeMismatch, node.condition.token, ctx.unwrappedType(node.condition.exprType), builtinType(Bool))

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

proc visitReturnStatement(ctx: Context, node: ReturnStatement) =
  if ctx.funcDepth == 0:
    newError(errReturnOutsideFunc, node.token)
    return

  if ctx.expectedReturnType.eq(getUnsetType()):
    if node.value != nil:
      newError(errReturnValue, node.token)
  else:
    if node.value == nil:
      newError(errReturnTypeMismatch, node.token, ctx.unwrappedType(ctx.expectedReturnType), getUnsetType())
    else:
      ctx.visit(node.value)
      if ctx.neq(node.value.exprType, ctx.expectedReturnType):
        newError(errReturnTypeMismatch, node.token, ctx.unwrappedType(ctx.expectedReturnType), ctx.unwrappedType(node.value.exprType))

proc visitCallStatement(ctx: Context, node: CallStatement) =
  ctx.visit(node.expr)

proc visitDefStatement(ctx: Context, node: DefStatement) =
  const specials = {exprFunc, exprKindType}

  block semantics:

    if ctx.symbolExistsInCurrentScope(node.name.lexeme):
      let symbol = ctx.getSymbol(node.name.lexeme)
      let symbolToken = symbol.definitionToken
      newError(errRedeclaration, node.name, symbolToken.lexeme, symbolToken.file, symbolToken.line, symbolToken.col)
      break semantics

    if node.value.exprType.kind.eq(typeFunc):
      ctx.newSymbol(node.name, node.value.exprType, false)

    ctx.visit(node.value)

    if node.value.kind notin specials and not node.value.comptime:
      let constructs = [
        fmt"{typeFunc} do ... end",
        fmt"{typeType}"
      ]
      newError(errUnsupportedDefinition, node.value.token, constructs.mapIt(fmt"- def {node.name.lexeme} = " & it).join("\n"), ctx.unwrappedType(node.value.exprType))
      break semantics

    if node.value.kind notin specials or node.value.kind == exprKindType:
      node.comptime = true
      var symType = ctx.unwrapType(node.value.exprType)
      if symType.isSome:
        ctx.newSymbol(node.name, symType.get(), false)

proc visit(ctx: Context, node: Expression) =
  case node.kind:
  of exprNumber: visitNumberExpression(ctx, NumberExpression(node))
  of exprBool: visitBoolExpression(ctx, BoolExpression(node))
  of exprUnary: visitUnaryExpression(ctx, UnaryExpression(node))
  of exprBinary: visitBinaryExpression(ctx, BinaryExpression(node))
  of exprIdent: visitIdentExpression(ctx, IdentExpression(node))
  of exprCall: visitCallExpression(ctx, CallExpression(node))
  of exprFunc: visitFuncExpression(ctx, FuncExpression(node))
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
  of stmtReturn: visitReturnStatement(ctx, ReturnStatement(node))
  of stmtCall: visitCallStatement(ctx, CallStatement(node))
  of stmtDef: visitDefStatement(ctx, DefStatement(node))
  else: discard

macro newTypeSymbol(name: untyped): untyped =
  let strName = $name
  return quote do:
    newSymbolGet(ctx, Token(kind: tkType, lexeme: `strName`, file: "std/builtins"), getTypeType(getBuiltinType(`strName`)), false)

macro newSymbol(name: untyped, typ: Type): untyped =
  let strName = $name
  return quote do:
    newSymbolGet(ctx, Token(kind: tkIdent, lexeme: `strName`, file: "std/builtins"), `typ`, false)

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
    BoolSym   = newTypeSymbol(Bool),
    wtiteSym  = newSymbol(write, getFuncType(@[ArgType(name: "a", argType: getBaseType("Number"), mutable: false)], getUnsetType()))
  )

  ctx.visit(node)