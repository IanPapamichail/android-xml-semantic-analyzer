![Language](https://img.shields.io/badge/language-C-blue)
![Tools](https://img.shields.io/badge/tools-Flex%20%7C%20Bison-orange)
![Parsing](https://img.shields.io/badge/domain-Compiler%20Design-purple)
![Status](https://img.shields.io/badge/status-Stable-success)


# XML Semantic Analyzer with Flex & Bison

**A Flex & Bison–based XML semantic analyzer with full BNF grammar and Android-specific validation rules.**

Abstract

This project presents the design and implementation of a compiler-style XML analyzer for Android layout files using Flex and Bison.
The analyzer performs lexical analysis, syntactic validation based on a complete BNF grammar, and semantic validation during parsing.

The system enforces context-aware constraints that cannot be detected by conventional XML validators, demonstrating practical application of compiler construction techniques.

⸻

Methodology

The analyzer is structured in three stages:
	1.	Lexical Analysis
Tokenization of XML input using Flex, including tags, attributes, and values.
	2.	Syntactic Analysis
Definition of a full BNF grammar using Bison to validate the hierarchical structure of XML documents.
	3.	Semantic Analysis
Implementation of semantic checks through grammar actions during parsing.

⸻

Semantic Constraints

The implemented semantic rules include:
	•	Uniqueness of android:id
	•	Validation of android:layout_width and android:layout_height
	•	Constraint enforcement: android:padding > 0
	•	Validation: android:progress ≤ android:max
	•	Consistency between RadioGroup and android:checkedButton
	•	Extended validation: android:count versus actual number of RadioButton elements

⸻

Significance

This work demonstrates how formal grammars and semantic actions can be combined to enforce logical constraints in structured documents.
The approach is applicable to static analysis tools, language validation systems, and compiler-based verification frameworks.


Requirements
	•	Flex
	•	Bison
	•	GCC or Clang

Compilation

bison -d parser.y
flex lexer.l
gcc lex.yy.c parser.tab.c -o myParser

Execution

./myParser < test.xml

Project Structure

.
├── lexer.l          # Lexical analyzer (Flex)
├── parser.y         # BNF grammar + semantic actions (Bison)
├── test.xml         # Sample XML input
├── screenshots/
│   └── demo.png     # Terminal demo screenshot
└── README.md


Example Errors

Semantic error: progress (80) greater than max (60) at line 12

Semantic error: duplicate android:id 'radio1' at line 8


License

This project is provided for educational and academic purposes.
