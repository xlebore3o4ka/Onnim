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

var errors*: seq[Error]

proc newError*(kind: ErrorKind, file: string, line, col: Positive, len: Positive, args: varargs[string, `$`]) {.inline.} =
  errors.add(Error(
    kind: kind,
    file: file,
    line: line,
    col: col,
    len: len,
    args: @args
  ))

proc newError*(kind: ErrorKind, token: Token, args: varargs[string, `$`]) {.inline.} =
  errors.add(Error(
    kind: kind,
    file: token.file,
    line: token.line,
    col: token.col,
    len: token.len,
    args: @args
  ))

import std/[strutils, strformat, terminal, tables, json]

var fileCache: Table[string, seq[string]]
var errorMessages*: Table[string, JsonNode]

proc loadErrorMessages*(path: string) =
  try:
    let jsonContent = readFile(path)
    let jsonNode = parseJson(jsonContent)
    errorMessages = initTable[string, JsonNode]()
    for key, value in jsonNode:
      errorMessages[key] = value
  except:
    stderr.write "Warning: Failed to load error messages from ", path

proc getErrorInfo(kind: ErrorKind): JsonNode =
  let key = $kind
  if key in errorMessages:
    return errorMessages[key]
  
  result = newJObject()
  result["message"] = %("<error reading file>")
  result["note"] = %"The set of error messages was not found"
  result["tip"] = %"Make sure the compiler has not been moved and the file for the selected locale exists"

proc message(kind: ErrorKind): string =
  getErrorInfo(kind)["message"].getStr()

proc note(kind: ErrorKind): string =
  getErrorInfo(kind)["note"].getStr()

proc tip(kind: ErrorKind): string =
  getErrorInfo(kind)["tip"].getStr()

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
    
    if chunkLen < remaining.len:
      let lastSpace = remaining.rfind(' ', 0, chunkLen - 1)
      if lastSpace > 0:
        chunkLen = lastSpace

    var chunk = remaining[0..<chunkLen]
    
    if chunkLen < remaining.len:
      let openCount = chunk.count('`')
      if openCount mod 2 == 1:
        let nextBacktick = remaining.find('`', chunkLen)
        if nextBacktick != -1:
          chunkLen = nextBacktick + 1
          chunk = remaining[0..<chunkLen]

    chunk = colorBackticks(chunk)
    remaining = remaining[chunkLen..^1].strip(leading = true)

    if isFirst:
      result &= green(prompt & continuing) & chunk
      isFirst = false
    else:
      result &= green(continuing) & chunk

  return result

proc format*(error: Error, short: bool): string =
  var msg = error.kind.message
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