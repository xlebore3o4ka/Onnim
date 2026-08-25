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

    errUnsupportedDefinition
    
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

  of errUnsupportedDefinition:   "You can only define comptime or one of [@0] constructs, got @."

  of errExpectedMutable:         "Expression is immutable"

proc note(kind: ErrorKind): string =
  case kind:
  of errSyntaxChar:              ""
  of errSyntaxParenthesis:       "You missed the opposite side of the bracket ‘@0'"

  of errExpectedSyntax:          "The parser expected @0 but found @1"
  of errExpression:              ""
  of errStatement:               ""
  of errType:                    "The parser expected a type, instead of @0"

  of errUnaryTypeMismatch:       "Unary operator '@0' requires specific operand types"
  of errBinaryTypeMismatch:      "Binary operator '@0' cannot operate on types @1 and @2. Consider using type conversion"
  of errDeclarationTypeMismatch: ""
  of errTypeMismatch:            ""
  of errRedeclaration:           ""
  of errUndeclaredSymbol:        "Symbol '@0' is not defined. Check for typos, modules, or declaration order"

  of errControlFlowOutsideLoop:  ""

  of errReturnOutsideFunc:       ""
  of errReturnValue:             "Function without return type cannot return a value. Either add a return type or remove the value"
  of errReturnTypeMismatch:      ""
  of errCallNonFunc:             ""
  of errNoMatchesCallForm:       ""
  of errMissingReturn:           "Check the conditional branches, they may not return a value in some paths"
  of errReturnInsideRegion:      "Return statement is not allowed inside region blocks. Move the return statement to the end of the region statement."

  of errUnsupportedDefinition:   "You can only define a value that is known at the compilation time, or one of the following constructs [@0], but you tried to define @1"

  of errExpectedMutable:         "Expression is immutable. Declare the symbol as mutable or use a different approach"

proc tip(kind: ErrorKind): string =
  case kind:
  of errSyntaxChar:              ""
  of errSyntaxParenthesis:       "Each open bracket, such as `({[` must be closed with `)}]`"

  of errExpectedSyntax:          "Try replacing @0 with @1"
  of errExpression:              "An expression can be only a type literal (`10`, `true`), a defined identifier (`name`), mathematical calculations (`2 + 3`), etc."
  of errStatement:               "A statement can only be a symbol declaration (`Int x = 10`, `def func = ...`), a branch (`if cond do ... end`, `while cond do ... end`), " & 
    "flow control (`return ...`, `continue`, `break`), etc."
  of errType:                    "All types are capitalized. Type example: `Int`, `Bool`, `Number(Int a, Int b)`"

  of errUnaryTypeMismatch:       "A minus `-` or a plus `+` expects any `Number` after it. A bang `!` expects a `Bool`"
  of errBinaryTypeMismatch:      "Arithmetic operators `+-*/%` expect a `Number` on both sides. Boolean operators expect a `Bool` value"
  of errDeclarationTypeMismatch: "Try changing your definition to `@2 @0 = ...` or modify the expression so that it returns @1."
  of errTypeMismatch:            ""
  of errRedeclaration:           "Use a different name or different scope"
  of errUndeclaredSymbol:        "Symbols from libraries should be used with an explicit indication of the source, like `lib.name`"

  of errControlFlowOutsideLoop:  "Create a loop: `while cond do ... end`"

  of errReturnOutsideFunc:       "Define your function: `def add = Int(Int a, Int b) do ... end`"
  of errReturnValue:             "Use `return` to terminate the function execution early"
  of errReturnTypeMismatch:      "If you want the function to return nothing, use `Unset` as the return value."
  of errCallNonFunc:             "Define your function: `def add = Int(Int a, Int b) do ... end`"
  of errNoMatchesCallForm:       "Mutability definition difference: `sym$` - mutable; `sym!` - immutable. Defining a symbol makes it mutable, but function argument symbols are immutable by default"
  of errMissingReturn:           ""
  of errReturnInsideRegion:      ""

  of errUnsupportedDefinition:   ""

  of errExpectedMutable:         "Mutability definition difference: `sym$` - mutable; `sym!` - immutable. Defining a symbol makes it mutable, but function argument symbols are immutable by default"

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

import std/[strutils, strformat, terminal, tables]

var fileCache: Table[string, seq[string]]

proc getLine(file: string, line: Natural): string {.inline.} =
  if file notin fileCache:
    try:
      fileCache[file] = readFile(file).splitLines()
    except:
      return "<error reading file>"
  return fileCache[file][line-1]

proc red(text: string): string =
  result = ansiForegroundColorCode(fgRed) & text & ansiResetCode

proc green(text: string): string =
  result = ansiForegroundColorCode(fgGreen) & text & ansiResetCode

proc gray(text: string): string =
  result = ansiForegroundColorCode(fgWhite, bright=false) & text & ansiResetCode

proc cyan(text: string): string =
  result = ansiForegroundColorCode(fgCyan) & text & ansiResetCode

proc colorBackticks(s: string): string =
  result = ""
  var i = 0

  while i < s.len:
    if s[i] == '`':
      let closing = s.find('`', i + 1)

      if closing >= 0:
        result &= cyan(s[i..closing])
        i = closing + 1
      else:
        result &= cyan("`")
        inc i
    else:
      result.add(s[i])
      inc i

proc wrapText(text: string, prompt: static[string], maxLen: int = 80): string =
  const continuing = "\n  ?  "
  const prompt = "\n  ? " & prompt

  if text.len <= maxLen:
    return green(prompt) & colorBackticks(text)

  result = ""
  var remaining = text
  var isFirst = true

  while remaining.len > 0:
    var chunkLen = min(maxLen, remaining.len)

    let backtickPos = remaining.find('`')
    if backtickPos >= 0 and backtickPos < chunkLen:
      let closingPos = remaining.find('`', backtickPos + 1)
      if closingPos >= 0 and closingPos >= chunkLen:
        chunkLen = closingPos + 1

    if chunkLen < remaining.len:
      let lastSpace = remaining.rfind(' ', 0, chunkLen)
      if lastSpace > 0:
        chunkLen = lastSpace

    let chunk = colorBackticks(remaining[0..<chunkLen])
    remaining = remaining[chunkLen..^1].strip(leading = true)

    if isFirst:
      result &= green(prompt & continuing) & chunk
      isFirst = false
    else:
      result &= green(continuing) & chunk

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
    if note.len != 0:
      for i, arg in error.args:
        note = note.replace("@" & $i, arg)

      result &= wrapText(note, "Note:  ")

    var tip = error.kind.tip()
    if tip.len != 0:
      for i, arg in error.args:
        tip = tip.replace("@" & $i, arg)

      result &= wrapText(tip, "Tip:   ")