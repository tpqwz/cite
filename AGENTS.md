# cite

`cite` is a native checker that reports guideline numbers a C parse can see. The aim is a matrix an author can trust: every MISRA C guideline and every CERT C guideline is either checked, or listed as not decided. A quiet run means the checked rows were quiet. Read `cite --matrix` for the rest. Silence is not a proof.

The program is Nim. It compiles to one binary, `build/cite`. Other C projects run that binary on their own tree. The first corpus is the offside native converter in `../c/src`.

## Purpose

Offside's C sources are held to SEI CERT C. The author asked whether they can also be held to MISRA C, then asked for a checker that can grow until both standards are covered. Commercial checkers (Perforce QAC, AbsInt Astrée and RuleChecker, Cppcheck Premium) already sell that coverage. The free Cppcheck CERT addon was removed. Open-source Cppcheck still has a MISRA C:2012 addon. clang-tidy has a partial `cert-*` set and no MISRA. Infer, Semgrep, SonarQube Community, and CodeQL are not this checker.

`cite` exists so the decidable rows stay free, local, and honest, and so the rows that need an execution model are named instead of skipped in silence.

## The contract

A finding is a citation: file, line, guideline number, and a short paraphrase. CERT paraphrases are ours. The MISRA wording is paid and is not carried in this repo. Print the number.

Two outcomes exist for every guideline we claim to know:

- **Checked.** The parse can see a violation. The row has a case in `--self-test`.
- **Not decided.** The guideline needs values, linkage, or a whole program. It appears under `cite --matrix`. Leaving it off the matrix is how a clean run becomes a lie.

Adding a row means adding the detection, adding the self-test count, and taking that id off the not-decided list in `src/rules.nim`. The matrix in `src/cite.nim` lists the checked ids in one place. Keep those three in step.

Advisory MISRA rows (15.1 `goto`, 15.5 more than one return) are checked and counted. They print only with `--advisory`. Required rows and CERT citations print by default. The process exits 1 when any default finding exists.

## What is checked

MISRA C:2012 numbers the parse can see:

- 7.3 lowercase `L` suffix. The same tokens cite CERT DCL16-C.
- 15.6 the body of `if`, `else`, `for`, `while`, or `do` is not a brace block. `else if` is accepted. The inner `if` is checked on its own. A `while` that closes a `do` is not treated as a loop body.
- 17.1 `<stdarg.h>` and `va_list` / `va_start` / `va_arg` / `va_end` / `va_copy`.
- 17.2 a function on a cycle of direct calls. Function pointers are not followed. Two functions are the same only when their names match exactly.
- 20.1 `#include` after other code. 20.4 a macro whose name is a keyword.
- 21.3 and Directive 4.12 allocation. 21.4 `setjmp`. 21.5 signals. 21.6 `stdio` calls and `<stdio.h>`. 21.7 `ato*`. 21.8 `abort`, `exit`, `getenv`, `system`. 21.9 `qsort` and `bsearch`. 21.10 time. 21.11 `<tgmath.h>`. 21.12 `fenv`.

CERT C, same standard of evidence:

- DCL37-C a macro or function we define whose name is reserved (`_Upper`, `__foo`, or a file-scope `_name`).
- DCL41-C a declaration before the first `case` in a `switch`. The type words we recognize are in `declWords` in `src/check.nim`. A typedef we have never seen is not decided.
- ENV33-C `system`.
- ERR33-C the return value of an allocation or a file call is thrown away. Assignment and `return` count as using the value. A value that is stored and never tested is not decided. `printf` and `scanf` are not in this row.
- ERR34-C `atof`, `atoi`, `atol`, `atoll`.
- MSC24-C the obsolescent calls listed in `certCallRows` in `src/rules.nim`, including `fopen`.
- MSC30-C `rand`.
- MSC37-C a non-void function with no `return`. `void` and `void *` are told apart. A function that always exits through another call is still cited. `_Noreturn` is not seen.

On the offside native sources the live citations have been `fclose` with an ignored return, `fopen` as MSC24-C, and the reserved macros `_DARWIN_C_SOURCE` and `_POSIX_C_SOURCE`. The brace, switch, and missing-return rows have been clean there.

## What is not decided

Overflow, shift width, null dereference, uninitialized read, use after free, allocation size, string bounds, argument types, unsequenced side effects, errno, and signal safety need a value analysis. They are listed by `cite --matrix`. That list is the public face of the gap.

Closing it means integer, pointer, and floating-point domains, an entry point, and stubs for the C library and the operating system. That is the shape of Astrée. VAST and MLIR carry a Clang AST into an IR. They do not contain these guidelines. A new front end is not the next row.

The hope is that `cite` grows until the not-decided list is only the guidelines that truly need that model, and that each decided row stays backed by a test. The hope is not a green run that an auditor would mistake for a qualification.

## Layout

- `src/lex.nim` turns a translation unit into tokens. Comments and string contents are not tokens. A preprocessor directive, including a backslash-newline, is one token.
- `src/rules.nim` is the table. A library ban is a row. A CERT citation on the same call is a row in `certCallRows`. A guideline we know and do not check is a row in `undecidedRows`.
- `src/check.nim` walks the tokens: calls, discarded returns, brace bodies, switches, recursion.
- `src/cite.nim` is the command, the self-test, and the printed matrix.
- `Makefile` builds `build/cite` with Nim. `make test` runs `--self-test`.

`build/` is gitignored. Nim 2.4 is enough. The binary is about 235 KB.

```
make
build/cite --self-test
build/cite --matrix
build/cite path/to/src
build/cite --advisory path/to/src
```

From the offside checkout, `make -C c cite` builds this tree and runs it on `c/src`. Offside gitignores this directory. This repo is the source of truth. It is https://github.com/tpqwz/cite. Local commits have been ahead of `origin/master`. Push only when the author asks.

## How to add a row

1. Put the detection in `rules.nim` or `check.nim`.
2. Give it a case in the sample inside `selfTest`, and assert the count, not only the presence of the id.
3. Add the id to the checked line in `--matrix`.
4. Delete it from `undecidedRows` when it was listed there.
5. Run `make test`, then `build/cite ../c/src`, and read the new citations before calling the row done.

A row that fires on the offside sources is a result to report. A row that stays quiet there is done only when the self-test shows it can fire.

## Hopes

The author wants one checker that can be aimed at full MISRA C and full CERT C without renting the report. The path is this matrix, grown one decided row at a time, with the undecided rows left in the open.

CERT is the side that can carry real wording, because the SEI text is public. MISRA stays numbers until the author supplies the document. Both standards belong in the same binary. A project that only wants the citations runs `cite` on a directory.

The further hope is that the not-decided list shrinks for the rules a deeper analysis can actually settle, and that `cite` never prints a clean bill for a rule it did not judge. The offside converter is the program the author wants to be able to defend. `cite` is how that defense stays visible.
