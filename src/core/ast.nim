import tokens, types
import std/[macros]

template onnimnode*(kind: untyped) {.pragma.}
template comptime*() {.pragma.}


proc unstar(n: NimNode): NimNode =
  if n.kind == nnkPostfix:
    n[1]
  else:
    n

proc getTypeName(n: NimNode): NimNode =
  if n.kind == nnkPragmaExpr:
    return unstar(n[0])

  unstar(n)

proc getPragmas(n: NimNode): NimNode =
  if n.kind == nnkPragmaExpr:
    return n[1]

  newEmptyNode()

proc makeConstructor(typeName, kindValue, objectTy: NimNode): NimNode =
  let parentType = objectTy[1][0]
  var params: seq[NimNode] = @[]
  params.add typeName
  params.add newIdentDefs(
    ident("token"),
    ident("Token")
  )

  var body = newStmtList()
  body.add quote do:
    new(result)
  body.add quote do:
    result.kind = `kindValue`
  body.add quote do:
    result.token = token

  if objectTy[2].kind == nnkRecList:
    for field in objectTy[2]:
      if field.kind != nnkIdentDefs:
        continue
        
      let fieldType = field[1]
      let fieldName = unstar(field[0])
      params.add newIdentDefs(
        fieldName,
        fieldType
      )
      body.add quote do:
        result.`fieldName` = `fieldName`

  if eqIdent(parentType, "Expression"):
    params.add newIdentDefs(
      ident("exprType"),
      ident("Type"),
      quote do:
        types.getUnsetType()
    )

    body.add quote do:
      result.exprType = exprType

  result = newProc(
    name = postfix(ident("new" & $typeName), "*"),
    params = params,
    body = body
  )

proc isAstNode(objectTy: NimNode): bool =
  if objectTy[1].kind != nnkOfInherit:
    return false

  let parent = objectTy[1][0]
  eqIdent(parent, "Expression") or
  eqIdent(parent, "Statement")

macro constructors*(body: untyped): untyped =
  result = newStmtList()
  result.add body
  for section in body:
    if section.kind != nnkTypeSection:
      continue

    for typeDef in section:
      if typeDef.kind != nnkTypeDef:
        continue

      let nameNode = typeDef[0]
      let refNode = typeDef[2]

      if refNode.kind != nnkRefTy:
        continue

      let objectTy = refNode[0]

      if objectTy.kind != nnkObjectTy:
        continue

      if objectTy[1].kind != nnkOfInherit:
        continue
      if not isAstNode(objectTy):
        continue

      let pragmas = getPragmas(nameNode)
      var kindValue: NimNode = nil

      if pragmas.kind == nnkPragma:
        for p in pragmas:
          if p.kind == nnkExprColonExpr and
             eqIdent(p[0], "onnimnode"):
            kindValue = p[1]
            break

      if kindValue.isNil:
        error(
          "Missing {.onnimnode: ... .}",
          typeDef
        )

      result.add makeConstructor(
        getTypeName(nameNode),
        kindValue,
        objectTy
      )

constructors: 
  type
    NodeKind* = enum
      exprInvalid, exprNumber, exprUnary, exprBinary, exprBool, exprIdent,
      exprCall, exprDeref, exprKindType, exprFunc

      stmtInvalid, stmtBlock, stmtDeclaration, stmtAssignment, stmtBranching
      stmtWhile, stmtContinue, stmtBreak, stmtReturn, stmtCall, stmtDef
      stmtRegion

    Expression* = ref object of RootObj
      kind*: NodeKind
      token*: Token
      exprType*: Type
      comptime*: bool

    InvalidExpression* {.onnimnode: exprInvalid.} = ref object of Expression

    NumberExpression* {.onnimnode: exprNumber, comptime.} = ref object of Expression
      ## <number>
      ## number = token

    UnaryExpression* {.onnimnode: exprUnary.} = ref object of Expression
      ## <op> <value>
      ## op = token
      value*: Expression

    BinaryExpression* {.onnimnode: exprBinary.} = ref object of Expression
      ## <left> <op> <right>
      ## op = token
      left*: Expression
      right*: Expression

    BoolExpression* {.onnimnode: exprBool, comptime.} = ref object of Expression
      ## <bool>
      ## bool = token

    IdentExpression* {.onnimnode: exprIdent.} = ref object of Expression
      ## <ident>[!]
      ## ident = token
      requireImmutable*: bool = false
    
    CallExpression* {.onnimnode: exprCall.} = ref object of Expression
      ## <value> ( [<args>]* )
      ## "(" = token
      value*: Expression
      args*: seq[Expression]

    TypeExpression* {.onnimnode: exprKindType, comptime.} = ref object of Expression
      ## <type>
      ## type = token
      ## exprType has typeType
    
    FuncExpression* {.onnimnode: exprFunc.} = ref object of Expression
      ## <funcType> <funcBlock>
      ## do = token
      ## funcType = exprType
      funcBlock*: BlockStatement

    Statement* = ref object of RootObj
      kind*: NodeKind
      token*: Token
      comptime*: bool

    InvalidStatement* {.onnimnode: stmtInvalid.} = ref object of Statement

    BlockStatement* {.onnimnode: stmtBlock.} = ref object of Statement
      ## do [<stmt>]* <endToken>
      ## endToken = token
      statements*: seq[Statement]

    DeclarationStatement* {.onnimnode: stmtDeclaration.} = ref object of Statement
      ## <valueType> <name> "=" <value>
      ## "=" = token
      valueType*: Type
      name*: Token
      value*: Expression
      mutable*: bool

    AssignmentStatement* {.onnimnode: stmtAssignment.} = ref object of Statement
      ## <left> = <right>
      ## "=" = token
      left*: Expression
      right*: Expression

    BranchingStatement* {.onnimnode: stmtBranching.} = ref object of Statement
      ## if <cond> <block> [elif <cond> <block>]* [else <block>]
      ## if = token
      condition*: Expression
      ifBlock*: BlockStatement
      elifBranches*: seq[tuple[cond: Expression, elifBlock: BlockStatement]]
      elseBlock*: BlockStatement

    WhileStatement* {.onnimnode: stmtWhile.} = ref object of Statement
      ## while <cond> <block>
      ## while = token
      condition*: Expression
      whileBlock*: BlockStatement

    ContinueStatement* {.onnimnode: stmtContinue.} = ref object of Statement
      ## continue
      ## continue = token

    BreakStatement* {.onnimnode: stmtBreak.} = ref object of Statement
      ## break
      ## break = token

    ReturnStatement* {.onnimnode: stmtReturn.} = ref object of Statement
      ## return [value]
      ## return = token
      value*: Expression

    CallStatement* {.onnimnode: stmtCall.} = ref object of Statement
      ## <expr>
      ## "(" = token
      expr*: CallExpression

    DefStatement* {.onnimnode: stmtDef.} = ref object of Statement
      ## def <name> = <value>
      ## def = token
      name*: Token
      value*: Expression