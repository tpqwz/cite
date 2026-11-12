## cite: report guideline numbers a parse can see.
##
## A finding means the source matched a checked row. A guideline that needs
## values is listed by --matrix as not decided. Silence is not a proof.
## MISRA wording is not included. CERT details are short paraphrases.

import std/algorithm
import std/os
import std/sets
import std/strutils
import std/tables
import check
import rules

proc hasBuildPart(path: string): bool =
  for part in path.replace('\\', '/').split('/'):
    if part == "build":
      return true
  false

proc filesOf(root: string): seq[string] =
  if fileExists(root):
    let ext = root.splitFile.ext
    if ext in [".c", ".h"] and not hasBuildPart(root):
      return @[root]
    return
  if not dirExists(root):
    stderr.writeLine(root & ": not a file or directory")
    return
  for path in walkDirRec(root):
    let ext = path.splitFile.ext
    if ext in [".c", ".h"] and not hasBuildPart(path):
      result.add(path)
  result.sort()

proc cmpRule(a, b: string): int =
  let aNum = a.len > 0 and a[0] in {'0' .. '9'}
  let bNum = b.len > 0 and b[0] in {'0' .. '9'}
  if aNum and bNum:
    proc key(name: string): seq[int] =
      for part in name.split('.'):
        try:
          result.add(parseInt(part))
        except ValueError:
          result.add(0)
    let ka = key(a)
    let kb = key(b)
    for i in 0 ..< max(ka.len, kb.len):
      let x = if i < ka.len: ka[i] else: 0
      let y = if i < kb.len: kb[i] else: 0
      if x != y: return cmp(x, y)
    return 0
  if aNum != bNum:
    return if aNum: -1 else: 1
  cmp(a, b)

proc selfTest() =
  let src = """
#include <stdio.h>
#include <stdarg.h>
#define if 1
int twice(int n) {
    if (n) return twice(n - 1);
    return n;
}
void show(void) {
    printf("%d\\n", twice(1));
    exit(0);
    system("ls");
    atoi("1");
    rand();
    gets(buf);
}
#define _FOO 1
int _Bar(void) { return 1; }
"""
  let ran = check("sample.c", src)
  var rules = initHashSet[string]()
  for item in ran.findings:
    rules.incl(item.rule)
  for rule in ["17.1", "20.4", "21.6", "21.8", "15.5", "ENV33-C", "ERR34-C", "MSC24-C", "MSC30-C", "DCL37-C"]:
    if rule notin rules:
      quit("self-test missed " & rule, 1)
  var called = false
  for fn in ran.funcs:
    if fn.path == "sample.c" and fn.name == "twice" and "twice" in fn.calls:
      called = true
  if not called:
    quit("self-test missed recursion", 1)
  if recursive(ran.funcs).len == 0:
    quit("self-test missed the cycle", 1)
  echo "self-test ok"

proc main() =
  var advisory = false
  var roots: seq[string] = @[]
  for arg in commandLineParams():
    if arg == "--help" or arg == "-h":
      echo "cite [--advisory] [--matrix] [--self-test] [files or directories]"
      echo "Cites guideline numbers a parse can see. --matrix lists what is not decided."
      return
    elif arg == "--matrix":
      echo "checked"
      echo "  MISRA 7.3 15.1 15.5 17.1 17.2 20.1 20.4 21.3 21.4 21.5 21.6 21.7 21.8 21.9 21.10 21.12"
      echo "  CERT DCL16-C DCL37-C ENV33-C ERR34-C MSC24-C MSC30-C"
      echo "not decided"
      for row in undecided():
        echo "  CERT ", row[0], "  ", row[1]
      return
    elif arg == "--self-test":
      selfTest()
      return
    elif arg == "--advisory":
      advisory = true
    elif arg.startsWith("-"):
      quit("unknown option " & arg, 2)
    else:
      roots.add(arg)
  if roots.len == 0:
    roots.add(".")
  var findings: seq[Finding] = @[]
  var funcs: seq[FuncBody] = @[]
  var count = 0
  for root in roots:
    for path in filesOf(root):
      inc count
      let ran = check(path, readFile(path))
      findings.add(ran.findings)
      funcs.add(ran.funcs)
  findings.add(recursive(funcs))
  var required: seq[Finding] = @[]
  var advice: seq[Finding] = @[]
  for item in findings:
    if item.required: required.add(item) else: advice.add(item)
  let shown = if advisory: required & advice else: required
  for item in shown:
    if item.line == 0:
      echo item.path, ": ", item.rule, ": ", item.text
    else:
      echo item.path, ":", item.line, ": ", item.rule, ": ", item.text
  echo ""
  var tally = initCountTable[string]()
  for item in findings:
    tally.inc(item.rule)
  if tally.len == 0:
    echo "no findings"
  else:
    var names: seq[string] = @[]
    for name in tally.keys:
      names.add(name)
    names.sort(cmpRule)
    for name in names:
      echo name, "  ", tally[name]
  echo "files ", count, "  required ", required.len, "  advisory ", advice.len
  if required.len > 0:
    quit(1)

main()
