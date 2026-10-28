{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestSchemaMalformed;

{$APPTYPE CONSOLE}

uses
  TestSupport, SchemaTestSupport, SysUtils, JsonSchemaErrors, JsonSchemaValidator;

procedure NotJsonAndIgnoreTests;
var
  V: TJsonSchemaValidator;
  Raised: Boolean;
  R: TValidationResult;
begin
  V := NewValidator;
  try
    Raised := False;
    try
      V.RegisterSchema('bad', '{"type":');
    except
      on E: ESchemaError do
        Raised := Pos('not valid JSON', E.Message) > 0;
    end;
    Check(Raised, 'schema text that is not JSON raises ESchemaError');
    Check(not V.HasSchema('bad'), 'a rejected schema is not registered');
    V.IgnoreUnsupportedKeywords := True;
    V.RegisterSchema('lenient', '{"unevaluatedProperties":false,"type":"object"}');
    R := V.ValidateText('{"a":1}', 'lenient');
    try
      Check(R.IsValid, 'IgnoreUnsupportedKeywords skips keywords that cannot be evaluated');
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

begin
  BeginSuite('Schema: malformed schemas and unsupported features');
  Check(SchemaIsInvalid('{"type":"strin"}'), 'unknown type name');
  Check(SchemaIsInvalid('{"type":5}'), 'type must be string or array');
  Check(SchemaIsInvalid('{"type":[]}'), 'type array must not be empty');
  Check(SchemaIsInvalid('{"type":[1]}'), 'type array entries must be strings');
  Check(SchemaIsInvalid('{"type":["string","string"]}'), 'type array must not repeat');
  Check(SchemaIsInvalid('{"properties":[]}'), 'properties must be an object');
  Check(SchemaIsInvalid('{"required":"a"}'), 'required must be an array');
  Check(SchemaIsInvalid('{"minimum":"1"}'), 'minimum must be numeric');
  Check(SchemaIsInvalid('{"minLength":-1}'), 'minLength must not be negative');
  Check(SchemaIsInvalid('{"minLength":1.5}'), 'minLength must be an integer');
  Check(SchemaIsInvalid('{"pattern":"("}'), 'pattern must compile');
  Check(SchemaIsInvalid('{"allOf":[]}'), 'allOf must not be empty');
  Check(SchemaIsInvalid('{"properties":{"a":5}}'), 'property values must be schemas');
  Check(SchemaIsInvalid('{"items":5}'), 'items must be a schema');
  Check(SchemaIsInvalid('{"not":5}'), 'not must be a schema');
  Check(SchemaIsInvalid('5'), 'a schema document must not be a number');
  Check(SchemaIsInvalid('[]'), 'a schema document must not be an array');
  Check(SchemaIsInvalid('"x"'), 'a schema document must not be a string');
  Check(SchemaIsInvalid('{"$ref":5}'), '$ref must be a string');
  Check(SchemaIsInvalid('{"enum":5}'), 'enum must be an array');
  Check(SchemaIsInvalid('{"uniqueItems":"yes"}'), 'uniqueItems must be boolean');
  Check(SchemaIsInvalid('{"multipleOf":0}'), 'multipleOf must be positive');
  Check(SchemaIsInvalid('{"unevaluatedProperties":false}'), 'unevaluatedProperties is unsupported');
  Check(SchemaIsInvalid('{"unevaluatedItems":false}'), 'unevaluatedItems is unsupported');
  Check(SchemaIsInvalid('{"$dynamicRef":"#x"}'), '$dynamicRef is unsupported');
  Check(SchemaIsInvalid('{"dependentRequired":{"a":"b"}}'), 'dependentRequired entries must be arrays');
  Check(SchemaIsInvalid('{"minContains":-1}'), 'minContains must be a non-negative integer');
  Check(SchemaIsInvalid('{"properties":{"a":{"items":{"type":"nope"}}}}'), 'nested errors are found deep inside the schema');
  Check(SchemaIsInvalid('{"$recursiveRef":"#"}', '2019-09'), '$recursiveRef is unsupported in 2019-09');
  Check(SchemaIsInvalid('{"unevaluatedProperties":false}', '2019-09'), 'unevaluatedProperties is unsupported in 2019-09');
  Check(not SchemaIsInvalid('{"unevaluatedProperties":false}', 'draft-07'), 'unevaluatedProperties is just an unknown keyword in draft-07');
  CheckEqualsInt(2, SchemaErrorCount('{"type":"nope","minimum":"x"}'), 'all schema errors are collected');
  CheckEqualsStr('type|/properties/a/type', SchemaErrorInfo('{"properties":{"a":{"type":"nope"}}}'), 'schema errors carry keyword and schema location');
  CheckEqualsStr('items|/items', SchemaErrorInfo('{"items":5}'), 'a bad subschema is reported at its keyword');
  Check(Pos('unknown type', SchemaErrorMessage('{"type":"nope"}')) > 0, 'the exception message explains the problem');
  Check(Pos('"t"', SchemaErrorMessage('{"type":"nope"}')) > 0, 'the exception message names the schema id');
  Check(not EValidationError.InheritsFrom(ESchemaError), 'instance failures and schema errors are distinct exception types');
  Check(ESchemaError.InheritsFrom(EJsonSchemaError) and EValidationError.InheritsFrom(EJsonSchemaError), 'both derive from EJsonSchemaError');
  NotJsonAndIgnoreTests;
  Halt(EndSuite);
end.
