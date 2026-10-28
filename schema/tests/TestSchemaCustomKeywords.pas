{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestSchemaCustomKeywords;

{$APPTYPE CONSOLE}

uses
  TestSupport, SchemaTestSupport, SysUtils, JSONPathJSON, JsonSchemaCore, JsonSchemaErrors,
  JsonSchemaKeywords, JsonSchemaValidator;

type
  TCounter = class
  public
    Calls: Integer;
    function Seen(Ctx: TKeywordContext): Boolean;
  end;

function TCounter.Seen(Ctx: TKeywordContext): Boolean;
begin
  Inc(Calls);
  Result := True;
end;

function KwDivisibleBy(Ctx: TKeywordContext): Boolean;
begin
  Result := True;
  if Ctx.Instance.Kind <> jkNumber then
    Exit;
  Result := Frac(Ctx.Instance.NumberValue / Ctx.KeywordValue.NumberValue) = 0;
  if not Result then
    Ctx.AddError('not divisible by ' + JSONToText(Ctx.KeywordValue));
end;

procedure CheckDivisor(Ctx: TCompileContext);
begin
  if (Ctx.KeywordValue.Kind <> jkNumber) or (Ctx.KeywordValue.NumberValue = 0) then
    Ctx.Error('"divisibleBy" must be a non-zero number');
end;

function KwStartsWith(Ctx: TKeywordContext): Boolean;
var
  S, P: string;
  CaseSensitive: Boolean;
  Opt: TJSONValue;
begin
  Result := True;
  if Ctx.Instance.Kind <> jkString then
    Exit;
  CaseSensitive := True;
  if Ctx.Config <> nil then
  begin
    Opt := Ctx.Config.FindMember('caseSensitive');
    if (Opt <> nil) and (Opt.Kind = jkBoolean) then
      CaseSensitive := Opt.BoolValue;
  end;
  S := Ctx.Instance.StringValue;
  P := Ctx.KeywordValue.StringValue;
  if not CaseSensitive then
  begin
    S := LowerCase(S);
    P := LowerCase(P);
  end;
  Result := Copy(S, 1, Length(P)) = P;
end;

function KwEveryItem(Ctx: TKeywordContext): Boolean;
var
  I: Integer;
begin
  Result := True;
  if Ctx.Instance.Kind <> jkArray then
    Exit;
  for I := 0 to Ctx.Instance.Count - 1 do
    if not Ctx.ValidateSubschema(Ctx.KeywordValue, Ctx.Instance[I], '', JsonPointerIndexStep(I)) then
      Result := False;
end;

function KwAlwaysFail(Ctx: TKeywordContext): Boolean;
begin
  Result := False;
end;

function ErrorsOf(V: TJsonSchemaValidator; const ASchema, AInstance: string): string;
var
  S, I: TJSONValue;
  R: TValidationResult;
  K: Integer;
begin
  Result := '';
  S := ParseJSON(ASchema);
  try
    I := ParseJSON(AInstance);
    try
      R := V.ValidateWithSchema(I, S);
      try
        for K := 0 to R.Errors.Count - 1 do
        begin
          if K > 0 then
            Result := Result + ';';
          Result := Result + R.Errors[K].Keyword + '@' + R.Errors[K].InstanceLocation + ':' +
            R.Errors[K].Message;
        end;
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

function Accepts(V: TJsonSchemaValidator; const ASchema, AInstance: string): Boolean;
begin
  Result := ErrorsOf(V, ASchema, AInstance) = '';
end;

function IsInvalidSchema(V: TJsonSchemaValidator; const ASchema: string): Boolean;
begin
  Result := False;
  try
    ErrorsOf(V, ASchema, 'null');
  except
    on ESchemaError do
      Result := True;
  end;
end;

function RegisterRaises(V: TJsonSchemaValidator; const AName: string; AOverride: Boolean): Boolean;
begin
  Result := False;
  try
    V.RegisterKeyword(AName, KwAlwaysFail, '', nil, AOverride);
  except
    on ESchemaRegistrationError do
      Result := True;
  end;
end;

var
  V, V2: TJsonSchemaValidator;
  C: TCounter;
  Raised: Boolean;
begin
  BeginSuite('Schema: custom keywords and validators');
  V := NewValidator;
  C := TCounter.Create;
  try
    { parameterised validator }
    V.RegisterKeyword('divisibleBy', KwDivisibleBy, '', CheckDivisor);
    Check(Accepts(V, '{"divisibleBy":3}', '9'), 'the keyword value is the validator parameter (accepts)');
    Check(not Accepts(V, '{"divisibleBy":3}', '10'), 'the keyword value is the validator parameter (rejects)');
    Check(Accepts(V, '{"divisibleBy":3}', '"text"'), 'validators decide which kinds they apply to');
    CheckEqualsStr('divisibleBy@:not divisible by 3', ErrorsOf(V, '{"divisibleBy":3}', '10'),
      'custom errors carry the keyword and message');
    Check(IsInvalidSchema(V, '{"divisibleBy":0}'), 'the checker rejects an invalid parameter');
    Check(IsInvalidSchema(V, '{"divisibleBy":"x"}'), 'the checker rejects a wrongly typed parameter');
    Check(Accepts(V, '{"properties":{"n":{"divisibleBy":2}}}', '{"n":4}'), 'custom keywords work in subschemas');
    Check(not Accepts(V, '{"properties":{"n":{"divisibleBy":2}}}', '{"n":5}'), 'custom keywords fail in subschemas');
    CheckEqualsStr('divisibleBy@/n:not divisible by 2', ErrorsOf(V, '{"properties":{"n":{"divisibleBy":2}}}', '{"n":5}'),
      'instance locations are tracked for custom keywords');

    { registration-time configuration }
    V.RegisterKeyword('startsWith', KwStartsWith, '{"caseSensitive":false}');
    V.RegisterKeyword('startsWithCS', KwStartsWith);
    Check(Accepts(V, '{"startsWith":"ab"}', '"ABc"'), 'configuration reaches the validator (case-insensitive)');
    Check(not Accepts(V, '{"startsWithCS":"ab"}', '"ABc"'), 'without configuration the default applies');
    Check(Accepts(V, '{"startsWithCS":"ab"}', '"abc"'), 'default behaviour accepts exact prefixes');
    Raised := False;
    try
      V.RegisterKeyword('badConfig', KwAlwaysFail, '{not json');
    except
      on ESchemaRegistrationError do
        Raised := True;
    end;
    Check(Raised, 'invalid configuration JSON raises ESchemaRegistrationError');

    { keywords that contain subschemas }
    V.RegisterKeyword('everyItem', KwEveryItem, '', CheckSchema);
    Check(Accepts(V, '{"everyItem":{"type":"integer"}}', '[1,2]'), 'custom applicators validate subschemas');
    CheckEqualsStr('type@/1:value is not of type integer', ErrorsOf(V, '{"everyItem":{"type":"integer"}}', '[1,"a"]'),
      'errors of custom applicators keep their instance location');
    Check(IsInvalidSchema(V, '{"everyItem":{"type":"nope"}}'), 'subschemas of custom keywords are compiled and checked');

    { generic message when the validator returns False silently }
    V.RegisterKeyword('alwaysFail', KwAlwaysFail);
    Check(Pos('alwaysFail', ErrorsOf(V, '{"alwaysFail":true}', '1')) > 0, 'a silent failure gets a generic message naming the keyword');

    { method validators }
    V.RegisterKeyword('seen', C.Seen);
    Accepts(V, '{"properties":{"a":{"seen":true},"b":{"seen":true}}}', '{"a":1,"b":2}');
    CheckEqualsInt(2, C.Calls, 'method based validators are called');

    { registration policy }
    Check(RegisterRaises(V, 'divisibleBy', False), 'a custom keyword cannot be registered twice');
    Check(RegisterRaises(V, 'minimum', False), 'built-in keywords need AllowOverride');
    Check(RegisterRaises(V, 'type', False), 'built-in keywords need AllowOverride (type)');
    Check(not RegisterRaises(V, 'divisibleBy', True), 'AllowOverride replaces a custom keyword');

    { unregistering }
    Check(V.Keywords.Unregister('startsWithCS'), 'custom keywords can be unregistered');
    Check(Accepts(V, '{"startsWithCS":"zz"}', '"abc"'), 'an unregistered keyword is an ordinary unknown keyword');
  finally
    V.Free;
    C.Free;
  end;

  { overriding a built-in keyword affects every draft }
  V2 := NewValidator;
  try
    V2.RegisterKeyword('minimum', KwAlwaysFail, '', nil, True);
    Check(not Accepts(V2, '{"minimum":1}', '5'), 'a validator-level override wins (2020-12)');
    Check(not Accepts(V2, '{"$schema":"http://json-schema.org/draft-04/schema#","minimum":1}', '5'),
      'a validator-level override wins in every draft (draft-04)');
  finally
    V2.Free;
  end;

  { draft-specific extension }
  V := NewValidator;
  try
    V.Drafts.FindByName('draft-07').Keywords.RegisterKeyword('onlyD7', KwAlwaysFail);
    Check(not Accepts(V, '{"$schema":"http://json-schema.org/draft-07/schema#","onlyD7":true}', '1'),
      'a draft-level keyword is active in that draft');
    Check(Accepts(V, '{"onlyD7":true}', '1'), 'a draft-level keyword is unknown to other drafts');
  finally
    V.Free;
  end;
  Halt(EndSuite);
end.
