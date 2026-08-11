import ../core/[ast, types]
import std/[strformat, sequtils, strutils]

const apiprefix = "onnim"

type
  Context = ref object
    indent = 0

template indent(ctx: Context): string = "  ".repeat(ctx.indent)
template apicall(name: string, args: varargs[string, `$`]): string = 
  apiprefix & "_" & name & "(" & args.join(", ") & ")"

proc nimtype(t: Type): string =
  case t.kind:
  of typeInt: return "int"
  of typeBool: return "bool"
  of typeFunc: 
    var args: string
    for i, argt in t.argTypes:
      args &= fmt"arg{i}: {nimtype(argt)}"
    if t.returnType.neq getUndefinedType():
      return fmt"proc ({args}): {t.returnType}"
    return fmt"proc ({args})"
  else: return fmt"auto #[{apiprefix} unsupported type]#"

proc visit(ctx: Context, node: Expression): string
proc visit(ctx: Context, node: Statement): string

proc visitNumberExpression(ctx: Context, node: NumberExpression): string =
  return node.token.lexeme

proc visitBoolExpression(ctx: Context, node: BoolExpression): string =
  return node.token.lexeme

proc visitUnaryExpression(ctx: Context, node: UnaryExpression): string =
  return "-" & ctx.visit(node.value)

proc visitBinaryExpression(ctx: Context, node: BinaryExpression): string =
  return fmt"{ctx.visit(node.left)} {node.token.lexeme} {ctx.visit(node.right)}"

proc visitIdentExpression(ctx: Context, node: IdentExpression): string =
  return node.token.lexeme

proc visitCallExpression(ctx: Context, node: CallExpression): string =
  let fn = ctx.visit(node.value)
  let args = node.args.mapIt( ctx.visit(it) ).join(", ")
  return fmt"{fn}({args})"

proc visitBlockStatement(ctx: Context, node: BlockStatement): string =
  result = ":\n"
  ctx.indent += 1
  for stmt in node.statements:
    result &= indent(ctx) & ctx.visit(stmt) & "\n"
  ctx.indent -= 1

proc visitDeclarationStatement(ctx: Context, node: DeclarationStatement): string =
  result = fmt"var {node.name.lexeme}: {nimtype(node.valueType)} = {ctx.visit(node.value)}"

proc visitAssignmentStatement(ctx: Context, node: AssignmentStatement): string =
  result = fmt"{ctx.visit(node.left)} = {ctx.visit(node.right)}"

proc visitBranchingStatement(ctx: Context, node: BranchingStatement): string =
  result = fmt"if {ctx.visit(node.condition)}{ctx.visit(node.ifBlock)}"
  for (cond, elifBlock) in node.elifBranches:
    result &= indent(ctx) & fmt"elif {ctx.visit(cond)}{ctx.visit(elifBlock)}"
  if node.elseBlock != nil:
    result &= indent(ctx) & fmt"else{ctx.visit(node.elseBlock)}"

proc visitWhileStatement(ctx: Context, node: WhileStatement): string =
  discard

proc visitContinueStatement(ctx: Context, node: ContinueStatement): string =
  discard

proc visitBreakStatement(ctx: Context, node: BreakStatement): string =
  discard

proc visitFuncStatement(ctx: Context, node: FuncStatement): string =
  discard

proc visitReturnStatement(ctx: Context, node: ReturnStatement): string =
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

proc visit(ctx: Context, node: Statement): string =
  case node.kind:
  of stmtBlock: return visitBlockStatement(ctx, BlockStatement(node))
  of stmtDeclaration: return visitDeclarationStatement(ctx, DeclarationStatement(node))
  of stmtAssignment: return visitAssignmentStatement(ctx, AssignmentStatement(node))
  of stmtBranching: return visitBranchingStatement(ctx, BranchingStatement(node))
  of stmtWhile: return visitWhileStatement(ctx, WhileStatement(node))
  of stmtContinue: return visitContinueStatement(ctx, ContinueStatement(node))
  of stmtBreak: return visitBreakStatement(ctx, BreakStatement(node))
  of stmtFunc: return visitFuncStatement(ctx, FuncStatement(node))
  of stmtReturn: return visitReturnStatement(ctx, ReturnStatement(node))
  else: discard

proc generateCode*(node: Statement): string =
  var ctx = Context()
  return "block `run`" & ctx.visit(node)