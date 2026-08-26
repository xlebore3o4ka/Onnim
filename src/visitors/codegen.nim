import ../core/[ast, types, tokens]
import std/[strformat, sequtils, strutils, os]
import builtins

const apiprefix = "onnim"

type
  Context = ref object
    indent = 0

template indent(ctx: Context): string = "  ".repeat(ctx.indent)

template apicall(name: string, args: varargs[string, `$`], module: string = "", types: seq[string] = @[]): string = 
  apiprefix & (
    if module != "": "_" & module 
    else: ""
  ) & "_" & name & (
    if types.len != 0: "[" & types.join(", ") & "]"
    else: ""
  ) & "(" & args.join(", ") & ")"

template ident(name: string): string = "s_" & name.replace("_", "_U")

proc nimtype(t: Type): string =
  case t.kind:
  of typeFunc: 
    var args: string
    for i, argt in t.argTypes:
      if i != 0: args &= ", "
      let isVar = if argt.mutable: " var" else: ""
      args &= fmt"{ident(argt.name)}:{isVar} {nimtype(argt.argType)}"
    if t.returnType.neq(getUnsetType()):
      return fmt"proc ({args}): {nimtype(t.returnType)}"
    return fmt"proc ({args})"
  of typePtr:
    return fmt"uint #[ptr {nimtype(t.ptrBase)}]#"
  of typeBase:
    return "`" & t.name & "`"
  of typeType:
    return nimtype(t.baseType)
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
  return node.token.lexeme & ctx.visit(node.value)

proc visitBinaryExpression(ctx: Context, node: BinaryExpression): string =
  var op = node.token.lexeme
  if node.token.kind == tkPercent:
    op = "mod"
  elif node.token.kind == tkAt:
    return apicall(
      "addArena", 
      ctx.visit(node.left), ctx.visit(node.right), 
      module = "system",
      types = @[nimtype(node.right.exprType)]
    )
  return fmt"{ctx.visit(node.left)} {op} {ctx.visit(node.right)}"

proc visitIdentExpression(ctx: Context, node: IdentExpression): string =
  return ident(node.token.lexeme)

proc visitCallExpression(ctx: Context, node: CallExpression): string =
  let fn = ctx.visit(node.value)
  let args = node.args.mapIt( ctx.visit(it) ).join(", ")
  return fmt"{fn}({args})"

proc visitDerefExpression(ctx: Context, node: DerefExpression): string =
  return apicall("getArena", 
    ident(node.value.exprType.ptrRegion.regionName.lexeme), ctx.visit(node.value), 
    module = "system", 
    types = @[nimtype(node.value.exprType.ptrBase)]
  )

proc visitFuncExpression(ctx: Context, node: FuncExpression): string =
  result = fmt"proc ("
  for i, arg in node.exprType.argTypes:
    if i != 0: result &= ", "
    let varPrefix = if arg.mutable: "var " else: ""
    result &= fmt"{ident(arg.name)}: {varPrefix}{nimtype(arg.argType)}"
  result &= ")"
  if node.exprType.returnType.neq(getUnsetType()):
    result &= fmt": {nimtype(node.exprType.returnType)}"
  result &= fmt" = {ctx.visit(node.funcBlock)}"


# STATEMENTS


proc visitBlockStatement(ctx: Context, node: BlockStatement): string =
  result = "\n"
  ctx.indent += 1
  for i, stmt in node.statements:
    if i != 0:
      result &= "\n"
    result &= indent(ctx) & ctx.visit(stmt)
  ctx.indent -= 1

proc visitDeclarationStatement(ctx: Context, node: DeclarationStatement): string =
  let keyword = if node.mutable: "var" else: "let"
  result = fmt"{keyword} {ident(node.name.lexeme)}: {nimtype(node.valueType)} = {ctx.visit(node.value)}"

proc visitAssignmentStatement(ctx: Context, node: AssignmentStatement): string =
  result = fmt"{ctx.visit(node.left)} = {ctx.visit(node.right)}"

proc visitBranchingStatement(ctx: Context, node: BranchingStatement): string =
  result = fmt"if {ctx.visit(node.condition)}:{ctx.visit(node.ifBlock)}"
  for (cond, elifBlock) in node.elifBranches:
    result &= "\n" & indent(ctx) & fmt"elif {ctx.visit(cond)}:{ctx.visit(elifBlock)}"
  if node.elseBlock != nil:
    result &= "\n" & indent(ctx) & fmt"else:{ctx.visit(node.elseBlock)}"

proc visitWhileStatement(ctx: Context, node: WhileStatement): string =
  result = fmt"while {ctx.visit(node.condition)}:{ctx.visit(node.whileBlock)}"

proc visitContinueStatement(ctx: Context, node: ContinueStatement): string =
  result = "continue"

proc visitBreakStatement(ctx: Context, node: BreakStatement): string =
  result = "break"
  
proc visitReturnStatement(ctx: Context, node: ReturnStatement): string =
  if node.value == nil:
    return "return"
  result = fmt"return {ctx.visit(node.value)}"

proc visitCallStatement(ctx: Context, node: CallStatement): string =
  return (if node.expr.exprType.neq(getUnsetType()): "discard " else: "") & ctx.visit(node.expr)

proc visitRegionStatement(ctx: Context, node: RegionStatement): string =
  return apicall("region", node.name.lexeme, module="system") & ":" & ctx.visit(node.regionBlock)

proc visitDefStatement(ctx: Context, node: DefStatement): string =
  if node.value.kind == exprFunc:
    let fn = FuncExpression(node.value)
    result = "proc " & ident(node.name.lexeme) & "(" 
    for i, arg in fn.exprType.argTypes:
      if i != 0: result &= ", "
      let varPrefix = if arg.mutable: "var " else: ""
      result &= fmt"{ident(arg.name)}: {varPrefix}{nimtype(arg.argType)}"
    result &= ")"
    if fn.exprType.returnType.neq(getUnsetType()):
      result &= fmt": {nimtype(fn.exprType.returnType)}"
    result &= fmt" = {ctx.visit(fn.funcBlock)}"
  elif node.value.kind == exprKindType:
    let ty = TypeExpression(node.value).exprType
    result = fmt"type `{node.name.lexeme}` = {nimtype(ty)}"

proc visit(ctx: Context, node: Expression): string =
  case node.kind:
  of exprNumber: return visitNumberExpression(ctx, NumberExpression(node))
  of exprBool: return visitBoolExpression(ctx, BoolExpression(node))
  of exprUnary: return visitUnaryExpression(ctx, UnaryExpression(node))
  of exprBinary: return visitBinaryExpression(ctx, BinaryExpression(node))
  of exprIdent: return visitIdentExpression(ctx, IdentExpression(node))
  of exprCall: return visitCallExpression(ctx, CallExpression(node))
  of exprDeref: return visitDerefExpression(ctx, DerefExpression(node))
  of exprFunc: return visitFuncExpression(ctx, FuncExpression(node))
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
  of stmtReturn: return visitReturnStatement(ctx, ReturnStatement(node))
  of stmtCall: return visitCallStatement(ctx, CallStatement(node))
  of stmtRegion: return visitRegionStatement(ctx, RegionStatement(node))
  of stmtDef: return visitDefStatement(ctx, DefStatement(node))
  else: discard

proc generateCode*(node: Statement, stdpath: string): string =
  var ctx = Context()

  let builtinsPath = stdpath / "builtins.nim"
  writeFile(builtinsPath, generateBuiltins())
  
  result = &"""import {stdpath}/[system, builtins]

var s_region = onnim_system_newArena()  # DEPRECATED

block transpiled:""" & ctx.visit(node) & "\n"
  ctx.indent.inc
  result &= ctx.indent()