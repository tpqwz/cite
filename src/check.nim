## Walk a token stream. Library bans come from the rule table.
## Recursion is a direct-call cycle. Function pointers are not followed.

import std/algorithm
import std/options
import std/sets
import std/strutils
import std/tables
import lex
import rules

type
  Finding* = object
    path*: string
    line*: int
    rule*: string
    text*: string
    required*: bool
  FuncBody* = object
    path*: string
    name*: string
    calls*: seq[string]

proc add(findings: var seq[Finding], path: string, line: int, rule, text: string, required: bool) =
  findings.add Finding(path: path, line: line, rule: rule, text: text, required: required)

proc matchDelim(tokens: seq[Tok], openAt: int, opener, closer: string): int =
  var depth = 0
  for i in openAt ..< tokens.len:
    if tokens[i].text == opener:
      inc depth
    elif tokens[i].text == closer:
      dec depth
      if depth == 0:
        return i
  return -1

proc headerOf(text: string): string =
  if text.len == 0 or text[0] != '#':
    return ""
  let body = text[1 .. ^1].strip()
  if not body.startsWith("include"):
    return ""
  let rest = body[len("include") .. ^1].strip()
  if rest.len >= 2 and rest[0] == '<' and rest[^1] == '>':
    if rest.len == 2: "" else: rest[1 .. rest.len - 2]
  elif rest.len >= 2 and rest[0] == '"' and rest[^1] == '"':
    if rest.len == 2: "" else: rest[1 .. rest.len - 2]
  else:
    ""

proc baseHeader(name: string): string =
  let s = name.replace('\\', '/')
  let i = s.rfind('/')
  if i >= 0: s[i + 1 .. ^1] else: s

proc defineName(text: string): string =
  if text.len == 0 or text[0] != '#':
    return ""
  let body = text[1 .. ^1].strip()
  if not body.startsWith("define"):
    return ""
  let rest = body[len("define") .. ^1].strip()
  var i = 0
  while i < rest.len and (rest[i] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}):
    inc i
  if i == 0: "" else: rest[0 ..< i]

proc sig(tokens: seq[Tok], i, hi: int): int =
  var k = i
  while k < hi and tokens[k].kind == tkPp:
    inc k
  k

proc prevSig(tokens: seq[Tok], i: int): int =
  var k = i
  while k >= 0 and tokens[k].kind == tkPp:
    dec k
  k

proc matchBraceBack(tokens: seq[Tok], closeAt: int): int =
  var depth = 0
  for i in countdown(closeAt, 0):
    if tokens[i].text == "}":
      inc depth
    elif tokens[i].text == "{":
      dec depth
      if depth == 0:
        return i
  -1

proc isDoWhile(tokens: seq[Tok], whileAt: int): bool =
  let before = prevSig(tokens, whileAt - 1)
  if before < 0 or tokens[before].text != "}":
    return false
  let opener = matchBraceBack(tokens, before)
  if opener < 0:
    return false
  let earlier = prevSig(tokens, opener - 1)
  earlier >= 0 and tokens[earlier].text == "do"

proc citeBraceBody(findings: var seq[Finding], path: string, tokens: seq[Tok], lo, hi: int) =
  ## MISRA C:2012 15.6. An else-if is accepted; the inner if is checked on its own.
  var i = lo
  while i < hi:
    let word = tokens[i].text
    if word == "if" or word == "for" or word == "while":
      if word == "while" and isDoWhile(tokens, i):
        inc i
        continue
      let paren = sig(tokens, i + 1, hi)
      if paren < hi and tokens[paren].text == "(":
        let close = matchDelim(tokens, paren, "(", ")")
        if close >= 0:
          let body = sig(tokens, close + 1, hi)
          if body < hi and tokens[body].text != "{":
            findings.add(path, tokens[i].line, "15.6", word & " body is not a compound statement", true)
    elif word == "else" or word == "do":
      let body = sig(tokens, i + 1, hi)
      if body < hi and tokens[body].text != "{" and not (word == "else" and tokens[body].text == "if"):
        findings.add(path, tokens[i].line, "15.6", word & " body is not a compound statement", true)
    inc i

const declWords = ["void", "char", "short", "int", "long", "float", "double", "signed",
                   "unsigned", "struct", "enum", "union", "const", "static", "volatile",
                   "_Bool", "bool", "size_t", "FILE"]

proc citeSwitchDecl(findings: var seq[Finding], path: string, tokens: seq[Tok], lo, hi: int) =
  ## DCL41-C. A declaration in a switch body before the first case label.
  var i = lo
  while i < hi:
    if tokens[i].text == "switch":
      let paren = sig(tokens, i + 1, hi)
      if paren < hi and tokens[paren].text == "(":
        let close = matchDelim(tokens, paren, "(", ")")
        if close >= 0:
          let brace = sig(tokens, close + 1, hi)
          if brace < hi and tokens[brace].text == "{":
            let finish = matchDelim(tokens, brace, "{", "}")
            if finish >= 0:
              var depth = 0
              var j = brace + 1
              while j < finish:
                if tokens[j].text == "{":
                  inc depth
                elif tokens[j].text == "}":
                  dec depth
                elif depth == 0 and (tokens[j].text == "case" or tokens[j].text == "default"):
                  break
                elif depth == 0 and tokens[j].text in declWords:
                  findings.add(path, tokens[j].line, "DCL41-C", "declaration before the first case", true)
                  break
                inc j
              i = finish
    inc i

proc skipStmt(tokens: seq[Tok], i, hi: int): int =
  ## Index just after the statement that starts at i.
  var i = sig(tokens, i, hi)
  if i >= hi:
    return i
  if tokens[i].text == "{":
    let close = matchDelim(tokens, i, "{", "}")
    if close < 0: return hi else: return close + 1
  if tokens[i].text == "if":
    let paren = sig(tokens, i + 1, hi)
    if paren >= hi or tokens[paren].text != "(":
      return i + 1
    let close = matchDelim(tokens, paren, "(", ")")
    if close < 0:
      return hi
    var n = skipStmt(tokens, close + 1, hi)
    let nxt = sig(tokens, n, hi)
    if nxt < hi and tokens[nxt].text == "else":
      n = skipStmt(tokens, nxt + 1, hi)
    return n
  if tokens[i].text == "for" or tokens[i].text == "while" or tokens[i].text == "switch":
    let paren = sig(tokens, i + 1, hi)
    if paren >= hi or tokens[paren].text != "(":
      return i + 1
    let close = matchDelim(tokens, paren, "(", ")")
    if close < 0:
      return hi
    return skipStmt(tokens, close + 1, hi)
  if tokens[i].text == "do":
    var n = skipStmt(tokens, i + 1, hi)
    let nxt = sig(tokens, n, hi)
    if nxt < hi and tokens[nxt].text == "while":
      let paren = sig(tokens, nxt + 1, hi)
      if paren < hi and tokens[paren].text == "(":
        let close = matchDelim(tokens, paren, "(", ")")
        if close >= 0:
          n = close + 1
    let semi = sig(tokens, n, hi)
    if semi < hi and tokens[semi].text == ";":
      return semi + 1
    return n
  if tokens[i].kind == tkIdent and i + 1 < hi and tokens[i + 1].text == ":":
    return skipStmt(tokens, i + 2, hi)
  var paren = 0
  var brace = 0
  var k = i
  while k < hi:
    let text = tokens[k].text
    if text == "(" or text == "[":
      inc paren
    elif text == ")" or text == "]":
      if paren > 0: dec paren
    elif paren == 0 and text == "{":
      inc brace
    elif paren == 0 and text == "}":
      if brace > 0: dec brace
    elif paren == 0 and brace == 0 and text == ";":
      return k + 1
    inc k
  hi

proc elseIfTerminated(tokens: seq[Tok], ifAt, hi: int): bool =
  ## True when this if is not an else-if chain, or the chain ends with else.
  var at = ifAt
  var sawElseIf = false
  while at < hi:
    let paren = sig(tokens, at + 1, hi)
    if paren >= hi or tokens[paren].text != "(":
      return true
    let close = matchDelim(tokens, paren, "(", ")")
    if close < 0:
      return true
    let afterBody = skipStmt(tokens, close + 1, hi)
    let nxt = sig(tokens, afterBody, hi)
    if nxt >= hi or tokens[nxt].text != "else":
      return not sawElseIf
    let body = sig(tokens, nxt + 1, hi)
    if body < hi and tokens[body].text == "if":
      sawElseIf = true
      at = body
    else:
      return true
  not sawElseIf

proc citeElseIf(findings: var seq[Finding], path: string, tokens: seq[Tok], lo, hi: int) =
  ## MISRA C:2012 15.7. A plain if, and an if with only an else, are accepted.
  var i = lo
  while i < hi:
    if tokens[i].text == "if":
      let prev = prevSig(tokens, i - 1)
      if prev < 0 or tokens[prev].text != "else":
        if not elseIfTerminated(tokens, i, hi):
          findings.add(path, tokens[i].line, "15.7", "else if chain has no final else", true)
    inc i

proc directiveWord(text: string): string =
  var i = 0
  if i < text.len and text[i] == '#':
    inc i
  while i < text.len and text[i] in {' ', '\t'}:
    inc i
  let start = i
  while i < text.len and (text[i] in {'a' .. 'z', 'A' .. 'Z', '_'}):
    inc i
  if i == start: "" else: text[start ..< i]

proc afterDirective(text: string): string =
  var i = 0
  if i < text.len and text[i] == '#':
    inc i
  while i < text.len and text[i] in {' ', '\t'}:
    inc i
  while i < text.len and (text[i] in {'a' .. 'z', 'A' .. 'Z', '_'}):
    inc i
  text[i .. ^1].strip()

proc guardMacro(text: string): string =
  ## The macro tested by a whole-file include guard, or "".
  let word = directiveWord(text)
  if word == "ifndef":
    let rest = afterDirective(text)
    var i = 0
    while i < rest.len and (rest[i] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}):
      inc i
    if i > 0 and i == rest.len: rest[0 ..< i] else: ""
  elif word == "if":
    var rest = afterDirective(text)
    if not rest.startsWith("!defined"):
      return ""
    rest = rest[len("!defined") .. ^1].strip()
    if rest.len >= 3 and rest[0] == '(':
      var i = 1
      while i < rest.len and rest[i] in {' ', '\t'}:
        inc i
      let start = i
      while i < rest.len and (rest[i] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}):
        inc i
      var j = i
      while j < rest.len and rest[j] in {' ', '\t'}:
        inc j
      if start == i or j + 1 != rest.len or rest[j] != ')':
        return ""
      rest[start ..< i]
    else:
      var i = 0
      while i < rest.len and (rest[i] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}):
        inc i
      if i > 0 and i == rest.len: rest[0 ..< i] else: ""
  else:
    ""

proc pragmaOnce(text: string): bool =
  directiveWord(text) == "pragma" and afterDirective(text) == "once"

proc citeHeaderGuard(findings: var seq[Finding], path: string, tokens: seq[Tok]) =
  ## Directive 4.10 and PRE06-C. A .h file whose first token is not a guard
  ## that covers the file. #pragma once is a precaution. An empty file is quiet.
  if not path.endsWith(".h") or tokens.len == 0:
    return
  for tok in tokens:
    if tok.kind == tkPp and pragmaOnce(tok.text):
      return
  let name = if tokens[0].kind == tkPp: guardMacro(tokens[0].text) else: ""
  var wrapped = name.len > 0
  if wrapped:
    var depth = 0
    var defined = false
    var closedAt = -1
    for i, tok in tokens:
      if tok.kind != tkPp:
        continue
      let word = directiveWord(tok.text)
      if word == "if" or word == "ifdef" or word == "ifndef":
        inc depth
      elif word == "endif":
        if depth > 0:
          dec depth
        if depth == 0:
          closedAt = i
          break
      elif depth == 1 and word == "define" and defineName(tok.text) == name:
        defined = true
    if not defined or closedAt != tokens.len - 1:
      wrapped = false
  if not wrapped:
    findings.add(path, tokens[0].line, "4.10", "header is not guarded against repeated inclusion", true)
    findings.add(path, tokens[0].line, "PRE06-C", "header is not guarded against repeated inclusion", true)

proc citeConditionals(findings: var seq[Finding], path: string, tokens: seq[Tok]) =
  ## MISRA C:2012 20.14. #else, #elif, and #endif stay with the #if in this file.
  var depth = 0
  var opened = 0
  for tok in tokens:
    if tok.kind != tkPp:
      continue
    let word = directiveWord(tok.text)
    if word == "if" or word == "ifdef" or word == "ifndef":
      inc depth
      opened = tok.line
    elif word == "elif" or word == "else":
      if depth == 0:
        findings.add(path, tok.line, "20.14", word & " has no opening directive in this file", true)
    elif word == "endif":
      if depth == 0:
        findings.add(path, tok.line, "20.14", "endif has no opening directive in this file", true)
      else:
        dec depth
  if depth != 0:
    findings.add(path, opened, "20.14", "conditional inclusion is not closed in this file", true)

type ClauseEnd = enum
  ceBreak, ceJump, ceFall

proc clauseEnd(tokens: seq[Tok], lo, hi: int): ClauseEnd

proc ifFalls(tokens: seq[Tok], ifAt, limit: int): bool =
  ## True when a path through this if reaches the statement after it.
  let paren = sig(tokens, ifAt + 1, limit)
  if paren >= limit or tokens[paren].text != "(":
    return true
  let close = matchDelim(tokens, paren, "(", ")")
  if close < 0:
    return true
  let afterBody = skipStmt(tokens, close + 1, limit)
  if clauseEnd(tokens, close + 1, afterBody) == ceFall:
    return true
  let nxt = sig(tokens, afterBody, limit)
  if nxt >= limit or tokens[nxt].text != "else":
    return true
  let body = sig(tokens, nxt + 1, limit)
  clauseEnd(tokens, body, skipStmt(tokens, body, limit)) == ceFall

proc clauseEnd(tokens: seq[Tok], lo, hi: int): ClauseEnd =
  ## How the last depth-0 statement in lo ..< hi leaves the clause.
  ## A loop as that statement is treated as a fall-through.
  var k = lo
  var kind = ""
  var a = 0
  var b = 0
  while k < hi:
    k = sig(tokens, k, hi)
    if k >= hi:
      break
    let word = tokens[k].text
    if word == "{":
      let close = matchDelim(tokens, k, "{", "}")
      if close < 0:
        break
      kind = "compound"
      a = k + 1
      b = close
      k = close + 1
    elif word == "if" or word == "for" or word == "while" or word == "do" or word == "switch":
      let n = skipStmt(tokens, k, hi)
      kind = word
      a = k
      b = n
      k = n
    else:
      let start = k
      var paren = 0
      var brace = 0
      var closed = false
      while k < hi:
        let text = tokens[k].text
        if text == "(" or text == "[":
          inc paren
        elif text == ")" or text == "]":
          if paren > 0: dec paren
        elif paren == 0 and text == "{":
          inc brace
        elif paren == 0 and text == "}":
          if brace > 0: dec brace
        elif paren == 0 and brace == 0 and text == ";":
          kind = "stmt"
          a = start
          b = k
          inc k
          closed = true
          break
        inc k
      if not closed:
        break
  if kind == "compound":
    return clauseEnd(tokens, a, b)
  if kind == "if":
    if ifFalls(tokens, a, b): return ceFall else: return ceJump
  if kind == "for" or kind == "while" or kind == "do" or kind == "switch":
    return ceFall
  if kind != "stmt":
    return ceFall
  let s = sig(tokens, a, b)
  if s >= b:
    return ceFall
  let word = tokens[s].text
  if word == "break" and sig(tokens, s + 1, b) >= b:
    return ceBreak
  if word == "continue" and sig(tokens, s + 1, b) >= b:
    return ceJump
  if word == "return" or word == "goto":
    return ceJump
  if word in ["exit", "abort", "_Exit", "quick_exit"]:
    let paren = sig(tokens, s + 1, b)
    if paren < b and tokens[paren].text == "(":
      let close = matchDelim(tokens, paren, "(", ")")
      if close >= 0 and sig(tokens, close + 1, b) >= b:
        return ceJump
  ceFall

proc afterLabel(tokens: seq[Tok], labelAt, hi: int): int =
  ## shortcut: a case label ends at its first colon, so a ternary in the label is misread.
  if tokens[labelAt].text == "default":
    let colon = sig(tokens, labelAt + 1, hi)
    if colon < hi and tokens[colon].text == ":": colon + 1 else: labelAt + 1
  else:
    var k = labelAt + 1
    var depth = 0
    while k < hi:
      if tokens[k].text == "(":
        inc depth
      elif tokens[k].text == ")":
        if depth > 0: dec depth
      elif depth == 0 and tokens[k].text == ":":
        return k + 1
      inc k
    hi

proc hasFallComment(src: string, fromLine, toLine: int): bool =
  ## CERT MSC17-C-EX2. A comment that says fall, between the clause and the next label.
  if fromLine < 1 or toLine < fromLine:
    return false
  let lines = src.splitLines()
  var n = fromLine
  while n <= toLine and n <= lines.len:
    let line = lines[n - 1].toLowerAscii()
    if "fall" in line and ("//" in line or "/*" in line or "*/" in line or line.strip().startsWith("*")):
      return true
    inc n
  false

proc citeSwitches(findings: var seq[Finding], path, src: string, tokens: seq[Tok], lo, hi: int) =
  ## 16.3 every clause that has statements ends with break.
  ## 16.4 a switch has a default. 16.5 default is first or last. 16.6 at least two labels.
  ## MSC17-C is only the fall-through. The last label, a jump, and a fall comment are quiet.
  var i = lo
  while i < hi:
    if tokens[i].text == "switch":
      let paren = sig(tokens, i + 1, hi)
      if paren < hi and tokens[paren].text == "(":
        let close = matchDelim(tokens, paren, "(", ")")
        if close >= 0:
          let brace = sig(tokens, close + 1, hi)
          if brace < hi and tokens[brace].text == "{":
            let finish = matchDelim(tokens, brace, "{", "}")
            if finish >= 0:
              var labels: seq[int] = @[]
              var depth = 0
              var parenDepth = 0
              var j = brace + 1
              while j < finish:
                let text = tokens[j].text
                if text == "(" or text == "[":
                  inc parenDepth
                elif text == ")" or text == "]":
                  if parenDepth > 0: dec parenDepth
                elif parenDepth == 0 and text == "{":
                  inc depth
                elif parenDepth == 0 and text == "}":
                  if depth > 0: dec depth
                elif parenDepth == 0 and text == "switch":
                  let innerParen = sig(tokens, j + 1, finish)
                  if innerParen < finish and tokens[innerParen].text == "(":
                    let innerClose = matchDelim(tokens, innerParen, "(", ")")
                    if innerClose >= 0:
                      let innerBrace = sig(tokens, innerClose + 1, finish)
                      if innerBrace < finish and tokens[innerBrace].text == "{":
                        let innerFinish = matchDelim(tokens, innerBrace, "{", "}")
                        if innerFinish >= 0:
                          j = innerFinish
                elif parenDepth == 0 and (text == "case" or text == "default"):
                  if depth == 0:
                    labels.add(j)
                  else:
                    findings.add(path, tokens[j].line, "16.2", "switch label is not in the switch body", true)
                inc j
              var hasDefault = false
              for at in labels:
                if tokens[at].text == "default":
                  hasDefault = true
              if not hasDefault:
                findings.add(path, tokens[i].line, "16.4", "switch has no default", true)
              if labels.len < 2:
                findings.add(path, tokens[i].line, "16.6", "switch has fewer than two labels", true)
              if hasDefault and labels.len > 0 and tokens[labels[0]].text != "default" and
                  tokens[labels[^1]].text != "default":
                findings.add(path, tokens[labels[0]].line, "16.5", "default is not first or last", true)
              for n, at in labels:
                let stmt = afterLabel(tokens, at, finish)
                let stop = if n + 1 < labels.len: labels[n + 1] else: finish
                if sig(tokens, stmt, stop) >= stop:
                  continue
                let ending = clauseEnd(tokens, stmt, stop)
                if ending != ceBreak:
                  findings.add(path, tokens[at].line, "16.3", "switch clause does not end with break", true)
                if ending == ceFall and n + 1 < labels.len:
                  let fromLine = tokens[stmt].line
                  if not hasFallComment(src, fromLine, tokens[labels[n + 1]].line):
                    findings.add(path, tokens[at].line, "MSC17-C", "case falls through", true)
    inc i

proc undefName(text: string): string =
  if directiveWord(text) != "undef":
    return ""
  let rest = afterDirective(text)
  var i = 0
  while i < rest.len and (rest[i] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}):
    inc i
  if i == 0 or i != rest.len: "" else: rest

const declSpecs = [
  "void", "char", "short", "int", "long", "float", "double", "signed", "unsigned",
  "struct", "enum", "union", "const", "static", "volatile", "extern", "typedef",
  "inline", "auto", "register", "_Bool", "bool", "restrict",
]

proc hasSpecifier(tokens: seq[Tok], nameAt: int): bool =
  ## A declaration specifier sits before this declarator, without crossing a call.
  var k = prevSig(tokens, nameAt - 1)
  while k >= 0:
    let text = tokens[k].text
    if text in declSpecs:
      return true
    if text == "*" or (tokens[k].kind == tkIdent and not isKeyword(text)):
      k = prevSig(tokens, k - 1)
      continue
    return false
  false

type ParamList = enum
  plProto, plEmpty, plNames, plLone

proc paramList(tokens: seq[Tok], openAt, closeAt: int): ParamList =
  ## plEmpty is (). plLone is one bare identifier. plNames is several bare identifiers.
  ## A keyword, a star, or two identifiers in one segment is a prototype.
  var segs = 0
  var lone = 0
  var typed = 0
  var idents = 0
  var segTyped = false
  var segAny = false
  proc closeSeg() =
    if not segAny:
      return
    inc segs
    if segTyped:
      inc typed
    elif idents == 1:
      inc lone
    else:
      inc typed
    idents = 0
    segTyped = false
    segAny = false
  var depth = 0
  for k in openAt + 1 ..< closeAt:
    if tokens[k].kind == tkPp:
      continue
    let text = tokens[k].text
    if depth == 0 and text == ",":
      closeSeg()
      continue
    segAny = true
    if text == "(" or text == "[":
      inc depth
      segTyped = true
    elif text == ")" or text == "]":
      if depth > 0: dec depth
    elif text == "*" or text in declSpecs:
      segTyped = true
    elif tokens[k].kind == tkIdent:
      inc idents
      if idents > 1:
        segTyped = true
    else:
      segTyped = true
  closeSeg()
  if segs == 0:
    return plEmpty
  if lone == 0:
    return plProto
  if lone == 1 and typed == 0:
    return plLone
  plNames

proc declaratorTail(tokens: seq[Tok], closeAt: int): string =
  ## "{" an immediate definition, "knr" when declarations sit between ) and {,
  ## ";" or "," a declaration. A call is "".
  ## shortcut: the second name in `int foo(), bar();` is not judged.
  var k = sig(tokens, closeAt + 1, tokens.len)
  if k >= tokens.len:
    return ""
  let text = tokens[k].text
  if text == "{" or text == ";" or text == ",":
    return text
  if text notin declSpecs:
    return ""
  while true:
    while k < tokens.len and tokens[k].text != ";" and tokens[k].text != "{":
      inc k
    if k >= tokens.len or tokens[k].text != ";":
      return ""
    k = sig(tokens, k + 1, tokens.len)
    if k >= tokens.len:
      return ""
    if tokens[k].text == "{":
      return "knr"
    if tokens[k].text notin declSpecs:
      return ""

proc citePrototypes(findings: var seq[Finding], path: string, tokens: seq[Tok]) =
  ## MISRA C:2012 8.2. () is not a prototype. A bare name is one only when
  ## K&R declarations sit before the brace. A typedef name plus a parameter is.
  var i = 0
  while i + 1 < tokens.len:
    if tokens[i].kind == tkIdent and not isKeyword(tokens[i].text) and tokens[i + 1].text == "(":
      let close = matchDelim(tokens, i + 1, "(", ")")
      if close >= 0:
        let kind = paramList(tokens, i + 1, close)
        let tail = declaratorTail(tokens, close)
        var hit = false
        if kind == plEmpty and (tail == "{" or (tail in [";", ","] and hasSpecifier(tokens, i))):
          hit = true
        elif (kind == plLone or kind == plNames) and tail == "knr":
          hit = true
        if hit:
          findings.add(path, tokens[i].line, "8.2", tokens[i].text & " has no prototype", true)
    inc i

proc simpleParamNames(tokens: seq[Tok], openAt, closeAt: int): seq[string] =
  ## Names of simple parameters. A nested declarator, a bare typedef, and a K&R
  ## name are skipped. The name is the last identifier of a typed segment.
  var depth = 0
  var idents: seq[string] = @[]
  var typed = false
  for k in openAt + 1 ..< closeAt:
    let text = tokens[k].text
    if text == "(" or text == "[":
      inc depth
    elif text == ")" or text == "]":
      if depth > 0: dec depth
    elif depth == 0 and text == ",":
      if typed and idents.len > 0 and not isKeyword(idents[^1]):
        result.add(idents[^1])
      idents.setLen(0)
      typed = false
    elif depth == 0 and tokens[k].kind == tkIdent:
      idents.add(text)
      if isKeyword(text) or idents.len > 1:
        typed = true
    elif depth == 0 and text == "*":
      typed = true
  if typed and idents.len > 0 and not isKeyword(idents[^1]):
    result.add(idents[^1])

proc citeParams(findings: var seq[Finding], path: string, tokens: seq[Tok],
                openAt, closeAt, bodyLo, bodyHi: int) =
  ## MISRA C:2012 2.7. A simple parameter name that never occurs in the body.
  for name in simpleParamNames(tokens, openAt, closeAt):
    var used = false
    for k in bodyLo ..< bodyHi:
      if tokens[k].kind == tkIdent and tokens[k].text == name:
        used = true
        break
    if not used:
      findings.add(path, tokens[openAt].line, "2.7", "unused parameter '" & name & "'", false)

type Label = object
  at: int
  home: int
  line: int

proc citeFlow(findings: var seq[Finding], path: string, tokens: seq[Tok], lo, hi: int) =
  ## 2.6 unused label. 15.2 the target is a later label. 15.3 the target's block
  ## encloses the goto. 15.4 a loop has at most one break or outward goto.
  var blocks = @[0]
  var nextBlock = 1
  var paren = 0
  var labels = initTable[string, Label]()
  var gotos: seq[tuple[name: string, at, line: int, chain: seq[int]]] = @[]
  var j = lo
  while j < hi:
    let text = tokens[j].text
    if text == "(" or text == "[":
      inc paren
    elif text == ")" or text == "]":
      if paren > 0: dec paren
    elif paren == 0 and text == "{":
      blocks.add(nextBlock)
      inc nextBlock
    elif paren == 0 and text == "}":
      if blocks.len > 1:
        discard blocks.pop()
    elif paren == 0 and tokens[j].kind == tkIdent and not isKeyword(text) and
        j + 1 < hi and tokens[j + 1].text == ":":
      let prev = prevSig(tokens, j - 1)
      if prev < lo or tokens[prev].text in [";", "{", "}"]:
        if text notin labels:
          labels[text] = Label(at: j, home: blocks[^1], line: tokens[j].line)
    elif paren == 0 and text == "goto" and j + 1 < hi and tokens[j + 1].kind == tkIdent:
      var chain: seq[int] = @[]
      for id in blocks:
        chain.add(id)
      gotos.add((tokens[j + 1].text, j, tokens[j].line, chain))
    inc j
  var used = initHashSet[string]()
  for g in gotos:
    used.incl(g.name)
  for name, lab in labels:
    if name notin used:
      findings.add(path, lab.line, "2.6", "unused label '" & name & "'", false)
  for g in gotos:
    if g.name notin labels or labels[g.name].at < g.at:
      findings.add(path, g.line, "15.2", "goto does not jump to a later label", true)
    if g.name in labels:
      var encloses = false
      for id in g.chain:
        if id == labels[g.name].home:
          encloses = true
      if not encloses:
        findings.add(path, g.line, "15.3", "goto target is not in an enclosing block", true)

proc loopTerminators(tokens: seq[Tok], bodyLo, bodyHi: int): int =
  var loopEnds: seq[int] = @[]
  var switchEnds: seq[int] = @[]
  var j = bodyLo
  while j < bodyHi:
    while loopEnds.len > 0 and j >= loopEnds[^1]:
      discard loopEnds.pop()
    while switchEnds.len > 0 and j >= switchEnds[^1]:
      discard switchEnds.pop()
    let text = tokens[j].text
    if (text == "for" or text == "while" or text == "do") and not (text == "while" and isDoWhile(tokens, j)):
      let finish = skipStmt(tokens, j, bodyHi)
      loopEnds.add(if finish > j: finish else: j + 1)
    elif text == "switch":
      let finish = skipStmt(tokens, j, bodyHi)
      switchEnds.add(if finish > j: finish else: j + 1)
    elif text == "break" and loopEnds.len == 0 and switchEnds.len == 0:
      inc result
    elif text == "goto" and loopEnds.len == 0 and switchEnds.len == 0 and
        j + 1 < bodyHi and tokens[j + 1].kind == tkIdent:
      let target = tokens[j + 1].text
      var outside = true
      var k = bodyLo
      while k < bodyHi:
        if tokens[k].kind == tkIdent and tokens[k].text == target and k + 1 < tokens.len and tokens[k + 1].text == ":":
          outside = false
          break
        inc k
      if outside:
        inc result
    inc j

proc citeLoops(findings: var seq[Finding], path: string, tokens: seq[Tok], lo, hi: int) =
  ## MISRA C:2012 15.4. A break inside a nested loop or a switch belongs to that statement.
  var i = lo
  while i < hi:
    let text = tokens[i].text
    if (text == "for" or text == "while" or text == "do") and not (text == "while" and isDoWhile(tokens, i)):
      var bodyLo = i + 1
      var bodyHi = hi
      if text == "do":
        bodyHi = skipStmt(tokens, i + 1, hi)
      else:
        let paren = sig(tokens, i + 1, hi)
        if paren < hi and tokens[paren].text == "(":
          let close = matchDelim(tokens, paren, "(", ")")
          if close >= 0:
            bodyLo = close + 1
            bodyHi = skipStmt(tokens, bodyLo, hi)
      if loopTerminators(tokens, bodyLo, bodyHi) > 1:
        findings.add(path, tokens[i].line, "15.4", "loop has more than one break or goto", false)
    inc i

type ParenKind = enum
  pkCall, pkExpr, pkFor

proc isAttribute(text: string): bool =
  text in ["__attribute__", "__attribute", "__declspec"]

proc forInitIsDecl(tokens: seq[Tok], openAt, commaAt: int): bool =
  ## A comma in `for (int i = 0, j = 0;;)` separates declarators.
  ## A comma in `for (i = 0, j = 0;;)` is the comma operator.
  var depth = 0
  var idents = 0
  var sawSpec = false
  var k = openAt + 1
  while k < commaAt:
    if tokens[k].kind == tkPp:
      inc k
      continue
    let text = tokens[k].text
    if text == "(" or text == "[":
      inc depth
    elif (text == ")" or text == "]") and depth > 0:
      dec depth
    elif depth == 0:
      if text == ";":
        return false
      if text in declSpecs:
        sawSpec = true
      elif tokens[k].kind == tkIdent:
        inc idents
      elif text != "*" and text != "," and not sawSpec and idents < 2:
        return false
    inc k
  sawSpec or idents >= 2

proc citeCommas(findings: var seq[Finding], path: string, tokens: seq[Tok]) =
  ## MISRA C:2012 12.3. The comma operator, not a separator.
  ## An argument list, an initializer, and a for-loop declarator are separators.
  var brace = 0
  var stack: seq[tuple[kind: ParenKind, attr: bool, openAt, braceAt: int]] = @[]
  for i, tok in tokens:
    let text = tok.text
    if text == "{":
      inc brace
    elif text == "}" and brace > 0:
      dec brace
    elif text == "(":
      let prev = prevSig(tokens, i - 1)
      var kind = pkExpr
      var attr = false
      if prev >= 0:
        let earlier = tokens[prev].text
        if isAttribute(earlier):
          kind = pkCall
          attr = true
        elif tokens[prev].kind == tkIdent and not isKeyword(earlier):
          kind = pkCall
        elif earlier == ")" or earlier in ["static_assert", "_Static_assert", "_Generic"]:
          kind = pkCall
        elif earlier == "for":
          kind = pkFor
        elif earlier == "(" and stack.len > 0 and stack[^1].attr:
          kind = pkCall
          attr = true
      stack.add (kind, attr, i, brace)
    elif text == ")" and stack.len > 0:
      discard stack.pop()
    elif text == "," and stack.len > 0 and brace == stack[^1].braceAt:
      let top = stack[^1]
      if top.kind == pkExpr or (top.kind == pkFor and not forInitIsDecl(tokens, top.openAt, i)):
        findings.add(path, tok.line, "12.3", "comma operator", false)

proc paramModified(tokens: seq[Tok], at, hi: int): bool =
  ## Assignment or ++/-- of this identifier. `==`, `*p =`, and `p->x` are quiet.
  ## `p + + q` is not an increment: a name or a number after the second sign.
  let prev = prevSig(tokens, at - 1)
  if prev >= 0 and tokens[prev].text in ["*", ".", ">"]:
    return false
  let nxt = sig(tokens, at + 1, hi)
  if nxt >= hi:
    return false
  let op = tokens[nxt].text
  let nxt2 = sig(tokens, nxt + 1, hi)
  if op == "=":
    return nxt2 >= hi or tokens[nxt2].text != "="
  if op in ["+", "-", "*", "/", "%", "&", "|", "^"] and nxt2 < hi and tokens[nxt2].text == "=":
    return true
  if (op == "<" or op == ">") and nxt2 < hi and tokens[nxt2].text == op:
    let nxt3 = sig(tokens, nxt2 + 1, hi)
    return nxt3 < hi and tokens[nxt3].text == "="
  if (op == "+" or op == "-") and nxt2 < hi and tokens[nxt2].text == op:
    let nxt3 = sig(tokens, nxt2 + 1, hi)
    if nxt3 < hi and (tokens[nxt3].kind in {tkIdent, tkNum, tkStr} or tokens[nxt3].text == "("):
      return false
    return true
  if prev >= 0 and tokens[prev].text in ["+", "-"]:
    let prev2 = prevSig(tokens, prev - 1)
    if prev2 >= 0 and tokens[prev2].text == tokens[prev].text:
      let prev3 = prevSig(tokens, prev2 - 1)
      if prev3 >= 0 and (tokens[prev3].kind in {tkIdent, tkNum, tkStr} or tokens[prev3].text == ")"):
        return false
      return true
  false

proc citeParamMod(findings: var seq[Finding], path: string, tokens: seq[Tok],
                  openAt, closeAt, bodyLo, bodyHi: int) =
  ## MISRA C:2012 17.8. A simple parameter that is assigned or incremented.
  var names = initHashSet[string]()
  for name in simpleParamNames(tokens, openAt, closeAt):
    names.incl(name)
  if names.len == 0:
    return
  for k in bodyLo ..< bodyHi:
    if tokens[k].kind == tkIdent and tokens[k].text in names and paramModified(tokens, k, bodyHi):
      findings.add(path, tokens[k].line, "17.8", "parameter '" & tokens[k].text & "' is modified", false)

proc emptyBrackets(tokens: seq[Tok], lo, hi: int): bool =
  var k = lo
  while k + 1 < hi:
    if tokens[k].text == "[":
      let nxt = sig(tokens, k + 1, hi)
      if nxt < hi and tokens[nxt].text == "]":
        return true
    inc k
  false

proc citeFlexible(findings: var seq[Finding], path: string, tokens: seq[Tok]) =
  ## MISRA C:2012 18.7. The last member of a struct is an incomplete array.
  var i = 0
  while i < tokens.len:
    if tokens[i].text == "struct":
      var k = i + 1
      while k < tokens.len and tokens[k].text != "{" and tokens[k].text != ";":
        inc k
      if k < tokens.len and tokens[k].text == "{":
        let close = matchDelim(tokens, k, "{", "}")
        if close > k:
          var depth = 0
          var start = k + 1
          var lastLo = -1
          var lastHi = -1
          for n in k + 1 ..< close:
            let text = tokens[n].text
            if text == "{" or text == "(" or text == "[":
              inc depth
            elif (text == "}" or text == ")" or text == "]") and depth > 0:
              dec depth
            elif text == ";" and depth == 0:
              if sig(tokens, start, n) < n:
                lastLo = start
                lastHi = n
              start = n + 1
          if lastLo >= 0 and emptyBrackets(tokens, lastLo, lastHi):
            findings.add(path, tokens[lastLo].line, "18.7", "flexible array member", true)
    inc i

proc isIntZero(text: string): bool =
  ## An integer literal whose value is zero. A float is not this row.
  var stop = text.len
  var floated = false
  while stop > 0 and text[stop - 1] in {'u', 'U', 'l', 'L', 'f', 'F'}:
    if text[stop - 1] in {'f', 'F'}:
      floated = true
    dec stop
  if floated or stop == 0:
    return false
  let body = text[0 ..< stop]
  if '.' in body or 'e' in body or 'E' in body:
    return false
  if body == "0":
    return true
  if body.len >= 3 and body[0] == '0' and body[1] in {'x', 'X', 'b', 'B'}:
    for c in body[2 .. ^1]:
      if c != '0':
        return false
    return true
  if body[0] == '0':
    for c in body:
      if c != '0':
        return false
    return true
  false

proc citeZeroDiv(findings: var seq[Finding], path: string, tokens: seq[Tok]) =
  ## INT33-C, the literal slice. Any other divisor stays not decided.
  var i = 0
  while i + 1 < tokens.len:
    let text = tokens[i].text
    if (text == "/" or text == "%") and tokens[i + 1].kind == tkNum and isIntZero(tokens[i + 1].text):
      findings.add(path, tokens[i].line, "INT33-C", "division by literal zero", true)
    inc i

const directiveNames = [
  "if", "ifdef", "ifndef", "elif", "elifdef", "elifndef", "else", "endif",
  "include", "define", "undef", "line", "error", "pragma", "warning", "embed",
]

proc lineMarker(text: string): bool =
  var i = 0
  if i < text.len and text[i] == '#':
    inc i
  while i < text.len and text[i] in {' ', '\t'}:
    inc i
  i < text.len and text[i] in {'0' .. '9'}

proc defineBody(text: string): string =
  if directiveWord(text) != "define":
    return ""
  let rest = afterDirective(text)
  var i = 0
  while i < rest.len and (rest[i] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}):
    inc i
  if i < rest.len and rest[i] == '(':
    var depth = 0
    while i < rest.len:
      if rest[i] == '(':
        inc depth
      elif rest[i] == ')':
        dec depth
        inc i
        if depth == 0:
          break
        continue
      inc i
  if i >= rest.len: "" else: rest[i .. ^1]

proc hashOperator(body: string): bool =
  ## A # or ## outside a string or a comment on the directive line.
  var i = 0
  while i < body.len:
    if body[i] == '/' and i + 1 < body.len and body[i + 1] == '/':
      return false
    if body[i] == '/' and i + 1 < body.len and body[i + 1] == '*':
      i += 2
      while i + 1 < body.len and not (body[i] == '*' and body[i + 1] == '/'):
        inc i
      if i + 1 < body.len:
        i += 2
      continue
    if body[i] == '"' or body[i] == '\'':
      let quote = body[i]
      inc i
      while i < body.len and body[i] != quote:
        if body[i] == '\\' and i + 1 < body.len:
          i += 2
          continue
        inc i
      if i < body.len:
        inc i
      continue
    if body[i] == '#':
      return true
    inc i
  false

proc citeDirective(findings: var seq[Finding], path: string, line: int, text: string) =
  let word = directiveWord(text)
  if word.len == 0:
    if not lineMarker(text):
      findings.add(path, line, "20.13", "invalid preprocessing directive", true)
    return
  var known = false
  for name in directiveNames:
    if name == word:
      known = true
      break
  if not known:
    findings.add(path, line, "20.13", "invalid preprocessing directive", true)
    return
  if word == "define" and hashOperator(defineBody(text)):
    let name = defineName(text)
    findings.add(path, line, "20.10", "hash operator in '" & name & "'", false)

proc identAt(text: string, i: int): tuple[name: string, nxt: int] =
  result = ("", i)
  if i >= text.len or text[i] notin {'a' .. 'z', 'A' .. 'Z', '_'}:
    return
  var j = i + 1
  while j < text.len and text[j] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}:
    inc j
  result = (text[i ..< j], j)

proc skipMacroSpace(text: string, i: int): int =
  result = i
  while result < text.len and text[result] in {' ', '\t'}:
    inc result

proc macroParams(text: string): tuple[name: string, params: seq[string], body: string] =
  ## A function-like macro. An object-like macro comes back with an empty name.
  if directiveWord(text) != "define":
    return
  let rest = afterDirective(text)
  var i = 0
  let name = identAt(rest, i)
  if name.name.len == 0 or name.nxt >= rest.len or rest[name.nxt] != '(':
    return
  i = name.nxt + 1
  var params: seq[string] = @[]
  while i < rest.len and rest[i] != ')':
    i = skipMacroSpace(rest, i)
    if i < rest.len and rest[i] == '.':
      while i < rest.len and rest[i] == '.':
        inc i
      i = skipMacroSpace(rest, i)
      if i < rest.len and rest[i] == ',':
        inc i
      continue
    let param = identAt(rest, i)
    if param.name.len == 0:
      break
    params.add(param.name)
    i = skipMacroSpace(rest, param.nxt)
    if i < rest.len and rest[i] == ',':
      inc i
  if i >= rest.len or rest[i] != ')':
    return
  (name.name, params, if i + 1 < rest.len: rest[i + 1 .. ^1] else: "")

proc mutableCharStar(tokens: seq[Tok], eqAt: int): bool =
  ## The declarator before `=` is `char *` with no const on the char.
  ## `char * const` still points at a mutable char. A typedef is not seen.
  var i = prevSig(tokens, eqAt - 1)
  if i < 0 or tokens[i].kind != tkIdent or isKeyword(tokens[i].text):
    return false
  var reversed: seq[string] = @[]
  i = prevSig(tokens, i - 1)
  while i >= 0:
    let text = tokens[i].text
    if text in [";", "{", "}", ",", "=", "("]:
      break
    reversed.add(text)
    i = prevSig(tokens, i - 1)
  var sawChar = false
  var stars = 0
  var constOnChar = false
  for k in countdown(reversed.len - 1, 0):
    let text = reversed[k]
    if text == "*":
      inc stars
    elif text == "char":
      sawChar = true
    elif text == "const" and stars == 0:
      constOnChar = true
    elif text notin ["static", "extern", "volatile", "signed", "unsigned",
        "auto", "register", "inline", "const"]:
      return false
  sawChar and stars == 1 and not constOnChar

proc citeStringAssign(findings: var seq[Finding], path: string, tokens: seq[Tok]) =
  ## MISRA C:2012 7.4, the declaration. A later assignment stays not decided.
  var i = 0
  while i + 1 < tokens.len:
    if tokens[i].text == "=" and tokens[i + 1].kind == tkStr and
        (i == 0 or tokens[i - 1].text != "=") and
        (i + 2 >= tokens.len or tokens[i + 2].text != "=") and
        mutableCharStar(tokens, i):
      findings.add(path, tokens[i].line, "7.4", "string literal assigned to char *", true)
    inc i

proc isOctal(text: string): bool =
  ## MISRA C:2012 7.1. A leading zero with more octal digits. Zero itself is allowed.
  if text.len < 2 or text[0] != '0':
    return false
  if text[1] in {'x', 'X', 'b', 'B', '.'}:
    return false
  var i = 1
  var digits = 0
  while i < text.len and text[i] in {'0' .. '7'}:
    inc digits
    inc i
  if digits == 0:
    return false
  while i < text.len and text[i] in {'u', 'U', 'l', 'L'}:
    inc i
  i == text.len

proc returnsValue(tokens: seq[Tok], nameAt: int): bool =
  ## False when the declarator is a void function, not void*.
  var star = false
  var k = nameAt - 1
  while k >= 0:
    let text = tokens[k].text
    if text == "*":
      star = true
    elif text == "void":
      return star
    elif text == ";" or text == "{" or text == "}":
      break
    dec k
  true

proc formatSlot(name: string): int =
  ## Which argument is the format. -1 is not a format call.
  ## swprintf and vswprintf use the C99 count (buffer, length, format).
  case name
  of "printf", "wprintf", "vprintf", "vwprintf", "scanf", "wscanf", "vscanf", "vwscanf":
    0
  of "fprintf", "sprintf", "dprintf", "fwprintf", "vfprintf", "vsprintf", "vdprintf",
     "fscanf", "sscanf", "fwscanf", "swscanf", "vfscanf", "vsscanf", "vfwscanf", "vswscanf":
    1
  of "snprintf", "vsnprintf", "swprintf", "vswprintf":
    2
  else:
    -1

proc argSpan(tokens: seq[Tok], openAt, nth: int): tuple[lo, hi: int] =
  ## Tokens of argument nth inside the call whose '(' is openAt.
  result = (-1, -1)
  let close = matchDelim(tokens, openAt, "(", ")")
  if close < 0:
    return
  var depth = 0
  var arg = 0
  var start = openAt + 1
  for i in openAt + 1 ..< close:
    let text = tokens[i].text
    if text == "(" or text == "[" or text == "{":
      inc depth
    elif (text == ")" or text == "]" or text == "}") and depth > 0:
      dec depth
    elif text == "," and depth == 0:
      if arg == nth:
        return (start, i)
      inc arg
      start = i + 1
  if arg == nth:
    return (start, close)

proc argSideEffect(tokens: seq[Tok], lo, hi: int, calls: bool): bool =
  ## An increment or an assignment. A call counts when `calls` is set.
  ## `==`, `!=`, `<=`, and `>=` are quiet. `<<=` and `>>=` count.
  ## `p + + q` is not an increment when a name follows the second sign.
  ## `sizeof` and the other keywords are not calls.
  var i = lo
  while i < hi:
    let text = tokens[i].text
    let nxt = if i + 1 < hi: tokens[i + 1].text else: ""
    if (text == "+" or text == "-") and nxt == text:
      let third = if i + 2 < hi: tokens[i + 2] else: tokens[i]
      if i + 2 >= hi or not (third.kind in {tkIdent, tkNum, tkStr} or third.text == "("):
        return true
    elif text == "=":
      let prev = if i > lo: tokens[i - 1].text else: ""
      let prev2 = if i > lo + 1: tokens[i - 2].text else: ""
      if nxt == "=" or prev == "=" or prev == "!":
        discard
      elif prev in ["<", ">"] and prev2 != prev:
        discard
      else:
        return true
    elif calls and tokens[i].kind == tkIdent and nxt == "(" and not isKeyword(text):
      return true
    inc i
  false

proc citeMacros(findings: var seq[Finding], path: string, tokens: seq[Tok]) =
  ## 20.7, 20.11, and 20.12 on a function-like macro in this file.
  ## PRE31-C is the same-file slice: a parameter used plainly more than once,
  ## and an argument with an increment, an assignment, or a call.
  var multi = initTable[string, seq[int]]()
  for tok in tokens:
    if tok.kind != tkPp:
      continue
    let mac = macroParams(tok.text)
    if mac.name.len == 0:
      continue
    var plain = newSeq[int](mac.params.len)
    var bare = newSeq[int](mac.params.len)
    var hashed = newSeq[int](mac.params.len)
    var pasted = newSeq[int](mac.params.len)
    var both = newSeq[int](mac.params.len)
    let body = mac.body
    var i = 0
    while i < body.len:
      if body[i] == '/' and i + 1 < body.len and body[i + 1] == '/':
        break
      if body[i] == '/' and i + 1 < body.len and body[i + 1] == '*':
        i += 2
        while i + 1 < body.len and not (body[i] == '*' and body[i + 1] == '/'):
          inc i
        if i + 1 < body.len:
          i += 2
        continue
      if body[i] == '"' or body[i] == '\'':
        let quote = body[i]
        inc i
        while i < body.len and body[i] != quote:
          if body[i] == '\\' and i + 1 < body.len:
            i += 2
          else:
            inc i
        if i < body.len:
          inc i
        continue
      let ident = identAt(body, i)
      if ident.name.len == 0:
        inc i
        continue
      let at = mac.params.find(ident.name)
      if at >= 0:
        var b = i - 1
        while b >= 0 and body[b] in {' ', '\t'}:
          dec b
        let after = skipMacroSpace(body, ident.nxt)
        let hashBefore = b >= 0 and body[b] == '#' and (b == 0 or body[b - 1] != '#')
        let pasteBefore = b >= 1 and body[b] == '#' and body[b - 1] == '#'
        let pasteAfter = after + 1 < body.len and body[after] == '#' and body[after + 1] == '#'
        if hashBefore and pasteAfter:
          inc both[at]
        elif hashBefore:
          inc hashed[at]
        elif pasteBefore or pasteAfter:
          inc pasted[at]
        else:
          inc plain[at]
          let wrapped = b >= 0 and body[b] == '(' and after < body.len and body[after] == ')'
          if not wrapped:
            inc bare[at]
      i = ident.nxt
    var repeats: seq[int] = @[]
    for n, param in mac.params:
      if bare[n] > 0:
        findings.add(path, tok.line, "20.7", "parameter '" & param & "' is not in parentheses", true)
      if both[n] > 0:
        findings.add(path, tok.line, "20.11", "parameter '" & param & "' follows # and ##", true)
      if (hashed[n] > 0 or pasted[n] > 0 or both[n] > 0) and plain[n] > 0:
        findings.add(path, tok.line, "20.12", "parameter '" & param & "' is both raw and expanded", true)
      if plain[n] > 1:
        repeats.add(n)
    if repeats.len > 0:
      multi[mac.name] = repeats
  var i = 0
  while i + 1 < tokens.len:
    if tokens[i].kind == tkIdent and tokens[i + 1].text == "(" and tokens[i].text in multi:
      let open = i + 1
      for n in multi[tokens[i].text]:
        let span = argSpan(tokens, open, n)
        if span.lo >= 0 and argSideEffect(tokens, span.lo, span.hi, true):
          findings.add(path, tokens[i].line, "PRE31-C",
            "macro argument is evaluated more than once", true)
    inc i

proc literalFormat(tokens: seq[Tok], lo, hi: int): bool =
  ## A format is a literal when it is only string tokens, a wide prefix,
  ## and parentheses. Contents are not read.
  if lo < 0 or hi <= lo:
    return false
  var saw = false
  var i = lo
  while i < hi:
    if tokens[i].kind == tkStr:
      saw = true
      inc i
    elif tokens[i].kind == tkPunct and (tokens[i].text == "(" or tokens[i].text == ")"):
      inc i
    elif tokens[i].kind == tkIdent and tokens[i].text in ["L", "u", "U", "u8"] and
        i + 1 < hi and tokens[i + 1].kind == tkStr:
      saw = true
      i += 2
    else:
      return false
  saw

proc resultIgnored(tokens: seq[Tok], calleeAt, openParen: int): bool =
  ## True when a call is a statement by itself, or cast to void.
  ## An assignment or a return uses the value. A surrounding expression does too.
  let close = matchDelim(tokens, openParen, "(", ")")
  if close < 0:
    return false
  var nxt = close + 1
  while nxt < tokens.len and tokens[nxt].kind == tkPp:
    inc nxt
  if nxt >= tokens.len or tokens[nxt].text != ";":
    return false
  var depth = 0
  var k = calleeAt - 1
  while k >= 0:
    let text = tokens[k].text
    if text == ")":
      inc depth
    elif text == "(":
      if depth == 0:
        break
      dec depth
    elif depth == 0:
      if text == "=" or text == "return":
        return false
      if text == ";" or text == "{" or text == "}":
        return true
    dec k
  true

proc badSuffix(text: string): bool =
  var i = 0
  while i < text.len and text[i] in {'0' .. '9', 'a' .. 'f', 'A' .. 'F', '.', 'x', 'X', '+', '-'}:
    inc i
  while i < text.len:
    if text[i] == 'l':
      return true
    inc i
  false

proc assignEq(tokens: seq[Tok], i: int): int =
  ## Index of the `=` in an assignment that starts at i, or -1.
  ## `==`, `!=`, `<=`, and `>=` are not assignments.
  if i < 0 or i >= tokens.len:
    return -1
  let text = tokens[i].text
  let nxt = if i + 1 < tokens.len: tokens[i + 1].text else: ""
  let prev = if i > 0: tokens[i - 1].text else: ""
  if text == "=":
    if nxt == "=" or prev == "=" or prev == "!":
      return -1
    if prev in ["+", "-", "*", "/", "%", "&", "|", "^", "<", ">"]:
      return -1
    return i
  if text in ["+", "-", "*", "/", "%", "&", "|", "^"] and nxt == "=":
    if (text == "+" or text == "-" or text == "&" or text == "|") and prev == text:
      return -1
    return i + 1
  if (text == "<" or text == ">") and i + 2 < tokens.len and
      tokens[i + 1].text == text and tokens[i + 2].text == "=" and prev != text:
    return i + 2
  -1

proc enumeratorEquals(tokens: seq[Tok], eqAt: int): bool =
  ## The `=` of an enumerator is not an assignment operator.
  var depth = 0
  var i = eqAt - 1
  while i >= 0:
    let text = tokens[i].text
    if text in ["}", ")", "]"]:
      inc depth
    elif text in ["{", "(", "["] and depth > 0:
      dec depth
    elif depth == 0 and text == "{":
      var k = prevSig(tokens, i - 1)
      if k >= 0 and tokens[k].kind == tkIdent and not isKeyword(tokens[k].text):
        k = prevSig(tokens, k - 1)
      return k >= 0 and tokens[k].text == "enum"
    elif depth == 0 and text == ";":
      return false
    dec i
  false

proc initializerEquals(tokens: seq[Tok], eqAt: int): bool =
  ## The `=` that introduces a declaration initializer, not a later assignment.
  var depth = 0
  var i = eqAt - 1
  while i >= 0:
    let text = tokens[i].text
    if text in [")", "]", "}"]:
      inc depth
    elif text in ["(", "[", "{"] and depth > 0:
      dec depth
    elif depth == 0:
      if text in [";", "{", "}", "(", ")"]:
        return false
      if assignEq(tokens, i) >= 0:
        return false
      if text in declSpecs:
        return true
    dec i
  false

proc forClause(tokens: seq[Tok], openAt, at: int): int =
  ## 0 init, 1 condition, 2 increment.
  result = 0
  var depth = 0
  var k = openAt + 1
  while k < at:
    let text = tokens[k].text
    if text in ["(", "[", "{"]:
      inc depth
    elif text in [")", "]", "}"] and depth > 0:
      dec depth
    elif depth == 0 and text == ";":
      inc result
    inc k

proc assignConsumed(tokens: seq[Tok], eqAt: int): bool =
  ## Something after this assignment reads it. A following `;` or `{` does not.
  var depth = 0
  var j = eqAt + 1
  while j < tokens.len:
    let text = tokens[j].text
    if text in ["(", "[", "{"]:
      inc depth
    elif text in [")", "]", "}"] and depth > 0:
      dec depth
    elif depth == 0 and text in [")", "]", "}"]:
      let nxt = sig(tokens, j + 1, tokens.len)
      if nxt >= tokens.len:
        return false
      return tokens[nxt].text notin [";", ",", ")", "]", "}", "{", ":"]
    elif depth == 0 and (text == ";" or text == ","):
      return false
    inc j
  false

proc assignResultUsed(tokens: seq[Tok], eqAt: int): bool =
  ## MISRA C:2012 13.4. A statement, a for-init, a for-increment, and a
  ## declaration initializer discard the result. `==` is not an assignment.
  if initializerEquals(tokens, eqAt) or enumeratorEquals(tokens, eqAt):
    return false
  var depth = 0
  var crossedComma = false
  var i = eqAt - 1
  while i >= 0:
    let text = tokens[i].text
    if text in [")", "]", "}"]:
      inc depth
    elif text in ["(", "[", "{"] and depth > 0:
      dec depth
    elif depth == 0:
      if text == "[":
        return true
      if text == "(":
        let prev = prevSig(tokens, i - 1)
        if prev >= 0 and tokens[prev].text in ["if", "while", "switch", "sizeof"]:
          return true
        if prev >= 0 and tokens[prev].text == "for":
          return forClause(tokens, i, eqAt) == 1
        if prev >= 0 and tokens[prev].text == ")" :
          return true
        if prev >= 0 and tokens[prev].kind == tkIdent and not isKeyword(tokens[prev].text):
          return true
      elif text == "?" or text == "return":
        return true
      elif text == "," :
        crossedComma = true
      elif text == ";" or text == "{":
        return assignConsumed(tokens, eqAt)
      else:
        let outer = assignEq(tokens, i)
        if outer >= 0 and outer < eqAt and not crossedComma:
          return true
    dec i
  assignConsumed(tokens, eqAt)

proc citeAssignUse(findings: var seq[Finding], path: string, tokens: seq[Tok]) =
  var i = 0
  while i < tokens.len:
    let eq = assignEq(tokens, i)
    if eq >= 0:
      if assignResultUsed(tokens, eq):
        findings.add(path, tokens[eq].line, "13.4", "assignment result is used", false)
      i = eq + 1
    else:
      inc i

proc logicalKind(tokens: seq[Tok], i: int): string =
  if i + 1 >= tokens.len:
    return ""
  let a = tokens[i].text
  let b = tokens[i + 1].text
  if a == "&" and b == "&": "&&" elif a == "|" and b == "|": "||" else: ""

proc logicalRhs(tokens: seq[Tok], start: int, kind: string): int =
  var depth = 0
  var j = start
  while j < tokens.len:
    let text = tokens[j].text
    if text in ["(", "[", "{"]:
      inc depth
    elif text in [")", "]", "}"] and depth > 0:
      dec depth
    elif depth == 0:
      if text in [")", "]", "}", ";", ",", "?"]:
        return j
      if j + 1 < tokens.len:
        let pair = logicalKind(tokens, j)
        if kind == "&&" and pair.len > 0:
          return j
        if kind == "||" and pair == "||":
          return j
    inc j
  tokens.len

proc citeLogical(findings: var seq[Finding], path: string, tokens: seq[Tok]) =
  ## 13.5, the visible slice. A call on the right stays not decided.
  var i = 0
  while i < tokens.len:
    let kind = logicalKind(tokens, i)
    if kind.len > 0:
      let hi = logicalRhs(tokens, i + 2, kind)
      if argSideEffect(tokens, i + 2, hi, false):
        findings.add(path, tokens[i].line, "13.5", "logical operand has a side effect", true)
      i += 2
    else:
      inc i

proc citeSizeof(findings: var seq[Finding], path: string, tokens: seq[Tok]) =
  ## 13.6. The operand in parentheses. An unparenthesized operand is not seen.
  var i = 0
  while i < tokens.len:
    if tokens[i].text == "sizeof":
      let nxt = sig(tokens, i + 1, tokens.len)
      if nxt < tokens.len and tokens[nxt].text == "(":
        let close = matchDelim(tokens, nxt, "(", ")")
        if close > nxt and argSideEffect(tokens, nxt + 1, close, true):
          findings.add(path, tokens[i].line, "13.6", "sizeof operand has a side effect", true)
    inc i

proc cutDirectiveComment(text: string): string =
  result = ""
  var i = 0
  var quote = false
  var angle = 0
  while i < text.len:
    let c = text[i]
    if quote:
      result.add c
      if c == '"':
        quote = false
      inc i
      continue
    if c == '"':
      quote = true
      result.add c
    elif c == '<':
      inc angle
      result.add c
    elif c == '>' and angle > 0:
      dec angle
      result.add c
    elif angle == 0 and c == '/' and i + 1 < text.len and text[i + 1] == '/':
      break
    elif angle == 0 and c == '/' and i + 1 < text.len and text[i + 1] == '*':
      i += 2
      while i + 1 < text.len and not (text[i] == '*' and text[i + 1] == '/'):
        inc i
      if i + 1 < text.len:
        i += 2
      continue
    else:
      result.add c
    inc i
  result = result.strip()

proc badHeaderName(name: string): bool =
  if '\'' in name or '"' in name or '\\' in name:
    return true
  var i = 0
  while i + 1 < name.len:
    if name[i] == '/' and (name[i + 1] == '/' or name[i + 1] == '*'):
      return true
    inc i
  false

proc citeIncludes(findings: var seq[Finding], path: string, tokens: seq[Tok]) =
  ## 20.2 a forbidden character in the header name.
  ## 20.3 the directive is not <name> or "name".
  for tok in tokens:
    if tok.kind != tkPp or directiveWord(tok.text) != "include":
      continue
    let rest = cutDirectiveComment(afterDirective(tok.text))
    if rest.len >= 2 and ((rest[0] == '<' and rest[^1] == '>') or
        (rest[0] == '"' and rest[^1] == '"')):
      let name = rest[1 ..< rest.len - 1]
      if badHeaderName(name):
        findings.add(path, tok.line, "20.2", "header name '" & name & "'", true)
    else:
      findings.add(path, tok.line, "20.3", "include is not a header name", true)

proc macroEndsSemi(body: string): bool =
  var i = 0
  var last = ' '
  while i < body.len:
    if body[i] in {' ', '\t'}:
      inc i
      continue
    if body[i] == '/' and i + 1 < body.len and body[i + 1] == '/':
      break
    if body[i] == '/' and i + 1 < body.len and body[i + 1] == '*':
      i += 2
      while i + 1 < body.len and not (body[i] == '*' and body[i + 1] == '/'):
        inc i
      if i + 1 < body.len:
        i += 2
      continue
    if body[i] == '"' or body[i] == '\'':
      let quote = body[i]
      last = quote
      inc i
      while i < body.len and body[i] != quote:
        if body[i] == '\\' and i + 1 < body.len:
          i += 2
        else:
          inc i
      if i < body.len:
        inc i
      continue
    last = body[i]
    inc i
  last == ';'

proc citeMacroSemi(findings: var seq[Finding], path: string, tokens: seq[Tok]) =
  ## CERT PRE11-C. A semicolon inside a string or a character constant is quiet.
  for tok in tokens:
    if tok.kind == tkPp and directiveWord(tok.text) == "define" and
        macroEndsSemi(defineBody(tok.text)):
      let name = defineName(tok.text)
      findings.add(path, tok.line, "PRE11-C", "macro '" & name & "' ends with a semicolon", true)

proc check*(path, src: string): tuple[findings: seq[Finding], funcs: seq[FuncBody]] =
  let tokens = lex(src)
  var findings: seq[Finding] = @[]
  citeHeaderGuard(findings, path, tokens)
  citeConditionals(findings, path, tokens)
  citePrototypes(findings, path, tokens)
  citeCommas(findings, path, tokens)
  citeFlexible(findings, path, tokens)
  citeZeroDiv(findings, path, tokens)
  citeMacros(findings, path, tokens)
  citeStringAssign(findings, path, tokens)
  citeAssignUse(findings, path, tokens)
  citeLogical(findings, path, tokens)
  citeSizeof(findings, path, tokens)
  citeIncludes(findings, path, tokens)
  citeMacroSemi(findings, path, tokens)
  var sawCode = false
  for tok in tokens:
    if tok.kind == tkPp:
      let header = headerOf(tok.text)
      if header.len > 0:
        let hit = headerRule(baseHeader(header))
        if hit.isSome:
          findings.add(path, tok.line, hit.get.id, "header <" & baseHeader(header) & ">", true)
        if sawCode:
          findings.add(path, tok.line, "20.1", "include after code: " & header, true)
      let defined = defineName(tok.text)
      if defined.len > 0 and isKeyword(defined):
        findings.add(path, tok.line, "20.4", "macro hides keyword " & defined, true)
      if defined.len > 0 and reservedName(defined):
        findings.add(path, tok.line, "DCL37-C", "reserved macro '" & defined & "'", true)
        findings.add(path, tok.line, "21.1", "reserved macro '" & defined & "'", true)
      let removed = undefName(tok.text)
      if removed.len > 0:
        findings.add(path, tok.line, "20.5", "undef '" & removed & "'", false)
        if reservedName(removed):
          findings.add(path, tok.line, "21.1", "reserved macro '" & removed & "'", true)
      citeDirective(findings, path, tok.line, tok.text)
      continue
    if tok.kind == tkNum and isOctal(tok.text):
      findings.add(path, tok.line, "7.1", "octal constant " & tok.text, true)
    if tok.kind == tkNum and badSuffix(tok.text):
      findings.add(path, tok.line, "7.3", "lowercase L in " & tok.text, true)
      findings.add(path, tok.line, "DCL16-C", "lowercase L in " & tok.text, true)
    if tok.kind == tkIdent and tok.text == "restrict":
      findings.add(path, tok.line, "8.14", "restrict", true)
    if tok.kind == tkIdent and tok.text == "union":
      findings.add(path, tok.line, "19.2", "union", false)
    if tok.kind == tkIdent:
      let hit = useRule(tok.text)
      if hit.isSome:
        findings.add(path, tok.line, hit.get.id, hit.get.what & " '" & tok.text & "'", true)
    sawCode = true

  var funcs: seq[FuncBody] = @[]
  var i = 0
  while i < tokens.len:
    if tokens[i].text == "(" and i > 0 and tokens[i - 1].kind == tkIdent:
      let name = tokens[i - 1].text
      let close = matchDelim(tokens, i, "(", ")")
      var nxt = if close >= 0: close + 1 else: -1
      while nxt >= 0 and nxt < tokens.len and tokens[nxt].kind == tkPp:
        inc nxt
      let isDef = not isKeyword(name) and close >= 0 and nxt >= 0 and nxt < tokens.len and tokens[nxt].text == "{"
      if isDef and reservedName(name):
        findings.add(path, tokens[i - 1].line, "DCL37-C", "reserved function '" & name & "'", true)
      if isDef:
        let finish = matchDelim(tokens, nxt, "{", "}")
        if finish < 0:
          break
        var calls: seq[string] = @[]
        var seen = initHashSet[string]()
        var returns = 0
        for inner in tokens[nxt + 1 ..< finish]:
          if inner.text == "return":
            inc returns
          if inner.text == "goto":
            findings.add(path, inner.line, "15.1", "goto", false)
        var j = nxt + 1
        while j < finish:
          if tokens[j].text == "(" and tokens[j - 1].kind == tkIdent and not isKeyword(tokens[j - 1].text):
            let callee = tokens[j - 1].text
            let hit = callRule(callee)
            if hit.isSome:
              var label = hit.get.what & " '" & callee & "'"
              if hit.get.extra.len > 0:
                label = hit.get.extra & ", " & label
              findings.add(path, tokens[j - 1].line, hit.get.id, label, true)
            for cert in certForCall(callee):
              findings.add(path, tokens[j - 1].line, cert.id, cert.detail & " '" & callee & "'", true)
            if ignoresResult(callee) and resultIgnored(tokens, j - 1, j):
              findings.add(path, tokens[j - 1].line, "ERR33-C", "ignored return '" & callee & "'", true)
            let slot = formatSlot(callee)
            if slot >= 0:
              let span = argSpan(tokens, j, slot)
              if not literalFormat(tokens, span.lo, span.hi):
                findings.add(path, tokens[j - 1].line, "FIO30-C",
                  "format is not a string literal '" & callee & "'", true)
            if callee notin seen:
              seen.incl(callee)
              calls.add(callee)
          inc j
        if returns > 1:
          findings.add(path, tokens[i - 1].line, "15.5", name & " returns in " & $returns & " places", false)
        if returns == 0 and returnsValue(tokens, i - 1):
          findings.add(path, tokens[i - 1].line, "MSC37-C", name & " has no return", true)
        citeBraceBody(findings, path, tokens, nxt + 1, finish)
        citeElseIf(findings, path, tokens, nxt + 1, finish)
        citeSwitchDecl(findings, path, tokens, nxt + 1, finish)
        citeSwitches(findings, path, src, tokens, nxt + 1, finish)
        citeParams(findings, path, tokens, i, close, nxt + 1, finish)
        citeParamMod(findings, path, tokens, i, close, nxt + 1, finish)
        citeFlow(findings, path, tokens, nxt + 1, finish)
        citeLoops(findings, path, tokens, nxt + 1, finish)
        funcs.add FuncBody(path: path, name: name, calls: calls)
        i = finish + 1
        continue
    inc i
  (findings, funcs)

proc recursive*(funcs: seq[FuncBody]): seq[Finding] =
  ## Each function that sits on a direct-call cycle, once.
  var byName = initTable[string, seq[int]]()
  for i, fn in funcs:
    byName.mgetOrPut(fn.name, @[]).add(i)
  var mark = newSeq[int](funcs.len)
  var stack: seq[int] = @[]
  var onCycle = initHashSet[int]()

  proc targets(callee: string): seq[int] =
    byName.getOrDefault(callee)

  proc visit(node: int) =
    mark[node] = 1
    stack.add(node)
    for callee in funcs[node].calls:
      for nxt in targets(callee):
        if mark[nxt] == 1:
          let at = stack.find(nxt)
          if at >= 0:
            for k in at ..< stack.len:
              onCycle.incl(stack[k])
        elif mark[nxt] == 0:
          visit(nxt)
    discard stack.pop()
    mark[node] = 2

  for i in 0 ..< funcs.len:
    if mark[i] == 0:
      visit(i)
  var ids = newSeq[int]()
  for id in onCycle:
    ids.add(id)
  ids.sort()
  for id in ids:
    result.add Finding(path: funcs[id].path, line: 0, rule: "17.2",
      text: funcs[id].name & " is recursive", required: true)
