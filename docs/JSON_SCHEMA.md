# JSON Schema validation framework

A modular JSON Schema validator for Delphi and Free Pascal built on the existing
`JSONPathJSON.pas` model. Units live in `schema/`, tests in `schema/tests/`,
examples in `schema/samples/`.

> **Status:** written without access to a Pascal compiler. Nothing here has been
> compiled or run yet; expect to fix a few compile-level nits on the first build
> (`./test.sh` or `test.bat`).

## 1. What the existing code base dictates (read before designing)

| Finding in the existing code | Consequence for the framework |
|---|---|
| `TJSONValue` stores every number as a `Double` plus its original text and, when possible, an exact `Int64`/decimal form (see README, "Lossless numbers"). | Schema keywords still compare through the `Double` value, and `integer` means "number without fractional part" in **every** draft. Draft-04's rule "1.0 is not an integer" is not enforced although the text `1.0` is now preserved. Equality (`enum`, `const`, `uniqueItems`) is exact for 64-bit integers and plain decimals. |
| Object members keep insertion order; duplicate names: last wins. | Error order and `additionalProperties` iteration are deterministic. |
| `JSONEquals` implements deep equality with numeric value comparison. | Reused as-is for `enum`, `const` and `uniqueItems` (exactly the JSON Schema equality rules). |
| `CodePointLength` counts Unicode scalar values on both UTF-8 (FPC) and UTF-16 (Delphi). | Reused for `minLength` / `maxLength`. |
| `TOwnedList` is the project's ownership primitive. | Reused for every owning list; two small additions were needed (`Delete`, `TruncateTo`). |
| The regex engine is I-Regexp (RFC 9485): no `^`/`$` anchors, no `\d \w \s`, always whole-string or substring. | JSON Schema `pattern` is ECMA 262. `JsonSchemaRegex` translates the common ECMA subset and `TIRegexp.IsFind` (new) provides anchored/unanchored search. Unsupported syntax is a **schema error**, never silently ignored. |
| No JSON Pointer support; JSONPath is a different language. | A small JSON Pointer helper is part of `JsonSchemaErrors`; JSONPath is not applicable to `$ref` or error locations. |
| `ParseJSON` raises `EJSONPathJSONError`, depth limit 512. | Mapped to `ESchemaLoadError` / `ESchemaError` / `EJsonSchemaError`. |
| No generics / anonymous methods are used (FPC 3.2 compatibility). | Callbacks are plain function types plus `of object` variants. Named array types are used everywhere (Delphi treats each `array of X` as distinct). |

## 2. Architecture

```
JsonSchemaErrors   error model, exceptions, JSON Pointer helpers
JsonSchemaCore     abstractions: contexts, callback types, registries, draft base class
JsonSchemaRegex    ECMA -> I-Regexp translation + pattern cache
JsonSchemaKeywords built-in types, formats, keyword validators and checkers (plain functions)
JsonSchemaDrafts   Draft 4, 6, 7, 2019-09, 2020-12 (each derives from the previous)
JsonSchemaStore    URI resolution, compiled schemas, schema store + $ref resolver, compiler
JsonSchemaEvaluator the validation engine (implements TKeywordContext)
JsonSchemaLoader   file / directory I/O
JsonSchemaValidator the public facade
```

Dependencies only point downwards in that list.

| Class | Single responsibility |
|---|---|
| `TValidationError`, `TValidationErrors`, `TValidationResult` | describe, collect and return problems |
| `EJsonSchemaError` family | signal problems (see section 5) |
| `TKeywordContext` / `TCompileContext` | the *only* view keyword code has of the engine (dependency inversion) |
| `TTypeRegistry`, `TFormatRegistry`, `TKeywordRegistry` | named definitions with one documented override policy |
| `TJsonSchemaDraft` (+ subclasses) | everything draft-specific: keyword table, id keyword, `$ref` sibling rule, boolean schemas |
| `TDraftRegistry` | draft management and detection (`$schema`, configurable default) |
| `TSchemaCompiler` | schema parsing: applies keyword checkers, indexes `$id`/anchors, records `$ref`s, raises `ESchemaError` |
| `TCompiledSchema`, `TSchemaStore` | compiled schemas by id, `$ref` resolution, caching |
| `TSchemaEvaluator` | executes keywords against an instance, tracks locations |
| `TSchemaFileLoader` | reads files, lists directories |
| `TJsonSchemaValidator` | wires everything together; configuration and policies |

Patterns used: **Template Method** (`TJsonSchemaDraft.RegisterKeywords`),
**Strategy** (keyword/type/format callbacks), **Registry**, **Facade**,
**Dependency Inversion** (abstract contexts), **Inheritance chain** between drafts
(open/closed: a new draft never edits an old one).

## 3. Quick start

```pascal
uses JsonSchemaErrors, JsonSchemaValidator;

V := TJsonSchemaValidator.Create;
try
  V.RegisterSchema('person', '{"type":"object","required":["name"]}');
  R := V.ValidateText('{}', 'person');          // return mode (default)
  try
    if not R.IsValid then WriteLn(R.ErrorText);
  finally
    R.Free;                                       // caller owns the result
  end;
finally
  V.Free;                                         // owns schemas and registries
end;
```

### Lifecycle and ownership

* The validator owns its registries, compiled schemas and registered documents; free it last.
* `RegisterSchema(Id, TJSONValue)` **transfers ownership** of the value, even when compilation fails (it is freed then). The text overload parses for you.
* Schemas are compiled once, at registration. Invalid schemas raise `ESchemaError` immediately and are not registered.
* `Validate*` return a `TValidationResult` that **the caller frees**. The instance is only borrowed.
* `ValidateWithSchema(Instance, Schema)` compiles for one call; the caller keeps the schema.
* Replacing/unregistering a schema keeps the old compiled schema alive until the validator is freed (other schemas may point into it).
* Not thread-safe: one validator per thread.

## 4. Supported drafts and keywords

| Draft name | `$schema` URI | Notes |
|---|---|---|
| `draft-04` | `http://json-schema.org/draft-04/schema` | `id`, boolean `exclusiveMinimum/Maximum`, no boolean schemas, `$ref` replaces siblings, `required` must be non-empty |
| `draft-06` | `http://json-schema.org/draft-06/schema` | `$id`, numeric `exclusiveMinimum/Maximum`, `const`, `contains`, `propertyNames`, boolean schemas |
| `draft-07` | `http://json-schema.org/draft-07/schema` | adds `if` / `then` / `else` |
| `2019-09` | `https://json-schema.org/draft/2019-09/schema` | `dependentRequired`, `dependentSchemas`, `minContains`/`maxContains`, `$defs`, `$anchor`, `$ref` evaluated with siblings; `dependencies` removed |
| `2020-12` (default) | `https://json-schema.org/draft/2020-12/schema` | `prefixItems`, `items` applies after the prefix; `additionalItems` removed |

A trailing `#` in `$schema` is optional. Schemas without `$schema` use
`DefaultDraftName` (`'2020-12'`, change with `UseDraft`).

Implemented keywords (per draft as above): `type`, `enum`, `const`, `allOf`,
`anyOf`, `oneOf`, `not`, `if/then/else`, `properties`, `patternProperties`,
`additionalProperties`, `propertyNames`, `required`, `minProperties`,
`maxProperties`, `dependencies`, `dependentRequired`, `dependentSchemas`,
`items`, `additionalItems`, `prefixItems`, `contains`, `minContains`,
`maxContains`, `minItems`, `maxItems`, `uniqueItems`, `minimum`, `maximum`,
`exclusiveMinimum`, `exclusiveMaximum`, `multipleOf`, `minLength`, `maxLength`,
`pattern`, `format`, `$ref`, `$id`/`id`, `$anchor`, `definitions`/`$defs`.
Annotation keywords (`title`, `description`, `default`, `examples`, ...) and
unknown keywords are ignored.

Built-in types: `null boolean object array number string integer`.
Built-in formats: `date time date-time email hostname ipv4 ipv6 uuid uri json-pointer`
(simplified, documented checks; unknown formats are annotations only; switch
assertion off with `AssertFormats := False`).

### Not supported (and what happens)

| Feature | Behaviour |
|---|---|
| `unevaluatedItems`, `unevaluatedProperties` (2019-09, 2020-12) | schema rejected with `ESchemaError` (or ignored with `IgnoreUnsupportedKeywords := True`) |
| `$recursiveRef`/`$recursiveAnchor` (2019-09), `$dynamicRef`/`$dynamicAnchor` (2020-12) | same as above |
| Meta-schema validation | not performed; every keyword has a *checker* that validates the shape of its value instead (types, ranges, nested subschemas, patterns, `$ref` targets) |
| Remote `$ref` (http/https) | never fetched; register the document under its URI instead |
| `$vocabulary`, `contentMediaType`, `contentEncoding`, `contentSchema` | ignored |
| ECMA regex features beyond the subset in `JsonSchemaRegex` | `ESchemaError` |
| 1.0 vs 1 distinction (draft-04) | impossible with the JSON model |
| Percent-decoding of non-ASCII `$ref` fragments on Delphi | ASCII only |
| `uniqueItems` complexity | O(n^2) |

## 5. Errors

Two families, deliberately separate:

| Exception | Meaning | When raised |
|---|---|---|
| `ESchemaError` | the **schema** is invalid / unsupported / has an unresolvable `$ref` | always (registration, or first use of a deferred `$ref`) |
| `EValidationError` | the **instance** is invalid | only when `ErrorMode = emRaise` |
| `ESchemaRegistrationError` | duplicate or unknown ids, registration-policy violations, bad draft/keyword config | always |
| `ESchemaLoadError` (`FileName`) | missing/unreadable file or directory, malformed JSON | always |
| `EJsonSchemaError` | base class; also nil instance / instance text that is not JSON | always |

`ESchemaError` and `EValidationError` carry `Errors: TValidationErrors`. Each
`TValidationError` has `Message`, `Keyword`, `SchemaLocation` (JSON Pointer to
the failing keyword, following `$ref` steps, e.g. `/properties/a/$ref/type`)
and `InstanceLocation` (JSON Pointer into the instance). All errors of one run
are collected unless `StopOnFirstError` is set (stops after the first failing
keyword of a schema object).

| Setting | Values (default first) | Effect |
|---|---|---|
| `ErrorMode` | `emReturn`, `emRaise` | invalid instances are returned in the result / raised as `EValidationError` |
| `DuplicatePolicy` | `dpRaise`, `dpReplace`, `dpSkip` | schema id already registered |
| `LoadErrorPolicy` | `lpRaise`, `lpCollect` | bad files in `LoadSchemaDirectory` (`LoadErrors` lists skipped files); `LoadSchemaFile` always raises |
| `AssertFormats` | `True` / `False` | `format` assertion |
| `IgnoreUnsupportedKeywords` | `False` / `True` | reject or skip keywords the framework cannot evaluate |
| `MaxDepth` | 200 | evaluation nesting limit (guards circular `$ref`s; raises `ESchemaError`) |

## 6. Schemas, files and `$ref`

* `RegisterSchema(Id, ...)`; an empty id falls back to the schema's `$id`/`id`.
* `LoadSchemaFile(File, Id = '')`: id = explicit id, else the schema's own id, else the file name without extension.
* `LoadSchemaDirectory(Dir, Recursive = True)` loads files whose name ends with one of `SchemaFileExtensions` (default `.json`; e.g. `'.schema.json;.json'`), sorted by path, UTF-8 (BOM ignored).
* A `$ref` is resolved against the base URI in effect (nearest `$id`), then looked up in the same schema's resources, in all registered schemas' resources, and finally as a registered schema id; the fragment is empty, a JSON Pointer or an anchor (`$anchor`, or `$id: "#name"` in drafts up to 07). References to schemas registered later are resolved on first use, so registration order does not matter.

## 7. Extending the framework

Registration policy for **types, formats and keywords**: a new name always
works; an existing name raises `ESchemaRegistrationError` unless
`AllowOverride = True`. Validator-level keywords apply to every draft and win
over a draft's own definition; draft-level keywords live in
`Draft.Keywords` and only affect that draft.

### Custom type

```pascal
function TypeEven(AValue: TJSONValue): Boolean;
begin
  Result := (AValue.Kind = jkNumber) and (Frac(AValue.NumberValue) = 0)
    and (Trunc(AValue.NumberValue) mod 2 = 0);
end;
V.RegisterType('even', TypeEven);          // "type": "even"
V.RegisterType('integer', TypeEven, True); // override a built-in (explicit)
```

### Custom keyword (parameters, configuration, subschemas)

```pascal
function KwDivisibleBy(Ctx: TKeywordContext): Boolean;
begin
  Result := True;
  if Ctx.Instance.Kind <> jkNumber then Exit;          // not applicable
  Result := Frac(Ctx.Instance.NumberValue / Ctx.KeywordValue.NumberValue) = 0;
  if not Result then Ctx.AddError('not divisible by ' + JSONToText(Ctx.KeywordValue));
end;

procedure CheckDivisor(Ctx: TCompileContext);          // runs when the schema is compiled
begin
  if (Ctx.KeywordValue.Kind <> jkNumber) or (Ctx.KeywordValue.NumberValue = 0) then
    Ctx.Error('"divisibleBy" must be a non-zero number');
end;

V.RegisterKeyword('divisibleBy', KwDivisibleBy, '', CheckDivisor);
V.RegisterKeyword('startsWith', KwStartsWith, '{"caseSensitive":false}'); // Ctx.Config
```

`TKeywordContext` offers: `Instance`, `Schema`, `KeywordValue` (the parameter),
`Sibling(name)`, `Config`, `InstanceLocation`, `SchemaLocation`, `AddError`,
`ValidateSubschema` (reports errors), `TestSubschema` (quiet), `TypeMatches`,
`RegexSearch`, `FormatValid`. Return `False` without `AddError` and a generic
message naming the keyword is reported. Keywords that contain subschemas use a
checker that calls `Ctx.CompileSubschema` / `Ctx.CompileChild` (see
`CheckSchema`, `CheckSchemaMap`, ... in `JsonSchemaKeywords`). Methods work too
(`V.RegisterKeyword('k', Obj.Method)`).

### Custom format

```pascal
V.RegisterFormat('sku', FormatSku);   // function(const AText: string): Boolean
```

### Adding a draft (no existing class is modified)

```pascal
type
  TDraft2030 = class(TJsonSchemaDraft202012)
  protected
    procedure RegisterKeywords; override;   // call inherited, then add / replace / Unregister
  public
    function Name: string; override;            // 'draft-2030'
    function MetaSchemaUri: string; override;   // value of "$schema"
  end;

V.Drafts.RegisterDraft(TDraft2030.Create);      // the registry takes ownership
V.UseDraft('draft-2030');                       // optional: make it the default
```

Override `IdKeyword`, `RefOverridesSiblings` or `SupportsBooleanSchemas` when the
draft differs. A draft derived from `TJsonSchemaDraft` directly must register
every keyword itself (use the functions in `JsonSchemaKeywords`).

## 8. Tests and samples

* `./test.sh` (FPC/Linux), `test.bat`, `run_tests.bat` (Delphi) build and run every `tests/Test*.pas` and `schema/tests/Test*.pas`.
* Schema tests: `TestSchemaTypes`, `Numeric`, `Strings`, `Formats`, `Arrays`, `Objects`, `Composition`, `Refs`, `DraftSelection`, `Malformed`, `ErrorReporting`, `Registry`, `CustomTypes`, `CustomKeywords`, `CustomDraft`, `Filesystem`, `Regex`, `UriAndPointer`.
* Samples (`./build_samples.sh`, run from `schema/samples`): `SampleSchemaBasics` (draft selection, registration, return mode), `SampleSchemaExtensions` (custom type/keyword/format), `SampleSchemaErrorModes` (return vs raise, schema vs instance errors), `SampleSchemaFiles` (directory loading, cross-file `$ref`).
