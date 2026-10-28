# JSONPath compliance test suite runner

`cts/jsonpath_cts.pas` is a command line program that runs the official
[JSONPath Compliance Test Suite](https://github.com/jsonpath-standard/jsonpath-compliance-test-suite)
against this library. The logic lives in `cts/JSONPathCTS.pas` (class
`TCtsRunner`), the program is a thin wrapper around it.

> Written without a Pascal compiler at hand: build it first (`./build_cts.sh`)
> and report any compile errors.

## Build and run

```
./build_cts.sh                                  # Free Pascal; Windows: build_cts_fpc.bat
./build/cts/jsonpath_cts path/to/cts.json
./build/cts/jsonpath_cts path/to/jsonpath-compliance-test-suite/      # scans a folder
```

Delphi: `dcc64 -U".;schema;cts" -E build\cts cts\jsonpath_cts.pas`.

## Input

A **file** is one suite file in the format of `cts/cts.schema.json`:

```json
{ "tests": [
  { "name": "...", "selector": "$.a", "document": {"a": 1},
    "result": [1], "result_paths": ["$['a']"] },
  { "name": "...", "selector": "$.*", "document": {"a": 1, "b": 2},
    "results": [[1, 2], [2, 1]],
    "results_paths": [["$['a']", "$['b']"], ["$['b']", "$['a']"]] },
  { "name": "...", "selector": "$..", "invalid_selector": true }
] }
```

A **directory** is scanned (recursively unless `--no-recursive`) for files ending
in `.json` (`--ext` changes that). `cts.schema.json` and other `*.schema.json`
files are skipped. Several paths may be given.

## How a test is judged

| Test case | Passes when |
|---|---|
| `invalid_selector: true` | the selector is **rejected** by the parser |
| `result` (+ `result_paths`) | the selected values equal `result` (same order, JSON equality) and the normalized paths equal `result_paths` |
| `results` (+ `results_paths`) | one alternative *i* matches: values equal `results[i]` and paths equal `results_paths[i]` (for object member order that is not defined) |

A valid selector that the parser rejects, a missing `document`, an evaluation
error or a malformed test case fail the test with an explanation (selector,
reason, expected, actual).

## Validation against `cts.schema.json`

Suite files are validated with the JSON Schema framework of this project before
they are run (Draft 2020-12 with `$ref`, `oneOf`, `const` and patterns). A file
that violates the schema is reported (first five schema errors) and skipped.
The schema is `--schema <file>` or, by default, `cts.schema.json` found next to
the input, in the current directory, next to the program or in `../cts` next to
the program. `--no-validate` turns this off. If no schema is found a note is
printed and files are run unvalidated.

## Options

| Option | Meaning |
|---|---|
| `-f, --filter <text>` | only tests whose name contains the text (case-insensitive) |
| `-t, --tag <tag>` | only tests with this tag |
| `--fail-fast` | stop after the first failing test |
| `-v, --verbose` | also list passing tests |
| `-q, --quiet` | summary only |
| `--no-recursive` | do not descend into sub directories |
| `--ext <list>` | file endings, e.g. `".json;.cts"` |
| `--schema <file>` / `--no-validate` | see above |
| `-h, --help` | usage |

`--option=value` is accepted too.

## Output and exit codes

```
FAIL [cts/basic.json] name selector, dot notation
     selector: $.a
     reason:   the selected values differ from "result"
     expected: ["x"]
     actual:   []

Files: 3  Tests: 120  Passed: 118  Failed: 2  Skipped: 0  File errors: 0
```

| Exit code | Meaning |
|---|---|
| 0 | every selected test passed |
| 1 | at least one test failed |
| 2 | usage error, or a file could not be read, parsed or validated (takes precedence over 1) |

## Known differences to expect

The runner reports what the library does; the official suite will likely expose
real gaps. Documents are parsed with the strict JSON parser of this project
(lone surrogates or numbers outside the Double range are file errors), and
JSONPath literals are compared as Doubles. Selector result order for objects
follows document order, which the suite's `results` alternatives allow.

## Tests

`cts/tests/TestCtsRunner.pas` covers pass/fail judging, `results` alternatives,
filters, fail-fast, malformed cases, folder scanning, extensions, schema
validation (a small schema plus the real `cts.schema.json` accepting and
rejecting suite files). Run all tests with `./run_tests.sh`.
