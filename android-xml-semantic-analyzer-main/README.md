<div align="center">

# Android XML Semantic Analyzer

**A compiler front end for Android layout XML, built with Flex and Bison.**
It runs lexical, syntactic and semantic analysis, and reports every error with its line number in a single pass.

[![License: MIT](https://img.shields.io/github/license/IanPapamichail/android-xml-semantic-analyzer?color=blue)](LICENSE)
[![Top language](https://img.shields.io/github/languages/top/IanPapamichail/android-xml-semantic-analyzer)](https://github.com/IanPapamichail/android-xml-semantic-analyzer)
[![Last commit](https://img.shields.io/github/last-commit/IanPapamichail/android-xml-semantic-analyzer)](https://github.com/IanPapamichail/android-xml-semantic-analyzer/commits/main)
[![Repo size](https://img.shields.io/github/repo-size/IanPapamichail/android-xml-semantic-analyzer)](https://github.com/IanPapamichail/android-xml-semantic-analyzer)
<br>
![C11](https://img.shields.io/badge/C-C11-00599C?logo=c&logoColor=white)
![Flex](https://img.shields.io/badge/lexer-Flex%202.6-orange)
![Bison](https://img.shields.io/badge/parser-Bison%203.x-orange)
![Domain](https://img.shields.io/badge/domain-compiler%20construction-purple)
![Tests](https://img.shields.io/badge/tests-19%20passing-success)

`compiler` · `flex` · `bison` · `lexer` · `parser` · `semantic-analysis` · `bnf-grammar` · `static-analysis` · `android` · `xml` · `c`

</div>

---

## Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Grammar](#grammar)
- [Semantic rules](#semantic-rules)
- [Building](#building)
- [Usage](#usage)
- [Diagnostics](#diagnostics)
- [Testing](#testing)
- [Implementation notes](#implementation-notes)
- [Project layout](#project-layout)
- [License](#license)

## Overview

A general-purpose XML validator checks only that a document is well formed. Android layouts also have rules that depend on context: ids must be unique across the whole document, a `ProgressBar`'s `progress` cannot exceed its `max`, and a `RadioGroup`'s `checkedButton` must name one of its own children.

This project enforces those rules with classic compiler techniques. A Flex scanner tokenizes the input, a BNF grammar in Bison validates the structure, and semantic actions attached to the grammar enforce the rules while the parse tree is built.

## Architecture

```
            ┌──────────────┐   tokens    ┌──────────────┐  reductions  ┌──────────────────┐
 layout ──▶ │   Scanner    │ ──────────▶ │    Parser    │ ───────────▶ │ Semantic actions │ ──▶ diagnostics
  .xml      │  lexer.l     │  + line no. │  parser.y    │              │ element stack,   │     + exit code
            │  (Flex)      │             │  LALR(1)     │              │ symbol table     │
            └──────────────┘             └──────────────┘              └──────────────────┘
```

| Stage | Responsibility |
|-------|----------------|
| **Lexical analysis** | Produces `<`, `</`, `>`, `/>`, `=`, names and quoted strings. Skips whitespace, the `<?xml ...?>` declaration and `<!-- comments -->`. Tracks line numbers with `yylineno` and Bison locations. |
| **Syntactic analysis** | An LALR(1) grammar for nested elements with attributes and self-closing tags. |
| **Semantic analysis** | Runs on each reduction. It keeps a stack of open elements, each with its own state, and a document-wide table of declared ids. |

## Grammar

```bnf
<document>   ::= <elements>
<elements>   ::= <element> | <elements> <element>
<element>    ::= <open-tag> <attributes> ">" <content> "</" NAME ">"
               | <open-tag> <attributes> "/>"
<open-tag>   ::= "<" NAME
<attributes> ::= ε | <attributes> NAME "=" STRING
<content>    ::= ε | <elements>
```

The shared `<open-tag>` nonterminal pushes the new element onto the stack as soon as its name is read. The element's own attributes, such as a `RadioGroup`'s `android:count`, are therefore checked against the correct element.

## Semantic rules

| # | Rule | Example diagnostic |
|---|------|--------------------|
| 1 | `android:id` is unique within the document | `duplicate android:id 'title' (first declared at line 5)` |
| 2 | `android:id` has the form `@+id/name` or `@id/name` | `android:id must be "@+id/name", got "title"` |
| 3 | `layout_width` / `layout_height` are `wrap_content`, `match_parent`, or a positive size | `android:layout_height has invalid value "0dp" (...)` |
| 4 | `android:padding` > 0 | `android:padding must be > 0, got 0` |
| 5 | `android:progress` ≥ 0 | `android:progress must be >= 0, got -5` |
| 6 | `android:progress` ≤ `android:max` on the same element | `android:progress (80) is greater than android:max (60) in <ProgressBar>` |
| 7 | A `RadioGroup`'s `android:checkedButton` names one of its `RadioButton`s | `android:checkedButton 'option_c' is not a RadioButton in this RadioGroup` |
| 8 | A `RadioGroup`'s `android:count` is a positive integer | `android:count must be a positive integer, got "0"` |
| 9 | A `RadioGroup`'s `android:count` equals the number of `RadioButton`s it contains | `RadioGroup declares android:count=3 but contains 2 RadioButton(s)` |
| 10 | A closing tag matches its opening tag | `closing tag </RelativeLayout> does not match <LinearLayout> opened at line 1` |

Sizes may carry a unit (`48dp`, `16sp`), because rules 3–6 read the leading integer of the value.

## Building

**Requirements:** a C11 compiler (GCC or Clang), Flex 2.6+, Bison 3.0+ and `make`.

```bash
make            # builds ./analyzer
make test       # builds and runs the test suite
make clean
```

> **macOS:** the Bison in `/usr/bin` is version 2.3, which is too old. Install a newer one with `brew install bison flex`, then put it first on your PATH or run `make BISON=$(brew --prefix bison)/bin/bison`.

The generated sources (`parser.tab.c`, `parser.tab.h`, `lex.yy.c`) are written to `build/` and are not committed.

## Usage

```
analyzer [-t] [file.xml]

  Reads standard input when no file is given.
  -t, --tokens   print each token as it is scanned
  -h, --help     show this help
```

```console
$ ./analyzer tests/valid/sample_layout.xml
tests/valid/sample_layout.xml: valid
```

## Diagnostics

Errors use the familiar `file:line: error: message` format and go to standard error. The analyzer doesn't stop at the first problem: it reports every lexical and semantic error, then prints a summary.

```console
$ ./analyzer tests/invalid/multiple_errors.xml
multiple_errors.xml:5: error: android:layout_height has invalid value "-1" (expected wrap_content, match_parent or a positive size)
multiple_errors.xml:6: error: android:padding must be > 0, got 0
multiple_errors.xml:9: error: duplicate android:id 'label' (first declared at line 8)
multiple_errors.xml:11: error: android:progress (80) is greater than android:max (60) in <ProgressBar>
multiple_errors.xml:20: error: android:checkedButton 'missing' is not a RadioButton in this RadioGroup
multiple_errors.xml:17: error: RadioGroup declares android:count=3 but contains 2 RadioButton(s)
multiple_errors.xml: 6 errors
```

| Exit code | Meaning |
|-----------|---------|
| `0` | Document is valid |
| `1` | One or more lexical, syntax or semantic errors |
| `2` | Usage error, or the input file could not be opened |

## Testing

`make test` runs [`tests/run.sh`](tests/run.sh):

| Suite | What it checks |
|-------|----------------|
| `tests/valid/*.xml` | Each file is accepted (exit 0). |
| `tests/invalid/*.xml` | Each file is rejected (exit 1), and its output exactly matches the matching `.expected` file. There is one file per rule, plus lexical, syntax and multiple-error cases. |
| Stress (generated) | 5,000 unique 300-character ids; the same set with one duplicate (exactly one error); a `RadioGroup` with 500 buttons. |

To add a regression case, drop an `.xml` file into `tests/invalid/` and record its expected output:

```bash
cd tests/invalid && ../../analyzer new_case.xml > new_case.expected 2>&1
```

## Implementation notes

- **No fixed-size buffers.** Ids, element names and `RadioGroup` children live in heap storage that grows as needed, so the length and number of ids are limited only by memory. The test suite runs cleanly under AddressSanitizer and UndefinedBehaviorSanitizer.
- **Per-element state.** Each open element has its own frame on a stack, so nested layouts don't overwrite each other's `progress`, `max` or `RadioGroup` state.
- **Error reporting.** Every diagnostic goes through `diag_error()`, which counts the error and lets the analysis continue. The scanner reports an unexpected character and skips it.
- **Locations.** Bison `%locations` plus `yylineno` attach each error to the line of the attribute that caused it, not to wherever the parser's lookahead happens to be.
- **Bounded integers.** Numbers are parsed with `strtol` and overflow is detected, instead of using `sscanf("%d")`.

**Limitations:** this analyzer covers the XML subset used in Android layouts. Text content, CDATA, entity references and single-quoted attribute values aren't supported. Parsing stops at the first syntax error. All lexical and semantic errors found before that point are still reported.

## Project layout

```
.
├── lexer.l              Flex scanner
├── parser.y             Bison grammar, semantic actions, main()
├── Makefile
├── tests/
│   ├── run.sh           Test runner (make test)
│   ├── valid/           Layouts that must be accepted
│   └── invalid/         Layouts that must be rejected, with .expected output
├── LICENSE
└── README.md
```

## License

Released under the [MIT License](LICENSE). © 2026 Nickolas-Adrian Papamichail.
