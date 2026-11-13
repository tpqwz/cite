## The decidable MISRA C:2012 rows.
## A new library ban is a row here. Rules that need values are not rows.

type
  Rule* = object
    id*: string
    extra*: string
    what*: string
  CertCite* = object
    id*: string
    detail*: string

const
  callRows = [
    ("malloc", "21.3", "Dir 4.12", "allocation"),
    ("calloc", "21.3", "Dir 4.12", "allocation"),
    ("realloc", "21.3", "Dir 4.12", "allocation"),
    ("aligned_alloc", "21.3", "Dir 4.12", "allocation"),
    ("free", "21.3", "Dir 4.12", "allocation"),
    ("setjmp", "21.4", "", "setjmp"),
    ("longjmp", "21.4", "", "setjmp"),
    ("signal", "21.5", "", "signal"),
    ("raise", "21.5", "", "signal"),
    ("abort", "21.8", "", "stdlib process"),
    ("exit", "21.8", "", "stdlib process"),
    ("_Exit", "21.8", "", "stdlib process"),
    ("quick_exit", "21.8", "", "stdlib process"),
    ("getenv", "21.8", "", "stdlib process"),
    ("system", "21.8", "", "stdlib process"),
    ("bsearch", "21.9", "", "bsearch or qsort"),
    ("qsort", "21.9", "", "bsearch or qsort"),
    ("atof", "21.7", "", "ato* conversion"),
    ("atoi", "21.7", "", "ato* conversion"),
    ("atol", "21.7", "", "ato* conversion"),
    ("atoll", "21.7", "", "ato* conversion"),
    ("va_start", "17.1", "", "stdarg"),
    ("va_arg", "17.1", "", "stdarg"),
    ("va_end", "17.1", "", "stdarg"),
    ("va_copy", "17.1", "", "stdarg"),
    ("fopen", "21.6", "", "stdio"),
    ("freopen", "21.6", "", "stdio"),
    ("fclose", "21.6", "", "stdio"),
    ("fflush", "21.6", "", "stdio"),
    ("fread", "21.6", "", "stdio"),
    ("fwrite", "21.6", "", "stdio"),
    ("fseek", "21.6", "", "stdio"),
    ("ftell", "21.6", "", "stdio"),
    ("rewind", "21.6", "", "stdio"),
    ("fgetpos", "21.6", "", "stdio"),
    ("fsetpos", "21.6", "", "stdio"),
    ("clearerr", "21.6", "", "stdio"),
    ("feof", "21.6", "", "stdio"),
    ("ferror", "21.6", "", "stdio"),
    ("remove", "21.6", "", "stdio"),
    ("rename", "21.6", "", "stdio"),
    ("tmpfile", "21.6", "", "stdio"),
    ("tmpnam", "21.6", "", "stdio"),
    ("setvbuf", "21.6", "", "stdio"),
    ("setbuf", "21.6", "", "stdio"),
    ("fprintf", "21.6", "", "stdio"),
    ("printf", "21.6", "", "stdio"),
    ("sprintf", "21.6", "", "stdio"),
    ("snprintf", "21.6", "", "stdio"),
    ("vfprintf", "21.6", "", "stdio"),
    ("vprintf", "21.6", "", "stdio"),
    ("vsprintf", "21.6", "", "stdio"),
    ("vsnprintf", "21.6", "", "stdio"),
    ("fscanf", "21.6", "", "stdio"),
    ("scanf", "21.6", "", "stdio"),
    ("sscanf", "21.6", "", "stdio"),
    ("vfscanf", "21.6", "", "stdio"),
    ("vscanf", "21.6", "", "stdio"),
    ("vsscanf", "21.6", "", "stdio"),
    ("fgetc", "21.6", "", "stdio"),
    ("fgets", "21.6", "", "stdio"),
    ("fputc", "21.6", "", "stdio"),
    ("fputs", "21.6", "", "stdio"),
    ("getc", "21.6", "", "stdio"),
    ("getchar", "21.6", "", "stdio"),
    ("gets", "21.6", "", "stdio"),
    ("putc", "21.6", "", "stdio"),
    ("putchar", "21.6", "", "stdio"),
    ("puts", "21.6", "", "stdio"),
    ("ungetc", "21.6", "", "stdio"),
    ("perror", "21.6", "", "stdio"),
    ("clock", "21.10", "", "time"),
    ("difftime", "21.10", "", "time"),
    ("mktime", "21.10", "", "time"),
    ("time", "21.10", "", "time"),
    ("asctime", "21.10", "", "time"),
    ("ctime", "21.10", "", "time"),
    ("gmtime", "21.10", "", "time"),
    ("localtime", "21.10", "", "time"),
    ("strftime", "21.10", "", "time"),
    ("feclearexcept", "21.12", "", "fenv"),
    ("fegetexceptflag", "21.12", "", "fenv"),
    ("feraiseexcept", "21.12", "", "fenv"),
    ("fesetexceptflag", "21.12", "", "fenv"),
    ("fetestexcept", "21.12", "", "fenv"),
    ("fegetround", "21.12", "", "fenv"),
    ("fesetround", "21.12", "", "fenv"),
    ("fegetenv", "21.12", "", "fenv"),
    ("feholdexcept", "21.12", "", "fenv"),
    ("fesetenv", "21.12", "", "fenv"),
    ("feupdateenv", "21.12", "", "fenv"),
  ]
  headerRows = [
    ("stdarg.h", "17.1", "stdarg"),
    ("setjmp.h", "21.4", "setjmp"),
    ("signal.h", "21.5", "signal"),
    ("stdio.h", "21.6", "stdio"),
    ("tgmath.h", "21.11", "tgmath"),
    ("time.h", "21.10", "time"),
    ("fenv.h", "21.12", "fenv"),
  ]
  useRows = [
    ("va_list", "17.1", "stdarg"),
  ]
  ## Same fact as a MISRA row, also a CERT rule whose text is public.
  certCallRows = [
    ("system", "ENV33-C", "calls system"),
    ("atof", "ERR34-C", "string to number without an error return"),
    ("atoi", "ERR34-C", "string to number without an error return"),
    ("atol", "ERR34-C", "string to number without an error return"),
    ("atoll", "ERR34-C", "string to number without an error return"),
    ("atof", "MSC24-C", "obsolescent function"),
    ("atoi", "MSC24-C", "obsolescent function"),
    ("atol", "MSC24-C", "obsolescent function"),
    ("atoll", "MSC24-C", "obsolescent function"),
    ("asctime", "MSC24-C", "obsolescent function"),
    ("ctime", "MSC24-C", "obsolescent function"),
    ("fopen", "MSC24-C", "obsolescent function"),
    ("freopen", "MSC24-C", "obsolescent function"),
    ("rewind", "MSC24-C", "obsolescent function"),
    ("setbuf", "MSC24-C", "obsolescent function"),
    ("gets", "MSC24-C", "obsolescent function"),
    ("rand", "MSC30-C", "rand"),
  ]
  ## Guidelines that need values, linkage, or a whole program. Listed so a
  ## clean run cannot be read as a proof.
  undecidedRows = [
    ("7.4", "a later assignment and a typedef for char are not seen"),
    ("13.5", "a call on the right of && or || is not seen"),
    ("ARR30-C", "pointer and index bounds"),
    ("ARR32-C", "variable-length array size"),
    ("ARR38-C", "library function argument bounds"),
    ("CON37-C", "signal in a multithreaded program"),
    ("DCL30-C", "storage duration"),
    ("DCL31-C", "declare before use, across the program"),
    ("DCL36-C", "conflicting linkage"),
    ("DCL38-C", "flexible array member syntax needs a full declarator"),
    ("DCL39-C", "padding leaked across a trust boundary"),
    ("DCL40-C", "incompatible declarations"),
    ("ENV30-C", "mutating getenv and locale results"),
    ("ENV31-C", "environment pointer invalidated"),
    ("ENV32-C", "exit handlers return normally"),
    ("ENV34-C", "storing pointers from getenv and similar"),
    ("ERR30-C", "errno is thread and call sensitive"),
    ("ERR32-C", "indeterminate errno"),
    ("ERR33-C", "unchecked library errors"),
    ("EXP30-C", "unsequenced side effects"),
    ("EXP32-C", "volatile accessed through a nonvolatile type"),
    ("EXP33-C", "uninitialized read"),
    ("EXP34-C", "null dereference"),
    ("EXP35-C", "temporary lifetime"),
    ("EXP37-C", "argument count and type"),
    ("FIO30-C", "a literal format may be built from user data, and a call through a pointer is not seen"),
    ("FIO39-C", "flush between input and output"),
    ("FIO40-C", "reset a string after fgets fails"),
    ("FLP30-C", "floating loop counter needs types"),
    ("FLP32-C", "floating exceptions"),
    ("INT30-C", "unsigned wrap"),
    ("INT32-C", "signed overflow"),
    ("INT33-C", "a divisor that is not a literal zero"),
    ("INT34-C", "shift width"),
    ("INT35-C", "integer precision"),
    ("INT36-C", "pointer converted to integer"),
    ("MEM30-C", "use after free"),
    ("MEM31-C", "free only what was allocated"),
    ("MEM34-C", "free only allocated memory"),
    ("MEM35-C", "allocation size"),
    ("MEM36-C", "realloc alignment"),
    ("MSC32-C", "how a generator is seeded"),
    ("MSC33-C", "asctime argument range"),
    ("MSC38-C", "a predefined identifier that may be a macro"),
    ("PRE31-C", "a macro defined in another file is not seen"),
    ("SIG30-C", "async-signal-safe calls inside a handler"),
    ("STR31-C", "storage for a string"),
    ("STR32-C", "wide and narrow strings"),
    ("STR34-C", "character converted to unsigned char"),
    ("STR38-C", "wide and narrow string functions"),
  ]
  ## What --matrix prints as checked. Every rule-table id belongs here.
  ## --self-test fails when one is missing or has no counted case.
  checkedIds* = [
    "2.6", "2.7", "4.10", "7.1", "7.3", "7.4", "8.2", "8.14",
    "12.3",
    "13.4", "13.5", "13.6",
    "15.1", "15.2", "15.3", "15.4", "15.5", "15.6", "15.7",
    "16.2", "16.3", "16.4", "16.5", "16.6", "17.1", "17.2", "17.8",
    "18.7", "19.2",
    "20.1", "20.2", "20.3", "20.4", "20.5", "20.7", "20.10", "20.11", "20.12", "20.13", "20.14",
    "21.1", "21.3", "21.4", "21.5", "21.6", "21.7", "21.8", "21.9", "21.10",
    "21.11", "21.12",
    "DCL16-C", "DCL37-C", "DCL41-C", "ENV33-C", "ERR33-C", "ERR34-C",
    "FIO30-C", "INT33-C",
    "MSC17-C", "MSC24-C", "MSC30-C", "MSC37-C", "PRE06-C", "PRE11-C", "PRE31-C",
  ]
  ## Checked for a slice, still not decided for the rest of the guideline.
  partialIds* = ["7.4", "13.5", "ERR33-C", "FIO30-C", "INT33-C", "PRE31-C"]
  keywordList = [
    "auto", "break", "case", "char", "const", "continue", "default", "do",
    "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline",
    "int", "long", "register", "restrict", "return", "short", "signed", "sizeof",
    "static", "struct", "switch", "typedef", "union", "unsigned", "void",
    "volatile", "while", "_Alignas", "_Alignof", "_Atomic", "_Bool", "_Complex",
    "_Generic", "_Imaginary", "_Noreturn", "_Static_assert", "_Thread_local",
    "bool", "true", "false", "nullptr", "static_assert", "thread_local",
    "alignas", "alignof", "typeof", "typeof_unqual",
  ]

import std/options
import std/sets
import std/tables

var callTable = initTable[string, Rule]()
var headerTable = initTable[string, Rule]()
var useTable = initTable[string, Rule]()
var certCalls = initTable[string, seq[CertCite]]()
var keywords = initHashSet[string]()

for row in callRows:
  callTable[row[0]] = Rule(id: row[1], extra: row[2], what: row[3])
for row in headerRows:
  headerTable[row[0]] = Rule(id: row[1], extra: "", what: row[2])
for row in useRows:
  useTable[row[0]] = Rule(id: row[1], extra: "", what: row[2])
for name in keywordList:
  keywords.incl(name)
for row in certCallRows:
  certCalls.mgetOrPut(row[0], @[]).add CertCite(id: row[1], detail: row[2])

proc callRule*(name: string): Option[Rule] =
  if name in callTable: some(callTable[name]) else: none(Rule)

proc headerRule*(base: string): Option[Rule] =
  if base in headerTable: some(headerTable[base]) else: none(Rule)

proc useRule*(name: string): Option[Rule] =
  if name in useTable: some(useTable[name]) else: none(Rule)

proc isKeyword*(name: string): bool =
  name in keywords

proc certForCall*(name: string): seq[CertCite] =
  certCalls.getOrDefault(name)

const err33Names = [
  "malloc", "calloc", "realloc", "aligned_alloc",
  "fopen", "freopen", "fclose", "fflush", "fread", "fwrite",
  "fseek", "ftell", "fgetpos", "fsetpos", "remove", "rename",
  "tmpfile", "setvbuf",
]
var err33 = initHashSet[string]()
for name in err33Names:
  err33.incl(name)

proc ignoresResult*(name: string): bool =
  ## ERR33-C, the part a parse can see: the return value is not used.
  ## An assigned result that is never tested still needs values.
  name in err33

proc reservedName*(name: string): bool =
  ## Always reserved: underscore then uppercase, or two leading underscores.
  ## File-scope names with one leading underscore are also reserved. cite
  ## only applies this to macros and functions it defines, which are file scope.
  if name.len >= 2 and name[0] == '_' and (name[1] == '_' or name[1] in {'A' .. 'Z'}):
    return true
  name.len >= 1 and name[0] == '_'

proc undecided*(): seq[(string, string)] =
  for row in undecidedRows:
    result.add (row[0], row[1])

proc ruledIds*(): seq[string] =
  ## Ids the tables can emit. The matrix has to name each one.
  var seen = initHashSet[string]()
  for row in callRows:
    if row[1] notin seen:
      seen.incl(row[1])
      result.add(row[1])
  for row in headerRows:
    if row[1] notin seen:
      seen.incl(row[1])
      result.add(row[1])
  for row in useRows:
    if row[1] notin seen:
      seen.incl(row[1])
      result.add(row[1])
  for row in certCallRows:
    if row[1] notin seen:
      seen.incl(row[1])
      result.add(row[1])
