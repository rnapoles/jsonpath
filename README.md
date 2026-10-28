# JSONPath (RFC 9535) for Object Pascal

Delphi- and Free Pascal-compatible JSONPath parser and evaluator.
Only `SysUtils` and `Classes` are used; no third-party or compiler-specific
JSON/regex libraries.

## Units

| Unit | Purpose |
|---|---|
| `JSONPathLexer.pas` | Scannerless lexer (`FInput`/`FPos`/`FLen`, `PeekChar`, `ConsumeChar`, `MatchToken`) plus the lexical ABNF rules; `EJSONPathParseException` with position, line, column, unexpected token and rule name |
| `JSONPathParser.pas` | Recursive-descent parser (one method per ABNF rule), AST classes, RFC 9535 §2.4.3 function type checking |
| `JSONPathQuery.pas` | Evaluator: selectors, descendant segments, filters, comparisons, `length/count/match/search/value`, normalized paths |
| `JSONPathJSON.pas` | Small JSON DOM, parser and serializer (so no JSON library is needed) |
| `JSONPathRegex.pas` | I-Regexp (RFC 9485) matcher backing `match()`/`search()` (Thompson NFA, no catastrophic backtracking) |
| `JSONPathCommon.pas` | Code point helpers (UTF-8 on FPC, UTF-16 on Delphi), owned list, number formatting |

## Usage

```pascal
uses JSONPathJSON, JSONPathQuery;

var Doc: TJSONValue; Path: TJSONPath; Res: TJSONPathResult;
begin
  Doc := ParseJSON('{"a":[1,2,3]}');
  try
    Path := TJSONPath.Create('$.a[?@ > 1]');   // EJSONPathParseException on bad syntax
    try
      Res := Path.Evaluate(Doc);
      try
        WriteLn(Res.ToJSONText);   // [2,3]
        WriteLn(Res.PathsToText);  // $['a'][1];$['a'][2]
      finally Res.Free; end;
    finally Path.Free; end;
  finally Doc.Free; end;
end.
```

Results reference nodes inside the queried document, so keep the document alive while using a result.

## Tests

One small console program per feature in `tests/` (`Test*.pas`, shared harness in `TestSupport.pas`).

* Free Pascal: `./build.sh`
* Delphi: `tests.bat`

## Known limitations

* I-Regexp `\p{..}` / `\P{..}` Unicode category escapes are not supported; such patterns are treated as invalid, so `match()`/`search()` return false.
* Delphi string comparison for `<`/`>` is by UTF-16 code unit, which differs from code point order only for supplementary characters.
* Only the five built-in functions exist; there is no extension registry.
