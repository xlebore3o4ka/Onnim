import ../core/[ast]

type
  Context = ref object
    code: string

proc visit(ctx: Context, node: Expression): string
proc visit(ctx: Context, node: Statement)

proc visitNumberExpression(ctx: Context, node: NumberExpression): string =
  discard

proc visitBoolExpression(ctx: Context, node: BoolExpression): string =
  discard

proc visitUnaryExpression(ctx: Context, node: UnaryExpression): string =
  discard

proc visitBinaryExpression(ctx: Context, node: BinaryExpression): string =
  discard

proc visitIdentExpression(ctx: Context, node: IdentExpression): string =
  discard

proc visitCallExpression(ctx: Context, node: CallExpression): string =
  discard

proc visitBlockStatement(ctx: Context, node: BlockStatement) =
  discard

proc visitDeclarationStatement(ctx: Context, node: DeclarationStatement) =
  discard

proc visitAssignmentStatement(ctx: Context, node: AssignmentStatement) =
  discard

proc visitBranchingStatement(ctx: Context, node: BranchingStatement) =
  discard

proc visitWhileStatement(ctx: Context, node: WhileStatement) =
  discard

proc visitContinueStatement(ctx: Context, node: ContinueStatement) =
  discard

proc visitBreakStatement(ctx: Context, node: BreakStatement) =
  discard

proc visitFuncStatement(ctx: Context, node: FuncStatement) =
  discard

proc visitReturnStatement(ctx: Context, node: ReturnStatement) =
  discard

proc visit(ctx: Context, node: Expression): string =
  case node.kind:
  of exprNumber: return visitNumberExpression(ctx, NumberExpression(node))
  of exprBool: return visitBoolExpression(ctx, BoolExpression(node))
  of exprUnary: return visitUnaryExpression(ctx, UnaryExpression(node))
  of exprBinary: return visitBinaryExpression(ctx, BinaryExpression(node))
  of exprIdent: return visitIdentExpression(ctx, IdentExpression(node))
  of exprCall: return visitCallExpression(ctx, CallExpression(node))
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
  else: discard

proc generateCode*(node: Statement): string =
  var ctx = Context()
  ctx.visit(node)
  return ctx.code