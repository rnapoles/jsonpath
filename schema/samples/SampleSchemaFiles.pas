{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program SampleSchemaFiles;

{ Loading schemas from a directory, cross-file $ref resolution and the load
  error policy.

  Build (Free Pascal, from this folder):
    fpc -Mdelphi -Fu../.. -Fu.. SampleSchemaFiles.pas
  Run from this folder:  ./SampleSchemaFiles [schema-directory] }

{$APPTYPE CONSOLE}

uses
  SysUtils, JsonSchemaErrors, JsonSchemaCore, JsonSchemaValidator;

procedure Show(V: TJsonSchemaValidator; const AInstance: string);
var
  R: TValidationResult;
begin
  R := V.ValidateText(AInstance, 'https://example.com/schemas/person.json');
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
  Dir: string;
  I, Loaded: Integer;
begin
  Dir := ParamStr(1);
  if Dir = '' then
    Dir := 'schemas';
  V := TJsonSchemaValidator.Create;
  try
    V.SchemaFileExtensions := '.schema.json'; { ignore everything else }
    V.LoadErrorPolicy := lpCollect;           { skip bad files, record them }
    try
      Loaded := V.LoadSchemaDirectory(Dir, True);
    except
      on E: ESchemaLoadError do
      begin
        WriteLn('cannot load schemas: ', E.Message);
        Exit;
      end;
    end;
    WriteLn('loaded ', Loaded, ' schema(s):');
    for I := 0 to V.SchemaCount - 1 do
      WriteLn('  ', V.SchemaIdAt(I));
    for I := 0 to V.LoadErrors.Count - 1 do
      WriteLn('skipped: ', V.LoadErrors[I].Message);
    WriteLn;

    { person.json references address.json: resolved through the $id values }
    Show(V, '{"name":"Ann","home":{"street":"1 Main St","city":"Oslo","zip":"12345"}}');
    Show(V, '{"name":"Bob","home":{"street":"","city":"Oslo","zip":"abc"}}');
    Show(V, '{"name":"Cy"}');
  finally
    V.Free;
  end;
end.
