{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program SampleSchemaExtensions;

{ Custom types, a parameterised validator, a validator with registration-time
  configuration and a custom format.

  Build (Free Pascal, from this folder):
    fpc -Mdelphi -Fu../.. -Fu.. SampleSchemaExtensions.pas }

{$APPTYPE CONSOLE}

uses
  SysUtils, JSONPathJSON, JsonSchemaErrors, JsonSchemaCore, JsonSchemaValidator;

{ a custom TYPE: usable as  "type": "even" }
function TypeEven(AValue: TJSONValue): Boolean;
begin
  Result := (AValue.Kind = jkNumber) and (Frac(AValue.NumberValue) = 0)
    and (Trunc(AValue.NumberValue) mod 2 = 0);
end;

{ a custom KEYWORD with a parameter taken from the schema: "divisibleBy": 3 }
function KwDivisibleBy(Ctx: TKeywordContext): Boolean;
begin
  Result := True;
  if Ctx.Instance.Kind <> jkNumber then
    Exit; { not applicable to other kinds }
  Result := Frac(Ctx.Instance.NumberValue / Ctx.KeywordValue.NumberValue) = 0;
  if not Result then
    Ctx.AddError('not divisible by ' + JSONToText(Ctx.KeywordValue));
end;

{ validates the keyword's value when the schema is compiled }
procedure CheckDivisor(Ctx: TCompileContext);
begin
  if (Ctx.KeywordValue.Kind <> jkNumber) or (Ctx.KeywordValue.NumberValue = 0) then
    Ctx.Error('"divisibleBy" must be a non-zero number');
end;

{ a keyword that reads configuration given at registration time }
function KwStartsWith(Ctx: TKeywordContext): Boolean;
var
  Text, Prefix: string;
  Opt: TJSONValue;
begin
  Result := True;
  if Ctx.Instance.Kind <> jkString then
    Exit;
  Text := Ctx.Instance.StringValue;
  Prefix := Ctx.KeywordValue.StringValue;
  Opt := nil;
  if Ctx.Config <> nil then
    Opt := Ctx.Config.FindMember('caseSensitive');
  if (Opt <> nil) and (Opt.Kind = jkBoolean) and not Opt.BoolValue then
  begin
    Text := LowerCase(Text);
    Prefix := LowerCase(Prefix);
  end;
  Result := Copy(Text, 1, Length(Prefix)) = Prefix;
end;

{ a custom FORMAT }
function FormatSku(const AText: string): Boolean;
begin
  Result := (Length(AText) = 6) and (Copy(AText, 1, 3) = 'SKU');
end;

procedure Show(V: TJsonSchemaValidator; const AInstance: string);
var
  R: TValidationResult;
begin
  R := V.ValidateText(AInstance, 'demo');
  try
    if R.IsValid then
      WriteLn(AInstance, ' -> valid')
    else
      WriteLn(AInstance, ' -> ', R.ErrorText);
  finally
    R.Free;
  end;
end;

var
  V: TJsonSchemaValidator;
begin
  V := TJsonSchemaValidator.Create;
  try
    V.RegisterType('even', TypeEven);
    V.RegisterKeyword('divisibleBy', KwDivisibleBy, '', CheckDivisor);
    { the third argument is configuration handed to the validator as Ctx.Config }
    V.RegisterKeyword('startsWith', KwStartsWith, '{"caseSensitive":false}');
    V.RegisterFormat('sku', FormatSku);

    V.RegisterSchema('demo',
      '{"type":"object","properties":{' +
      '"count":{"type":"even"},' +
      '"batch":{"type":"integer","divisibleBy":3},' +
      '"code":{"startsWith":"ab"},' +
      '"sku":{"type":"string","format":"sku"}}}');

    Show(V, '{"count":4,"batch":9,"code":"ABC","sku":"SKU123"}');
    Show(V, '{"count":3,"batch":10,"code":"xyz","sku":"nope"}');

    { registration policy: built-in names need AllowOverride }
    try
      V.RegisterType('integer', TypeEven);
    except
      on E: ESchemaRegistrationError do
        WriteLn('policy: ', E.Message);
    end;
    V.RegisterType('integer', TypeEven, True);
    WriteLn('after override, "integer" means even integers');
  finally
    V.Free;
  end;
end.
