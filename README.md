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

## JsonSerializer

`JsonSerializer.pas` converts an object graph to a `TJSONValue` via RTTI: `TJsonSerializer.Serialize(Obj)` (caller frees the result) or `SerializeToText(Obj, 2)`. Use `[JsonName('key')]` on a property to choose its JSON key. On Free Pascal put classes under `{$M+}` with `published` properties and enable `{$modeswitch prefixedattributes}`; Delphi also sees public properties.

## Custom functions

Register a function once, then use it in any filter. Handlers receive the evaluated arguments and return a `Func*` result:

```pascal
uses JSONPathParser, JSONPathQuery;

function FnUpper(Args: TJSONPathArgs): TJSONPathFuncResult;
begin
  if Args.IsString(0) then
    Result := FuncString(UpperCase(Args.AsString(0)))
  else
    Result := FuncNothing;
end;

function FnBetween(Args: TJSONPathArgs): TJSONPathFuncResult;
begin
  Result := FuncLogical((Args.AsNumber(0) >= Args.AsNumber(1)) and (Args.AsNumber(0) <= Args.AsNumber(2)));
end;

RegisterJSONPathFunction('upper',   [vtValue], vtValue, FnUpper);
RegisterJSONPathFunction('between', [vtValue, vtValue, vtValue], vtLogical, FnBetween);
// $[?upper(@.name) == "ANN" && between(@.age, 18, 65)]
```

* Parameter types: `vtValue` (literal, singular query or value function; `Args.IsNothing(i)` when empty), `vtNodes` (any query; `Args.NodeCount(i)` / `Args.Node(i, k)`), `vtLogical` (logical expression; `Args.AsBoolean(i)`).
* Result types: `vtValue` (`FuncNumber`, `FuncString`, `FuncBool`, `FuncNull`, `FuncValue`, `FuncNothing`) or `vtLogical` (`FuncLogical`, usable directly as a test).
* Handlers can be plain functions or methods (`RegisterJSONPathFunction('f', [vtValue], vtValue, Obj.Method)`). `TJSONPath.RegisterFunction` / `UnregisterFunction` are shortcuts; `IsJSONPathFunctionRegistered` checks a name.
* Queries are type-checked against the registered signatures, exactly like the built-ins. Names follow the RFC grammar (lowercase letter, then lowercase letters, digits or `_`) and cannot reuse `length`, `count`, `match`, `search` or `value`.
* Register at start-up (registration is not thread-safe). Unregistering or replacing a function does not affect queries that were already parsed.

## JSON Schema validation

`schema/` contains a modular JSON Schema framework (Draft 4, 6, 7, 2019-09, 2020-12) on top of `JSONPathJSON.pas`: draft classes, registries for custom types / formats / keywords, schema registration and file/directory loading, `$ref` resolution, collected validation errors with schema and instance locations, and return-based or exception-based error handling. See **[docs/JSON_SCHEMA.md](docs/JSON_SCHEMA.md)** for the architecture, compatibility constraints, supported/unsupported features and the extension guide. Samples are in `schema/samples`, tests in `schema/tests` (run by the same `tests` scripts).

```pascal
V := TJsonSchemaValidator.Create;
V.RegisterSchema('person', '{"type":"object","required":["name"]}');
R := V.ValidateText('{}', 'person');   // R.IsValid, R.Errors[i].Keyword / SchemaLocation / InstanceLocation
R.Free; V.Free;
```

## TJSONValue conversions

`TJSONValue` has kind tests (`IsNull`, `IsBoolean`, `IsNumber`, `IsInteger`, `IsString`, `IsArray`, `IsObject`) and lenient conversions (`AsBoolean`, `AsNumber`, `AsInteger`, `AsString`) that never raise: a value that cannot be converted yields `False`, `0` or `''`. Rules are listed next to the properties in `JSONPathJSON.pas` (for example `AsBoolean` is False for null, `0`, `""`, empty arrays and empty objects; `AsString` of an array or object is its compact JSON text).

## JSON model: lossless numbers, parser/writer options, builder

**Lossless numbers.** A parsed number keeps its original text, its `Double` value and, when possible, an exact form: an `Int64` for integer literals (64-bit ids) and an unscaled `Int64` + scale for plain decimals (money). `1` and `1.0` stay different texts but compare equal; `9223372036854775807` survives parsing, comparison and writing; `19.99` is exactly `1999/10^2` (`TryGetDecimal`, `AsCurrency`); numbers too large or written with an exponent keep their text. Related API: `NumberText`, `IsExactInt64`, `TryGetInt64`, `TryGetDecimal`, `AsCurrency`, `NewJSONInt64`, `NewJSONDecimal`, `NewJSONNumberText`, `JSONNumberCompare`. Assigning `NumberValue` discards the exact forms.

**Parser options** (`ParseJSON(Text, Options)`; presets `DefaultJSONParseOptions`, `LenientJSONParseOptions`): `AllowComments` (`//` and `/* */`), `AllowTrailingCommas`, `DuplicateKeys` (`dkLastWins`, `dkFirstWins`, `dkError`) and `MaxDepth` (default 512, counts nested arrays/objects). `EJSONPathJSONError` carries `Position` (0-based offset), `Line` and `Column` (1-based; bytes on Free Pascal, UTF-16 units on Delphi).

**Writer options** (`JSONToText(Value, Options)`, preset `DefaultJSONWriteOptions`): `Indent`, `SortKeys` (UTF-16 code unit order), `EscapeNonAscii`, `OriginalNumbers` (default True: numbers are written exactly as parsed; False normalises through `Double`) and `Canonical` (RFC 8785, also `JSONCanonicalText`). Canonical numbers use IEEE doubles by definition, so integers above 2^53 are rounded in canonical output. The shortest-digits search relies on `StrToFloat` round trips and can in rare cases print one digit too many on Free Pascal (80-bit `Extended` parsing).

**Fluent builder** (`TJSONBuilder`):

```pascal
B := TJSONBuilder.Create;
Doc := B.BeginObject
         .PutString('name', 'Ann')
         .PutInt('id', 9223372036854775807)
         .PutDecimal('price', 1999, 2)
         .BeginArray('tags').AddString('a').AddString('b').EndArray
         .BeginObject('address').PutString('city', 'Oslo').EndObject
       .EndObject.Build;      // the caller owns Doc
B.Free;
```

Inside an object use `Put*` / `Begin*(Name)`, inside an array (or at the root) use `Add*` / `Begin*`; misuse raises `EJSONBuilderError`.

## Tests

One small console program per feature in `tests/` (`Test*.pas`, shared harness in `TestSupport.pas`).

* Free Pascal: `./build.sh`
* Delphi: `tests.bat`

## Known limitations

* I-Regexp `\p{..}` / `\P{..}` Unicode category escapes are not supported; such patterns are treated as invalid, so `match()`/`search()` return false.
* Delphi string comparison for `<`/`>` is by UTF-16 code unit, which differs from code point order only for supplementary characters.
* Only the five built-in functions exist;
