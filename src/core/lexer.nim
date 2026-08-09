import tokens, errors
import std/tables

type 
  Lexer* = object
    text: string
    file: string
    len: Natural
    line: Positive = 1
    col: Positive = 1
    pos: Natural = 0

    wasError*: bool = false

    parenthesisStack: seq[Token]

    peekedToken*: Token
    hasPeeked*: bool = false

proc newLexer*(text: string, file: string): Lexer =
  result = Lexer(text: text, file: file, len: text.len)

proc peek(self: var Lexer): char =
  if self.pos < self.len: return self.text[self.pos]
  return '\0'

proc isDigit(c: char): bool =
  c in '0'..'9'

proc isAlpha(c: char): bool =
  c in 'a'..'z' or c in 'A'..'Z'

proc isAlphaNumeric(c: char): bool =
  c.isAlpha() or c.isDigit()

proc advance(self: var Lexer) =
  if self.pos < self.len and self.text[self.pos] == '\n':
    self.line.inc()
    self.col = 1
  else:
    self.col.inc()
  self.pos.inc()

proc nextToken*(self: var Lexer): Token =
  if self.hasPeeked:
    self.hasPeeked = false
    return self.peekedToken

  var c = self.peek()

  while c in " \t\r\n":
    self.advance()
    c = self.peek()

  if c == '\0': 
    if self.parenthesisStack.len > 0:
      self.wasError = true
      let last = self.parenthesisStack[^1]
      newError(errSyntaxParenthesis, last.file, last.line, last.col, 1, "Unclosed")
    return newToken(tkEOF, "\0", self.file, self.line, self.col, 1)

  if c.isDigit():
    var startCol = self.col
    var startLine = self.line
    var lexeme = ""
    
    while self.peek().isDigit():
      lexeme &= $self.peek()
      self.advance()
    
    result = newToken(tkNumber, lexeme, self.file, startLine, startCol, lexeme.len)

  elif $c in operatorTable:
    var op = $c
    let startCol = self.col
    let startLine = self.line
    
    self.advance()
    var next = self.peek()
    
    while ($(op & next)) in operatorTable:
      op &= next
      self.advance()
      next = self.peek()
    
    result = newToken(operatorTable[op], op, self.file, startLine, startCol, op.len)
    
    if result.kind in parenthesisTable:
      self.parenthesisStack.add(result)
    elif result.kind in rightParenthesis:
      if self.parenthesisStack.len == 0 or parenthesisTable[self.parenthesisStack[^1].kind] != result.kind:
        self.wasError = true
        newError(errSyntaxParenthesis, self.file, startLine, startCol, 1, "Unexpected")
      else:
        discard self.parenthesisStack.pop()

  elif c.isAlpha() or c == '_':
    var startCol = self.col
    var startLine = self.line
    var lexeme = ""
    
    while self.peek().isAlphaNumeric() or self.peek() == '_':
      lexeme &= $self.peek()
      self.advance()
    
    if lexeme in keywordTable:
      result = newToken(keywordTable[lexeme], lexeme, self.file, startLine, startCol, lexeme.len)
    else:
      result = newToken(tkIdent, lexeme, self.file, startLine, startCol, lexeme.len)

  else:
    self.wasError = true
    result = newToken(tkInvalid, $c, self.file, self.line, self.col, 1)
    newError(errSyntaxChar, result, c)
    self.advance()

proc peekToken*(self: var Lexer): Token =
  if not self.hasPeeked:
    self.peekedToken = self.nextToken()
    self.hasPeeked = true
  result = self.peekedToken