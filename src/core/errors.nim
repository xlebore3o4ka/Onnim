import tokens

type
  ErrorKind* = enum
    errSyntaxChar, errSyntaxParenthesis

    errExpectedSyntax, errExpression, errStatement, errType

    errUnaryTypeMismatch, errBinaryTypeMismatch, errDeclarationTypeMismatch, errTypeMismatch
    errRedeclaration, errUndeclaredSymbol

    errControlFlowOutsideLoop

    errReturnOutsideFunc, errReturnValue, errReturnTypeMismatch
    errCallNonFunc, errNoMatchesCallForm, errMissingReturn
    errReturnInsideRegion
    
    errExpectedMutable

  Error* = ref object
    kind*: ErrorKind
    file*: string
    line*: Positive
    col*: Positive
    len*: Positive
    args*: seq[string]
    message*: string

var errors*: seq[Error]

proc message(kind: ErrorKind): string =
  case kind:
  of errSyntaxChar:              "Unknown character: '@0'"
  of errSyntaxParenthesis:       "@0 parenthesis"

  of errExpectedSyntax:          "Expected @0, got @1"
  of errExpression:              "Invalid expression: @0"
  of errStatement:               "Invalid statement: @0"
  of errType:                    "Invalid type: @0"

  of errUnaryTypeMismatch:       "Type mismatch for the unary operator @0: @1"
  of errBinaryTypeMismatch:      "Type mismatch for the binary operator @0: @1 @0 @2"
  of errDeclarationTypeMismatch: "Expected @0 for @1, got @2"
  of errTypeMismatch:            "Expected @0, got @1"
  of errRedeclaration:           "Redeclaration symbol '@0', originally declared in @1(@2:@3)"
  of errUndeclaredSymbol:        "Undeclared symbol '@0'"

  of errControlFlowOutsideLoop:  "'@0' statement outside of loop"

  of errReturnOutsideFunc:       "Return statement outside of function"
  of errReturnValue:             "Function should not return anything"
  of errReturnTypeMismatch:      "Function returns @0, got @1"
  of errCallNonFunc:             "Cannot call non-function value of type '@0'"
  of errNoMatchesCallForm:       "No matches found for the expected @0 call form @1, expected one of:\n@2"
  of errMissingReturn:           "Function @0 does not return a value on all paths"
  of errReturnInsideRegion:      "Return statement is not allowed inside region"

  of errExpectedMutable:         "Expression is immutable"

proc note(kind: ErrorKind): string =
  case kind:
  of errSyntaxChar:              "Character '@0' is not supported in this context. Check the language specification for allowed characters"
  of errSyntaxParenthesis:       "You missed the opposite side of the bracket ‘@0'"

  of errExpectedSyntax:          "The parser expected @0 but found @1. Check the syntax rules for this construct"
  of errExpression:              "The expression containing @0 is not recognized as valid in this context"
  of errStatement:               "The statement containing @0 is not recognized as valid in this context"
  of errType:                    "The type containing '@0' is not valid in this context."

  of errUnaryTypeMismatch:       "Unary operator '@0' requires specific operand types. Check the operator's documentation for type requirements"
  of errBinaryTypeMismatch:      "Binary operator '@0' cannot operate on types @1 and @2. Consider using type conversion"
  of errDeclarationTypeMismatch: "Declaration of '@1' expects type @0 but the expression has type @2. Change either the type annotation or the expression"
  of errTypeMismatch:            "Expected type @0 but found @1. Consider using explicit type conversion"
  of errRedeclaration:           "Symbol '@0' was already declared at @1(@2:@3). Use a different name or different scope"
  of errUndeclaredSymbol:        "Symbol '@0' is not defined. Check for typos, imports, or declaration order"

  of errControlFlowOutsideLoop:  "The '@0' statement can only be used inside loops. Move it inside a loop or remove it"

  of errReturnOutsideFunc:       "Return statement appears outside any function. Check function boundaries"
  of errReturnValue:             "Function without return type cannot return a value. Either add a return type or remove the value"
  of errReturnTypeMismatch:      "Function expects to return @0 but the expression has type @1. Adjust the return expression or function signature"
  of errCallNonFunc:             "Value of type @0 is not callable. Only functions and procedures can be called"
  of errNoMatchesCallForm:       "No overloaded @0 matches the expected call form @1. Check the available overloads above"
  of errMissingReturn:           "Function '@0' may not return a value on all paths. Ensure all branches return a value"
  of errReturnInsideRegion:      "Return statement is not allowed inside region blocks"

  of errExpectedMutable:         "Expression is immutable. Declare the variable as mutable or use a different approach"

proc newError*(kind: ErrorKind, file: string, line, col: Positive, len: Positive, args: varargs[string, `$`]) {.inline.} =
  errors.add(Error(
    kind: kind,
    file: file,
    line: line,
    col: col,
    len: len,
    args: @args,
    message: kind.message
  ))

proc newError*(kind: ErrorKind, token: Token, args: varargs[string, `$`]) {.inline.} =
  errors.add(Error(
    kind: kind,
    file: token.file,
    line: token.line,
    col: token.col,
    len: token.len,
    args: @args,
    message: kind.message
  ))

import std/[strutils, strformat, terminal]

proc getLine(file: string, line: Natural): string {.inline.} =
  try:
    readFile(file).splitLines()[line-1]
  except:
    "<error reading file>"

proc red(text: string): string =
  result = ansiForegroundColorCode(fgRed) & text & ansiResetCode

proc green(text: string): string =
  result = ansiForegroundColorCode(fgGreen) & text & ansiResetCode

proc gray(text: string): string =
  result = ansiForegroundColorCode(fgWhite, bright=false) & text & ansiResetCode

proc wrapText(text: string, maxLen: int = 80): string =
  const continuing = "\n  ?  "
  const prompt = "\n  ? Note:  "

  if text.len <= maxLen:
    return green(prompt) & text
  
  result = ""
  var remaining = text
  var isFirst = true
  
  while remaining.len > 0:
    var chunkLen = min(maxLen, remaining.len)
    if chunkLen < remaining.len:
      var lastSpace = remaining.rfind(' ', 0, chunkLen)
      if lastSpace > 0:
        chunkLen = lastSpace
    
    let chunk = remaining[0..<chunkLen]
    remaining = remaining[chunkLen..^1].strip(leading=true)
    
    if isFirst:
      result &= green(prompt) & continuing & chunk
      isFirst = false
    else:
      result &= continuing & chunk
  
  return result

proc format*(error: Error, short: bool): string =
  var msg = error.message
  for i, arg in error.args:
    msg = msg.replace("@" & $i, arg)
  
  let errorMsg = $error.kind & ":"
  result = fmt"{error.file}({error.col}:{error.line}) {red(errorMsg)} {msg}"
  
  if not short:
    let line = getLine(error.file, error.line)
    let start = error.col - 1
    let finish = min(start + error.len - 1, line.high)
    
    let before = line[0..start-1]
    let highlighted = red(line[start..finish])
    let after = line[finish+1..^1]
    
    result &= "\n  |  " & " ".repeat(start) & gray("_".repeat(max(finish - start + 1, 1)))
    result &= "\n  |  " & before & highlighted & after

    var note = error.kind.note()
    for i, arg in error.args:
      note = note.replace("@" & $i, arg)

    result &= wrapText(note)