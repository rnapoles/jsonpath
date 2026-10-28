{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program SampleSchemaBasics;

{ Draft selection, programmatic schema registration and return-based error
  handling.

  Build (Free Pascal, from this folder):
    fpc -Mdelphi -Fu../.. -Fu.. SampleSchemaBasics.pas }

{$APPTYPE CONSOLE}

uses
  SysUtils, JsonSchemaErrors, JsonSchemaValidator;

const
  PersonSchema =
    '{"type":"object","required":["name","age"],' +
    '"properties":{"name":{"type":"string","minLength":1},' +
    '"age":{"type":"integer","minimum":0},' +
    '"email":{"type":"string","format":"email"}},' +
    '"additionalProperties":false}';

procedure Show(V: TJsonSchemaValidator; const ASchemaId, AInstance: string);
var
  R: TValidationResult;
  I: Integer;
begin
  WriteLn('instance ', AInstance, ' against "', ASchemaId, '"');
  R := V.ValidateText(AInstance, ASchemaId); { return mode: never raises for invalid instances }
  try
    if R.IsValid then
      WriteLn('  valid')
    else
      for I := 0 to R.Errors.Count - 1 do
        WriteLn('  ', R.Errors[I].Describe);
  finally
    R.Free; { the caller owns the result }
  end;
end;

var
  V: TJsonSchemaValidator;
begin
  V := TJsonSchemaValidator.Create;
  try
    { 1. register schemas programmatically; they are compiled once, right here }
    V.RegisterSchema('person', PersonSchema);
    Show(V, 'person', '{"name":"Ann","age":30,"email":"ann@example.com"}');
    Show(V, 'person', '{"name":"","age":-1,"email":"nope","extra":true}');

    { 2. the draft comes from "$schema"; without it the default draft applies }
    WriteLn;
    WriteLn('default draft: ', V.DefaultDraftName);
    V.RegisterSchema('positive-d4',
      '{"$schema":"http://json-schema.org/draft-04/schema#",' +
      '"type":"number","minimum":0,"exclusiveMinimum":true}');
    Show(V, 'positive-d4', '0');   { draft-04: exclusiveMinimum is a boolean }
    Show(V, 'positive-d4', '0.5');

    V.UseDraft('draft-07');        { configurable default for schemas without $schema }
    V.RegisterSchema('positive-d7', '{"type":"number","exclusiveMinimum":0}');
    WriteLn('default draft is now: ', V.DefaultDraftName);
    Show(V, 'positive-d7', '0');
    Show(V, 'positive-d7', '0.5');

    { 3. unsupported drafts and invalid schemas raise ESchemaError }
    WriteLn;
    try
      V.RegisterSchema('old', '{"$schema":"http://json-schema.org/draft-03/schema#"}');
    except
      on E: ESchemaError do
        WriteLn('schema rejected: ', E.Message);
    end;
  finally
    V.Free;
  end;
end.
