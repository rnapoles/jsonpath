{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestSchemaCustomTypes;

{$APPTYPE CONSOLE}

uses
  TestSupport, SchemaTestSupport, SysUtils, JSONPathJSON, JsonSchemaCore, JsonSchemaErrors,
  JsonSchemaValidator;

type
  TLimits = class
  public
    function IsShortString(AValue: TJSONValue): Boolean;
    function IsEvenLength(const AText: string): Boolean;
  end;

function TLimits.IsShortString(AValue: TJSONValue): Boolean;
begin
  Result := (AValue.Kind = jkString) and (Length(AValue.StringValue) <= 3);
end;

function TLimits.IsEvenLength(const AText: string): Boolean;
begin
  Result := Length(AText) mod 2 = 0;
end;

function TypeEven(AValue: TJSONValue): Boolean;
begin
  Result := (AValue.Kind = jkNumber) and (Frac(AValue.NumberValue) = 0)
    and (Trunc(AValue.NumberValue) mod 2 = 0);
end;

function TypeNonNegativeInteger(AValue: TJSONValue): Boolean;
begin
  Result := (AValue.Kind = jkNumber) and (Frac(AValue.NumberValue) = 0)
    and (AValue.NumberValue >= 0);
end;

function FormatUpperCase(const AText: string): Boolean;
begin
  Result := AText = UpperCase(AText);
end;

function Accepts(V: TJsonSchemaValidator; const ASchema, AInstance: string): Boolean;
var
  S, I: TJSONValue;
  R: TValidationResult;
begin
  S := ParseJSON(ASchema);
  try
    I := ParseJSON(AInstance);
    try
      R := V.ValidateWithSchema(I, S);
      try
        Result := R.IsValid;
      finally
        R.Free;
      end;
    finally
      I.Free;
    end;
  finally
    S.Free;
  end;
end;

function IsInvalidSchema(V: TJsonSchemaValidator; const ASchema: string): Boolean;
var
  S, I: TJSONValue;
  R: TValidationResult;
begin
  Result := False;
  S := ParseJSON(ASchema);
  try
    I := ParseJSON('null');
    try
      try
        R := V.ValidateWithSchema(I, S);
        R.Free;
      except
        on ESchemaError do
          Result := True;
      end;
    finally
      I.Free;
    end;
  finally
    S.Free;
  end;
end;

function RegistrationRaises(V: TJsonSchemaValidator; const AName: string; AOverride: Boolean): Boolean;
begin
  Result := False;
  try
    V.RegisterType(AName, TypeEven, AOverride);
  except
    on ESchemaRegistrationError do
      Result := True;
  end;
end;

var
  V: TJsonSchemaValidator;
  L: TLimits;
begin
  BeginSuite('Schema: custom types and formats');
  L := TLimits.Create;
  V := NewValidator;
  try
    Check(IsInvalidSchema(V, '{"type":"even"}'), 'an unregistered type is a schema error');
    V.RegisterType('even', TypeEven);
    Check(not IsInvalidSchema(V, '{"type":"even"}'), 'a registered type is accepted by the schema');
    Check(Accepts(V, '{"type":"even"}', '4'), 'custom type accepts matching values');
    Check(not Accepts(V, '{"type":"even"}', '3'), 'custom type rejects other values');
    Check(not Accepts(V, '{"type":"even"}', '"x"'), 'custom type rejects other kinds');
    Check(Accepts(V, '{"type":["even","string"]}', '"x"'), 'custom types combine with built-in ones');
    Check(Accepts(V, '{"properties":{"n":{"type":"even"}}}', '{"n":2}'), 'custom types work in subschemas');
    Check(not Accepts(V, '{"items":{"type":"even"}}', '[2,3]'), 'custom types work in items');

    Check(RegistrationRaises(V, 'even', False), 'registering an existing custom type raises');
    Check(RegistrationRaises(V, 'integer', False), 'overriding a built-in type needs AllowOverride');
    Check(not RegistrationRaises(V, 'even', True), 'AllowOverride replaces a custom type');

    V.RegisterType('integer', TypeNonNegativeInteger, True);
    Check(not Accepts(V, '{"type":"integer"}', '-1'), 'an overridden built-in type changes behaviour');
    Check(Accepts(V, '{"type":"integer"}', '3'), 'an overridden built-in type still accepts valid values');

    V.RegisterType('short', L.IsShortString);
    Check(Accepts(V, '{"type":"short"}', '"abc"'), 'method based type checkers work');
    Check(not Accepts(V, '{"type":"short"}', '"abcd"'), 'method based type checkers reject');

    Check(V.Types.Unregister('even'), 'types can be unregistered');
    Check(IsInvalidSchema(V, '{"type":"even"}'), 'an unregistered type is rejected again');

    { formats }
    V.RegisterFormat('upper', FormatUpperCase);
    Check(Accepts(V, '{"format":"upper"}', '"ABC"'), 'custom format accepts');
    Check(not Accepts(V, '{"format":"upper"}', '"abc"'), 'custom format rejects');
    V.RegisterFormat('even-length', L.IsEvenLength);
    Check(not Accepts(V, '{"format":"even-length"}', '"abc"'), 'method based format checkers work');
    Check(V.Formats.IsRegistered('email'), 'built-in formats are listed in the registry');
  finally
    V.Free;
    L.Free;
  end;
  Halt(EndSuite);
end.
