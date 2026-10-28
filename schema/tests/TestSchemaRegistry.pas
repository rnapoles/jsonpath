{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestSchemaRegistry;

{$APPTYPE CONSOLE}

uses
  TestSupport, SchemaTestSupport, SysUtils, JSONPathJSON, JsonSchemaCore, JsonSchemaErrors,
  JsonSchemaValidator;

function Valid(V: TJsonSchemaValidator; const AInstance, AId: string): Boolean;
var
  R: TValidationResult;
begin
  R := V.ValidateText(AInstance, AId);
  try
    Result := R.IsValid;
  finally
    R.Free;
  end;
end;

function RaisesRegistration(V: TJsonSchemaValidator; const AId, AJson: string): Boolean;
begin
  Result := False;
  try
    V.RegisterSchema(AId, AJson);
  except
    on ESchemaRegistrationError do
      Result := True;
  end;
end;

var
  V: TJsonSchemaValidator;
  Doc: TJSONValue;
  Raised: Boolean;
begin
  BeginSuite('Schema: registration and retrieval');
  V := NewValidator;
  try
    CheckEqualsStr('a', V.RegisterSchema('a', '{"type":"integer"}'), 'RegisterSchema returns the id');
    Check(V.HasSchema('a'), 'HasSchema finds registered schemas');
    Check(not V.HasSchema('zzz'), 'HasSchema is False for unknown ids');
    CheckEqualsInt(1, V.SchemaCount, 'SchemaCount');
    CheckEqualsStr('a', V.SchemaIdAt(0), 'SchemaIdAt');
    Check(V.GetSchema('a').Kind = jkObject, 'GetSchema returns the schema document');
    Check(V.GetSchema('a') = V.GetSchema('a'), 'the same compiled schema is reused');
    Check(Valid(V, '1', 'a') and not Valid(V, '"x"', 'a'), 'registered schemas validate');

    Check(RaisesRegistration(V, 'a', '{"type":"string"}'), 'duplicate ids raise by default (dpRaise)');
    CheckEqualsInt(1, V.SchemaCount, 'a rejected duplicate does not change the registry');
    Check(Valid(V, '1', 'a'), 'a rejected duplicate keeps the original schema');

    V.DuplicatePolicy := dpReplace;
    V.RegisterSchema('a', '{"type":"string"}');
    Check(Valid(V, '"x"', 'a') and not Valid(V, '1', 'a'), 'dpReplace replaces the schema');
    CheckEqualsInt(1, V.SchemaCount, 'dpReplace keeps one entry');

    V.DuplicatePolicy := dpSkip;
    V.RegisterSchema('a', '{"type":"integer"}');
    Check(Valid(V, '"x"', 'a'), 'dpSkip keeps the existing schema');
    V.DuplicatePolicy := dpRaise;

    Check(V.UnregisterSchema('a'), 'UnregisterSchema removes a schema');
    Check(not V.UnregisterSchema('a'), 'UnregisterSchema reports unknown ids');
    Check(not V.HasSchema('a'), 'the schema is gone');
    Raised := False;
    try
      V.GetSchema('a');
    except
      on ESchemaRegistrationError do
        Raised := True;
    end;
    Check(Raised, 'GetSchema raises for unknown ids');

    CheckEqualsStr('http://example.com/s.json',
      V.RegisterSchema('', '{"$id":"http://example.com/s.json","type":"integer"}'),
      'an empty id falls back to the schema''s $id');
    Check(RaisesRegistration(V, '', '{}'), 'a schema without any id is rejected');

    Doc := ParseJSON('{"type":"boolean"}');
    V.RegisterSchema('doc', Doc);
    Check(Valid(V, 'true', 'doc'), 'registering a TJSONValue transfers ownership to the validator');

    { references between registered schemas, in any order }
    V.RegisterSchema('person', '{"type":"object","properties":{"home":{"$ref":"address"}}}');
    Raised := False;
    try
      Valid(V, '{"home":{"city":"x"}}', 'person');
    except
      on ESchemaError do
        Raised := True;
    end;
    Check(Raised, 'an unresolved reference raises ESchemaError when it is used');
    V.RegisterSchema('address', '{"type":"object","required":["city"]}');
    Check(Valid(V, '{"home":{"city":"x"}}', 'person'), 'references resolve once the target is registered');
    Check(not Valid(V, '{"home":{}}', 'person'), 'resolved references validate');
  finally
    V.Free;
  end;
  Halt(EndSuite);
end.
