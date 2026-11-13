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

const citeVersion = "0.1.0-alpha.1"

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

proc matrixAgrees() =
  var checked = initHashSet[string]()
  for id in checkedIds:
    if id in checked:
      quit("duplicate checked id " & id, 1)
    checked.incl(id)
  for id in ruledIds():
    if id notin checked:
      quit("rule table id " & id & " is missing from checkedIds", 1)
  var undec = initHashSet[string]()
  for row in undecided():
    if row[0] in undec:
      quit("duplicate undecided id " & row[0], 1)
    undec.incl(row[0])
  var partial = initHashSet[string]()
  for id in partialIds:
    if id in partial:
      quit("duplicate partial id " & id, 1)
    partial.incl(id)
    if id notin checked or id notin undec:
      quit(id & " must stay in checkedIds and undecidedRows", 1)
  for id in checked:
    if id in undec and id notin partial:
      quit(id & " is checked and still not decided", 1)

proc printMatrix() =
  var misra: seq[string] = @[]
  var cert: seq[string] = @[]
  for id in checkedIds:
    if id.len > 0 and id[0] in {'0' .. '9'}:
      misra.add(id)
    else:
      cert.add(id)
  misra.sort(cmpRule)
  cert.sort(cmpRule)
  echo "checked"
  echo "  MISRA " & misra.join(" ")
  echo "  CERT " & cert.join(" ")
  echo "not decided"
  for row in undecided():
    let family = if row[0].len > 0 and row[0][0] in {'0' .. '9'}: "MISRA" else: "CERT"
    echo "  " & family & " " & row[0] & "  " & row[1]

proc selfTest() =
  let src = """
#include <stdio.h>
#include <stdarg.h>
#include <setjmp.h>
#include <signal.h>
#include <time.h>
#include <tgmath.h>
#include <fenv.h>
#include <bad'name.h>
#include MACRO
#define if 1
long lit = 1l;
int zero = 0;
int hex = 0x10;
int oct = 012;
int * restrict rp;
int oldStyle();
int twice(int n) {
    if (n) return twice(n - 1);
    return n;
}
void show(void) {
    printf("%d\\n", twice(1));
    printf("a" "b\\n");
    printf(buf);
    fprintf(stderr, fmt);
    snprintf(dst, 4, "%s", name);
    exit(0);
    system("ls");
    atoi("1");
    rand();
    gets(buf);
    FILE *kept = fopen("a", "r");
    fopen("b", "r");
    malloc(4);
    qsort(0, 0, 0, 0);
    goto done;
    done: ;
}
#define _FOO 1
#undef plain
#undef _FOO
int _Bar(void) { return 1; }
void bodies(int x) {
  if (x) return;
  if (x) { return; }
  while (x) x = 0;
  do { x = 0; } while (x);
}
int missing(void) { int y; }
void declInSwitch(int x) {
  switch (x) {
    int z;
    case 1: break;
  }
}
void elseIf(int x) {
  if (x) {
    x = 1;
  } else if (x) {
    x = 2;
  }
  if (x) {
    x = 3;
  } else if (x) {
    x = 4;
  } else {
    x = 5;
  }
  if (x) {
    if (x) {
      x = 6;
    } else if (x) {
      x = 7;
    }
  } else {
    x = 8;
  }
}
void switches(int x) {
  switch (x) {
    case 1:
      x = 1;
    case 2:
      break;
    default:
      x = 2;
  }
  switch (x) {
    case 3:
      x = 3;
      /* fall through */
    case 4:
      break;
    default:
      break;
  }
  switch (x) {
    case 1:
      break;
    default:
      break;
    case 2:
      break;
  }
  switch (x) {
    default:
      break;
    case 1:
      break;
  }
  switch (x) {
    case 9:
      return;
    default:
      break;
  }
  switch (x) {
    case 10: {
      x = 10;
      break;
    }
    case 11:
      if (x) {
        continue;
      } else {
        break;
      }
    case 12:
      if (x) {
        break;
      }
    default:
      break;
  }
}
int oldDef() {
  return 1;
}
int knr(a)
  int a;
{
  return a;
}
void unusedParam(int used, int ignored) {
  used = 1;
}
void jumps(void) {
  early:
  goto early;
  goto missing;
  goto later;
  {
    inner:
    ;
  }
  goto inner;
  goto into;
  {
    into:
    ;
  }
  later:
  ;
  unused:
  ;
}
void loops(int x) {
  while (x) {
    if (x) {
      break;
    }
    break;
  }
  while (x) {
    while (x) {
      break;
    }
    break;
  }
  for (;;) {
    break;
  }
  do {
    switch (x) {
      case 1:
        break;
      default:
        break;
    }
  } while (x);
}
void touch(int n) {
  n = n + 1;
  if (n == 1) {
    n++;
  }
}
void commas(void) {
  int i;
  int j;
  int pair = (1, 2);
  for (int a = 0, b = 0; a < 1; a++) {
    b = a;
  }
  for (i = 0, j = 1; i < 1; i++) {
    j = i;
  }
}
union Hold {
  int n;
  char raw[4];
};
struct Flex {
  int n;
  char data[];
};
struct Fixed {
  int n;
  char data[4];
};
typedef enum Color {
  RED = 1,
  BLUE = 2
} Color;
int div0 = 1 / 0;
int mod0 = 1 % 0u;
int div1 = 1 / 1;
int notFloat = 1 / 0.0;
#define STR(x) #x
#define CAT(a, b) a ## b
#define MSG "a # b"
#define PLAIN 1
#define INC(x) x + 1
#define PAREN(x) ((x) + 1)
#define GLUE(x) #x ## y
#define BOTH(x) #x x
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define SEMI(x) foo(x);
#define NOSEMI(x) foo(x)
#not a directive
void nestedCase(int x) {
  switch (x) {
    case 1:
      {
        case 2:
          break;
      }
      break;
    default:
      break;
  }
}
void nestedSwitch(int x, int y) {
  switch (x) {
    case 1:
      switch (y) {
        case 2:
          break;
        default:
          break;
      }
      break;
    default:
      break;
  }
}
char *mut = "hi";
const char *quietLit = "hi";
char const *alsoQuiet = "hi";
char * const alsoMut = "hi";
char buf[] = "hi";
void pre31(void) {
  int i = 0;
  int pre = MAX(i++, 1);
  int preQuiet = MAX(i, 1);
}
void side(void) {
  int a = 0;
  int b = 0;
  if (a && b++) {
    a = 0;
  }
  if (a && b == 1) {
    a = 0;
  }
  if (a || b) {
    a = 0;
  }
  if (a = b) {
    a = 0;
  }
  a = b;
  a = b = 1;
  int used = (a = b) + 1;
  (a = b) + 1;
  sizeof(a);
  sizeof(b++);
  sizeof(int);
}
#include "later.h"
#if 0
"""
  let openHdr = """
int exposed;
"""
  let lateHdr = """
#include "a.h"
#ifndef LATE_H
#define LATE_H
int x;
#endif
"""
  let guardHdr = """
/* lead comment */
#ifndef GUARD_H
#define GUARD_H
int x;
#ifndef INNER
#define INNER
int y;
#endif
#endif
"""
  let onceHdr = """
#pragma once
int kept;
"""
  const expect = [
    ("2.6", 1), ("2.7", 1), ("4.10", 2), ("7.1", 1), ("7.3", 1), ("7.4", 2),
    ("8.2", 3), ("8.14", 1), ("12.3", 2), ("13.4", 4), ("13.5", 1), ("13.6", 1),
    ("15.1", 6), ("15.2", 3), ("15.3", 2), ("15.4", 1),
    ("15.5", 2), ("15.6", 3), ("15.7", 2), ("16.2", 1), ("16.3", 6), ("16.4", 1), ("16.5", 1),
    ("16.6", 1), ("17.1", 1), ("17.2", 1), ("17.8", 17), ("18.7", 1), ("19.2", 1),
    ("20.1", 1), ("20.2", 1), ("20.3", 1), ("20.4", 1), ("20.5", 2), ("20.7", 2),
    ("20.10", 4), ("20.11", 1),
    ("20.12", 1), ("20.13", 1),
    ("20.14", 1), ("21.1", 2), ("21.3", 1), ("21.4", 1), ("21.5", 1), ("21.6", 9),
    ("21.7", 1), ("21.8", 2), ("21.9", 1), ("21.10", 1),
    ("21.11", 1), ("21.12", 1),
    ("DCL16-C", 1), ("DCL37-C", 2), ("DCL41-C", 1), ("ENV33-C", 1),
    ("ERR33-C", 2), ("ERR34-C", 1), ("FIO30-C", 2), ("INT33-C", 2),
    ("MSC17-C", 2), ("MSC24-C", 4),
    ("MSC30-C", 1), ("MSC37-C", 1), ("PRE06-C", 2), ("PRE11-C", 1), ("PRE31-C", 1),
  ]
  let ran = check("sample.c", src)
  var tally = initCountTable[string]()
  for item in ran.findings:
    tally.inc(item.rule)
  for item in recursive(ran.funcs):
    tally.inc(item.rule)
  for item in check("open.h", openHdr).findings:
    tally.inc(item.rule)
  for item in check("late.h", lateHdr).findings:
    tally.inc(item.rule)
  for quiet in [("guard.h", guardHdr), ("once.h", onceHdr)]:
    let clean = check(quiet[0], quiet[1])
    if clean.findings.len != 0 or recursive(clean.funcs).len != 0:
      var shown = quiet[0]
      if clean.findings.len != 0:
        shown = shown & " " & clean.findings[0].rule
      quit("self-test expected a quiet header, got " & shown, 1)
  var seen = initHashSet[string]()
  for row in expect:
    if row[0] in seen:
      quit("duplicate self-test count " & row[0], 1)
    seen.incl(row[0])
    if tally[row[0]] != row[1]:
      quit("self-test " & row[0] & " expected " & $row[1] & " got " & $tally[row[0]], 1)
  for id in checkedIds:
    if id notin seen:
      quit("self-test has no count for " & id, 1)
  for id in seen:
    if id notin checkedIds:
      quit("self-test counts " & id & ", which is not checked", 1)
  for id, n in tally:
    if id notin seen:
      quit("self-test found unexpected " & id & " x" & $n, 1)
  var called = false
  for fn in ran.funcs:
    if fn.path == "sample.c" and fn.name == "twice" and "twice" in fn.calls:
      called = true
  if not called:
    quit("self-test missed recursion", 1)
  matrixAgrees()
  echo "self-test ok"

proc main() =
  var advisory = false
  var roots: seq[string] = @[]
  for arg in commandLineParams():
    if arg == "--help" or arg == "-h":
      echo "cite " & citeVersion
      echo "cite [--advisory] [--matrix] [--self-test] [--version] [files or directories]"
      echo "Cites guideline numbers a parse can see. --matrix lists what is not decided."
      return
    elif arg == "--version":
      echo "cite " & citeVersion
      return
    elif arg == "--matrix":
      printMatrix()
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
