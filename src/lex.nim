import std/strutils

## C tokens with line numbers. Comments and character constants are not
## tokens. A string literal is a token whose text is `"`. Its contents are
## not kept. A directive is one token, including a backslash-newline continuation.

type
  TokKind* = enum
    tkIdent, tkNum, tkPunct, tkPp, tkStr
  Tok* = object
    kind*: TokKind
    text*: string
    line*: int

proc isIdentStart(c: char): bool =
  c in {'a' .. 'z', 'A' .. 'Z', '_'}

proc isIdentCont(c: char): bool =
  isIdentStart(c) or c in {'0' .. '9'}

proc lex*(src: string): seq[Tok] =
  result = @[]
  var i = 0
  var line = 1
  var bol = true
  let n = src.len
  while i < n:
    let c = src[i]
    if c in {' ', '\t', '\r', '\v', '\f'}:
      inc i
      continue
    if c == '\n':
      inc line
      bol = true
      inc i
      continue
    if c == '/' and i + 1 < n and src[i + 1] == '/':
      while i < n and src[i] != '\n':
        inc i
      continue
    if c == '/' and i + 1 < n and src[i + 1] == '*':
      i += 2
      while i + 1 < n and not (src[i] == '*' and src[i + 1] == '/'):
        if src[i] == '\n':
          inc line
          bol = true
        inc i
      if i + 1 < n:
        i += 2
      else:
        i = n
      continue
    if bol and c == '#':
      let start = line
      var buf = "#"
      inc i
      while i < n and src[i] != '\n':
        if src[i] == '\\' and i + 1 < n and src[i + 1] == '\n':
          inc line
          i += 2
          buf.add ' '
          continue
        buf.add src[i]
        inc i
      result.add Tok(kind: tkPp, text: buf.strip(), line: start)
      bol = false
      continue
    bol = false
    if c == '"' or c == '\'':
      let quote = c
      let startLine = line
      inc i
      while i < n and src[i] != quote:
        if src[i] == '\n':
          inc line
        if src[i] == '\\' and i + 1 < n:
          if src[i + 1] == '\n':
            inc line
          i += 2
          continue
        inc i
      if i < n:
        inc i
      if quote == '"':
        result.add Tok(kind: tkStr, text: "\"", line: startLine)
      continue
    if c in {'0' .. '9'} or (c == '.' and i + 1 < n and src[i + 1] in {'0' .. '9'}):
      let startLine = line
      var j = i
      if j + 1 < n and src[j] == '0' and src[j + 1] in {'x', 'X'}:
        j += 2
        while j < n and src[j] in {'0' .. '9', 'a' .. 'f', 'A' .. 'F'}:
          inc j
      else:
        while j < n and (src[j] in {'0' .. '9'} or src[j] == '.'):
          inc j
        if j < n and src[j] in {'e', 'E'}:
          inc j
          if j < n and src[j] in {'+', '-'}:
            inc j
          while j < n and src[j] in {'0' .. '9'}:
            inc j
      while j < n and src[j] in {'u', 'U', 'l', 'L', 'f', 'F'}:
        inc j
      result.add Tok(kind: tkNum, text: src[i ..< j], line: startLine)
      i = j
      continue
    if isIdentStart(c):
      var j = i + 1
      while j < n and isIdentCont(src[j]):
        inc j
      result.add Tok(kind: tkIdent, text: src[i ..< j], line: line)
      i = j
      continue
    result.add Tok(kind: tkPunct, text: $c, line: line)
    inc i
