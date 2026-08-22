import ../core/[ast, types, tokens]
import std/[strformat, sequtils, strutils, os]

const apiprefix = "onnim"

type
  Context = ref object
    indent = 0

template indent(ctx: Context): string = "  ".repeat(ctx.indent)
template apicall(name: string, args: varargs[string, `$`], module: string = ""): string = 
  apiprefix & (if module != "": "_" & module else: "") & "_" & name & "(" & args.join(", ") & ")"

proc nimtype(t: Type): string =
  case t.kind:
  of typeInt: return "int"
  of typeBool: return "bool"
  of typeFunc: 
    var args: string
    for i, argt in t.argTypes:
      if i != 0: args &= ", "
      args &= fmt"arg{i}: {nimtype(argt)}"
    if t.returnType.neq getUndefinedType():
      return fmt"proc ({args}): {t.returnType}"
    return fmt"proc ({args})"
  of typePtr:
    return fmt"ptr {nimtype(t.ptrBase)}"
  else: 
    echo "Unhandled type: ", t 
    quit(1)

proc visit(ctx: Context, node: Expression): string
proc visit(ctx: Context, node: Statement): string

proc visitNumberExpression(ctx: Context, node: NumberExpression): string =
  return node.token.lexeme

proc visitBoolExpression(ctx: Context, node: BoolExpression): string =
  return node.token.lexeme

proc visitUnaryExpression(ctx: Context, node: UnaryExpression): string =
  if node.token.kind == tkAt:
    return apicall("addArena", ctx.visit(node.value), module = "system")
  return node.token.lexeme & ctx.visit(node.value)

proc visitBinaryExpression(ctx: Context, node: BinaryExpression): string =
  var op = node.token.lexeme
  if node.token.kind == tkPercent:
    op = "mod"
  return fmt"{ctx.visit(node.left)} {op} {ctx.visit(node.right)}"

proc visitIdentExpression(ctx: Context, node: IdentExpression): string =
  return node.token.lexeme

proc visitCallExpression(ctx: Context, node: CallExpression): string =
  let fn = ctx.visit(node.value)
  let args = node.args.mapIt( ctx.visit(it) ).join(", ")
  return fmt"{fn}({args})"

proc visitDerefExpression(ctx: Context, node: DerefExpression): string =
  return ctx.visit(node.value) & "[]"


# STATEMENTS


proc visitBlockStatement(ctx: Context, node: BlockStatement): string =
  result = "\n"
  ctx.indent += 1
  for stmt in node.statements:
    result &= indent(ctx) & ctx.visit(stmt) & "\n"
  ctx.indent -= 1

proc visitDeclarationStatement(ctx: Context, node: DeclarationStatement): string =
  result = fmt"var {node.name.lexeme}: {nimtype(node.valueType)} = {ctx.visit(node.value)}"

proc visitAssignmentStatement(ctx: Context, node: AssignmentStatement): string =
  result = fmt"{ctx.visit(node.left)} = {ctx.visit(node.right)}"

proc visitBranchingStatement(ctx: Context, node: BranchingStatement): string =
  result = fmt"if {ctx.visit(node.condition)}:{ctx.visit(node.ifBlock)}"
  for (cond, elifBlock) in node.elifBranches:
    result &= indent(ctx) & fmt"elif {ctx.visit(cond)}:{ctx.visit(elifBlock)}"
  if node.elseBlock != nil:
    result &= indent(ctx) & fmt"else:{ctx.visit(node.elseBlock)}"

proc visitWhileStatement(ctx: Context, node: WhileStatement): string =
  result = fmt"while {ctx.visit(node.condition)}:{ctx.visit(node.whileBlock)}"

proc visitContinueStatement(ctx: Context, node: ContinueStatement): string =
  result = "continue"

proc visitBreakStatement(ctx: Context, node: BreakStatement): string =
  result = "break"

proc visitFuncStatement(ctx: Context, node: FuncStatement): string =
  result = fmt"proc {node.name.lexeme}("
  for i, arg in node.args:
    if i != 0: result &= ", "
    result &= fmt"{arg.argToken.lexeme}: {nimtype(arg.argType)}"
  result &= ")"
  if node.returnType != getUndefinedType():
    result &= fmt": {nimtype(node.returnType)}"
  result &= fmt" = {ctx.visit(node.funcBlock)}"

proc visitReturnStatement(ctx: Context, node: ReturnStatement): string =
  if node.value == nil:
    return "return"
  result = fmt"return {ctx.visit(node.value)}"

proc visitCallStatement(ctx: Context, node: CallStatement): string =
  return (if node.expr.exprType.neq getUndefinedType(): "discard " else: "") & ctx.visit(node.expr)

proc visit(ctx: Context, node: Expression): string =
  case node.kind:
  of exprNumber: return visitNumberExpression(ctx, NumberExpression(node))
  of exprBool: return visitBoolExpression(ctx, BoolExpression(node))
  of exprUnary: return visitUnaryExpression(ctx, UnaryExpression(node))
  of exprBinary: return visitBinaryExpression(ctx, BinaryExpression(node))
  of exprIdent: return visitIdentExpression(ctx, IdentExpression(node))
  of exprCall: return visitCallExpression(ctx, CallExpression(node))
  of exprDeref: return visitDerefExpression(ctx, DerefExpression(node))
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
  of stmtCall: return visitCallStatement(ctx, CallStatement(node))
  else: discard

proc generateCode*(node: Statement): string =
  var ctx = Context()
  return &"import {currentSourcePath().absolutePath()}/src/std/[system]\nblock `transpiled`:" & ctx.visit(node)