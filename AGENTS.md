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

Adding a row is the procedure under "How to add a row". `checkedIds` in `src/rules.nim` is the list `--matrix` prints. A partial check stays on both lists. `partialIds` names those rows. 7.4, 13.5, ERR33-C, FIO30-C, INT33-C, and PRE31-C stay in both.

Advisory MISRA rows (2.6, 2.7, 12.3, 13.4, 15.1, 15.4, 15.5, 17.8, 19.2, 20.5, 20.10) are checked and counted. They print only with `--advisory`. Required rows and CERT citations print by default. The process exits 1 when any default finding exists.

## What is checked

The meanings of the checked rows. The ids that count are `checkedIds`, printed by `cite --matrix`.

MISRA C:2012 numbers the parse can see:

- 2.6 an unused label. 2.7 a simple parameter whose name never occurs in the body. A nested declarator, a bare typedef, and a K&R name are not judged.
- 4.10 and CERT PRE06-C a header with no include guard and no `#pragma once`. The guard has to be the first token and it has to cover the file. An empty header is quiet.
- 7.1 an octal constant. A lone `0`, a hex constant, and a float are quiet.
- 7.3 lowercase `L` suffix. The same tokens cite CERT DCL16-C.
- 7.4 a declaration `char *name = "..."`. `const char *`, `char const *`, and `char name[]` are quiet. `char * const` is cited, because the pointed-to char is mutable. A later assignment and a typedef for char stay not decided.
- 8.2 an empty parameter list. A bare name is K&R only when declarations sit before the brace. `(void)`, a keyword type, and a typedef name plus a parameter are quiet. 8.14 the word `restrict`.
- 12.3 the comma operator. An argument comma, an initializer comma, and `for (int i = 0, j = 0;;)` are quiet. `for (i = 0, j = 0;;)` and `(1, 2)` are the operator. A typedef name before the declarator counts as a for-init declaration.
- 13.4 an assignment whose result is used. `a = b`, a declaration initializer, an enumerator, a for-init, and a for-increment are quiet. `==`, `!=`, `<=`, and `>=` are quiet. 13.5 the right operand of `&&` or `||` increments or assigns. A call on that side stays not decided. 13.6 a parenthesized `sizeof` operand that increments, assigns, or calls.
- 15.2 a `goto` whose label is missing or earlier in the function. 15.3 a `goto` whose label is in a block that does not enclose the `goto`. 15.4 a loop with more than one `break` or outward `goto`. A `break` inside a nested loop or a `switch` belongs to that statement.
- 15.6 the body of `if`, `else`, `for`, `while`, or `do` is not a brace block. `else if` is accepted. The inner `if` is checked on its own. A `while` that closes a `do` is not treated as a loop body.
- 15.7 an `if` / `else if` chain with no final `else`. A plain `if`, and an `if` with only an `else`, are quiet.
- 16.2 a `case` or `default` whose closest compound is not the switch body. A label of a nested `switch` stays with that switch. 16.3 a switch clause that has statements and does not end in `break`. A brace block is followed to its last statement. `return`, `goto`, `continue`, and `exit` still count, including when every path of an `if` / `else` is one of those. 16.4 a switch with no `default`. 16.5 a `default` that is neither first nor last. 16.6 a switch with fewer than two labels. CERT MSC17-C is the fall-through only: the last label, a jump, an `if` whose every path jumps, and a comment that says fall are quiet.
- 17.1 `<stdarg.h>` and `va_list` / `va_start` / `va_arg` / `va_end` / `va_copy`.
- 17.2 a function on a cycle of direct calls. Function pointers are not followed. Two functions are the same only when their names match exactly.
- 17.8 a simple parameter that is assigned or incremented. `==`, `*p =`, `p->x =`, and `p[i] =` are quiet.
- 18.7 the last member of a struct is an incomplete array, written `name[]`. `name[4]` is quiet.
- 19.2 the word `union`.
- 20.1 `#include` after other code. 20.2 a header name containing `'`, `"`, `\`, `/*`, or `//`. 20.3 an `#include` that is not `<name>` or `"name"`. 20.4 a macro whose name is a keyword. 20.5 `#undef`. 20.7 a function-like macro parameter used in the replacement and not wrapped in parentheses. An operand of `#` or `##` is quiet. 20.10 `#` or `##` in a macro replacement. A hash inside a string or a comment on that line is quiet. 20.11 a parameter that follows `#` and is immediately followed by `##`. 20.12 a parameter used both as a `#` or `##` operand and plainly elsewhere. 20.13 a `#` line that is not a preprocessing directive. A digit after `#` is a line marker and is quiet. 20.14 a conditional inclusion that is not opened and closed in the same file.
- 21.1 `#define` or `#undef` of a reserved identifier. 21.3 and Directive 4.12 allocation. 21.4 `setjmp`. 21.5 signals. 21.6 `stdio` calls and `<stdio.h>`. 21.7 `ato*`. 21.8 `abort`, `exit`, `getenv`, `system`. 21.9 `qsort` and `bsearch`. 21.10 time. 21.11 `<tgmath.h>`. 21.12 `fenv`.

CERT C, same standard of evidence:

- DCL37-C a macro or function we define whose name is reserved (`_Upper`, `__foo`, or a file-scope `_name`).
- DCL41-C a declaration before the first `case` in a `switch`. The type words we recognize are in `declWords` in `src/check.nim`. A typedef we have never seen is not decided.
- ENV33-C `system`.
- ERR33-C the return value of an allocation or a file call is thrown away. Assignment and `return` count as using the value. A value that is stored and never tested is not decided. `printf` and `scanf` are not in this row.
- ERR34-C `atof`, `atoi`, `atol`, `atoll`.
- FIO30-C a `printf` or `scanf` family call whose format argument is not a string literal. Adjacent literals, a wide prefix (`L`, `u`, `U`, `u8`), and parentheses count as one literal. A literal built from user data, and a call through a pointer, stay not decided.
- INT33-C a `/` or `%` whose divisor is an integer literal zero. Any other divisor stays not decided.
- MSC24-C the obsolescent calls listed in `certCallRows` in `src/rules.nim`, including `fopen`.
- MSC30-C `rand`.
- MSC37-C a non-void function with no `return`. `void` and `void *` are told apart. A function that always exits through another call is still cited. `_Noreturn` is not seen.
- PRE11-C a macro whose replacement ends with `;`. A semicolon inside a string or a character constant is quiet.
- PRE31-C a same-file function-like macro whose parameter is used plainly more than once, invoked with an argument that increments, assigns, or calls. `==`, `!=`, `<=`, and `>=` are quiet. `sizeof` is quiet. A macro defined in another file stays not decided.

On the offside native sources the live citations have been `fclose` with an ignored return, `fopen` as MSC24-C, and the reserved macros `_DARWIN_C_SOURCE` and `_POSIX_C_SOURCE`. The brace, switch, and missing-return rows have been clean there.

## What is not decided

Overflow, shift width, null dereference, uninitialized read, use after free, allocation size, string bounds, argument types, unsequenced side effects, errno, and signal safety need a value analysis. They are listed by `cite --matrix`. That list is the public face of the gap.

Closing it means integer, pointer, and floating-point domains, an entry point, and stubs for the C library and the operating system. That is the shape of Astrée. VAST and MLIR carry a Clang AST into an IR. They do not contain these guidelines. A new front end is not the next row.

The hope is that `cite` grows until the not-decided list is only the guidelines that truly need that model, and that each decided row stays backed by a test. The hope is not a green run that an auditor would mistake for a qualification.

## Layout

- `src/lex.nim` turns a translation unit into tokens. Comments and character constants are not tokens. A string literal is a token whose text is `"`, and its contents are not kept. A preprocessor directive, including a backslash-newline, is one token.
- `src/rules.nim` is the table. A library ban is a row. A CERT citation on the same call is a row in `certCallRows`. A guideline we know and do not check is a row in `undecidedRows`. `checkedIds` is what `--matrix` prints. `partialIds` names a row that is both checked and not decided.
- `src/check.nim` walks the tokens: calls, discarded returns, brace bodies, switches, recursion.
- `src/cite.nim` is the command, the self-test, and the printed matrix.
- `Makefile` builds `build/cite` with Nim. `make test` runs `--self-test`.

`build/` is gitignored. Nim 2.4 is enough. The binary is about 235 KB.

The version is `citeVersion` in `src/cite.nim`. `cite --version` prints it.

```
make
build/cite --version
build/cite --self-test
build/cite --matrix
build/cite path/to/src
build/cite --advisory path/to/src
```

From the offside checkout, `make -C c cite` builds this tree and runs it on `c/src`. Offside gitignores this directory. This repo is the source of truth. It is https://github.com/tpqwz/cite. Push only when the author asks. A tag `v` plus `citeVersion` publishes a prerelease of the three executables. The tag has to match `cite --version`.

## How to add a row

1. Put the detection in `rules.nim` or `check.nim`.
2. Add the id to `checkedIds`. Give it a count in the sample inside `selfTest`. The test fails when that count is wrong, when the id is missing, when a rule-table id is off `checkedIds`, or when a checked id is still in `undecidedRows`.
3. Leave the id in `undecidedRows` only when the check is partial, and add it to `partialIds`. A full check comes off `undecidedRows`. 7.4, 13.5, ERR33-C, FIO30-C, INT33-C, and PRE31-C stay in both.
4. Run `make test`, then `build/cite ../c/src`, and read the new citations before calling the row done.

A row that fires on the offside sources is a result to report. A row that stays quiet there is done only when the self-test shows it can fire.

## Hopes

The author wants one checker that can be aimed at full MISRA C and full CERT C without renting the report. The path is this matrix, grown one decided row at a time, with the undecided rows left in the open.

CERT is the side that can carry real wording, because the SEI text is public. MISRA stays numbers until the author supplies the document. Both standards belong in the same binary. A project that only wants the citations runs `cite` on a directory.

The further hope is that the not-decided list shrinks for the rules a deeper analysis can actually settle, and that `cite` never prints a clean bill for a rule it did not judge. The offside converter is the program the author wants to be able to defend. `cite` is how that defense stays visible.
