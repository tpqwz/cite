# cite

cite is a small checker for C. Point it at a file or a directory and it reports the MISRA C and CERT C guideline numbers a parse can see.

A quiet run means the checked rows were quiet. `cite --matrix` lists the rest. Silence is not a proof.

This is alpha software, version 0.1.0-alpha.1. The checked set is still growing. A green run is not a qualification, and it is not a stand-in for a checker you rent.

## A citation

```
widget.c:40: 15.7: else if chain has no final else
```

The line is a file, a line number, a guideline number, and a short paraphrase. CERT paraphrases are cite's own. The MISRA wording is paid, so the program prints the number.

Required rows and CERT citations print by default. When any of them are present, the process exits 1. Advisory MISRA rows print only with `--advisory`, and a run that has nothing but advisory rows exits 0.

At the end, cite prints a count for each number it saw, then a total:

```
files 11  required 4  advisory 1
```

## Obtain a binary

Alpha versions are published as GitHub prereleases. Each file is the program. There is no archive to unpack.

| File | Machine |
| --- | --- |
| `cite-linux-x64` | Linux x64 |
| `cite-macos-arm64` | macOS Apple silicon |
| `cite-windows-x64.exe` | Windows x64 |

On Linux and macOS, mark the file executable:

```sh
chmod +x cite-linux-x64
./cite-linux-x64 --version
```

`cite --version` prints the same number as the release, without the leading `v`.

## Build from source

Nim 2.4 is enough.

```sh
make
build/cite --version
make test
```

`make test` runs `build/cite --self-test`. The test fails when a checked guideline has no counted case, or when the printed matrix and the rule table disagree.

```sh
build/cite path/to/src
build/cite --matrix
build/cite --advisory path/to/src
```

## The matrix

Every guideline cite claims to know is in one of two places.

A checked row is one the parse can judge. It has a counted case in the self-test.

A row that is not decided needs values, linkage, or a whole program. `cite --matrix` prints it. A clean run does not cover it.

A few rows are in both places. The parse can see a slice of the guideline, and the rest stays on the matrix.

## Version

The number is `citeVersion` in `src/cite.nim`. While cite is alpha, it has the form `0.1.0-alpha.N`.

A push to `master` runs the self-test on Linux, macOS, and Windows. A tag `v0.1.0-alpha.N` does the same and, when the tag matches `cite --version`, publishes a prerelease with the three executables. A tag that does not say alpha, beta, or rc is published as a release. This project is not there yet.
