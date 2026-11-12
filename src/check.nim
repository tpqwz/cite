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

proc badSuffix(text: string): bool =
  var i = 0
  while i < text.len and text[i] in {'0' .. '9', 'a' .. 'f', 'A' .. 'F', '.', 'x', 'X', '+', '-'}:
    inc i
  while i < text.len:
    if text[i] == 'l':
      return true
    inc i
  false

proc check*(path, src: string): tuple[findings: seq[Finding], funcs: seq[FuncBody]] =
  let tokens = lex(src)
  var findings: seq[Finding] = @[]
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
      continue
    if tok.kind == tkNum and badSuffix(tok.text):
      findings.add(path, tok.line, "7.3", "lowercase L in " & tok.text, true)
      findings.add(path, tok.line, "DCL16-C", "lowercase L in " & tok.text, true)
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
            if callee notin seen:
              seen.incl(callee)
              calls.add(callee)
          inc j
        if returns > 1:
          findings.add(path, tokens[i - 1].line, "15.5", name & " returns in " & $returns & " places", false)
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
