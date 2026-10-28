{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit SchemaTestSupport;

{ Helpers shared by the JSON Schema test programs (on top of TestSupport). }

interface

uses
  SysUtils, Classes, JSONPathJSON, JsonSchemaErrors, JsonSchemaCore, JsonSchemaValidator;

{ A validator in return mode; ADraft is the default draft ('' keeps 2020-12) }
function NewValidator(const ADraft: string = ''): TJsonSchemaValidator;

{ True when AInstanceJson is valid against ASchemaJson }
function SchemaAccepts(const ASchemaJson, AInstanceJson: string;
  const ADraft: string = ''): Boolean;
function SchemaAcceptsNoFormats(const ASchemaJson, AInstanceJson: string): Boolean;
{ "keyword@instance-pointer" of every error, joined with ";" }
function ErrorSummary(const ASchemaJson, AInstanceJson: string;
  const ADraft: string = ''): string;
{ schema pointers of every error, joined with ";" }
function ErrorSchemaLocations(const ASchemaJson, AInstanceJson: string;
  const ADraft: string = ''): string;
{ message of the first error }
function FirstErrorMessage(const ASchemaJson, AInstanceJson: string;
  const ADraft: string = ''): string;

{ True when registering the schema raises ESchemaError }
function SchemaIsInvalid(const ASchemaJson: string; const ADraft: string = ''): Boolean;
{ number of errors carried by the ESchemaError, 0 when the schema is valid }
function SchemaErrorCount(const ASchemaJson: string; const ADraft: string = ''): Integer;
{ "keyword|schema-pointer" of the first schema error, '' when valid }
function SchemaErrorInfo(const ASchemaJson: string; const ADraft: string = ''): string;
function SchemaErrorMessage(const ASchemaJson: string; const ADraft: string = ''): string;

{ file helpers for the filesystem tests }
function TestTempDir: string;
procedure WriteTextFile(const APath, AText: string);
procedure RemoveDirTree(const ADir: string);

implementation

function NewValidator(const ADraft: string): TJsonSchemaValidator;
begin
  Result := TJsonSchemaValidator.Create;
  if ADraft <> '' then
    try
      Result.UseDraft(ADraft);
    except
      Result.Free;
      raise;
    end;
end;

function RunInstance(const ASchemaJson, AInstanceJson, ADraft: string;
  AAssertFormats: Boolean; AMode: Integer): string;
var
  V: TJsonSchemaValidator;
  R: TValidationResult;
  I: Integer;
begin
  Result := '';
  V := NewValidator(ADraft);
  try
    V.AssertFormats := AAssertFormats;
    V.RegisterSchema('t', ASchemaJson);
    R := V.ValidateText(AInstanceJson, 't');
    try
      case AMode of
        0:
          if R.IsValid then Result := 'valid' else Result := 'invalid';
        1:
          for I := 0 to R.Errors.Count - 1 do
          begin
            if I > 0 then
              Result := Result + ';';
            Result := Result + R.Errors[I].Keyword + '@' + R.Errors[I].InstanceLocation;
          end;
        2:
          for I := 0 to R.Errors.Count - 1 do
          begin
            if I > 0 then
              Result := Result + ';';
            Result := Result + R.Errors[I].SchemaLocation;
          end;
        3:
          if R.Errors.Count > 0 then
            Result := R.Errors[0].Message;
      end;
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end;

function SchemaAccepts(const ASchemaJson, AInstanceJson, ADraft: string): Boolean;
begin
  Result := RunInstance(ASchemaJson, AInstanceJson, ADraft, True, 0) = 'valid';
end;

function SchemaAcceptsNoFormats(const ASchemaJson, AInstanceJson: string): Boolean;
begin
  Result := RunInstance(ASchemaJson, AInstanceJson, '', False, 0) = 'valid';
end;

function ErrorSummary(const ASchemaJson, AInstanceJson, ADraft: string): string;
begin
  Result := RunInstance(ASchemaJson, AInstanceJson, ADraft, True, 1);
end;

function ErrorSchemaLocations(const ASchemaJson, AInstanceJson, ADraft: string): string;
begin
  Result := RunInstance(ASchemaJson, AInstanceJson, ADraft, True, 2);
end;

function FirstErrorMessage(const ASchemaJson, AInstanceJson, ADraft: string): string;
begin
  Result := RunInstance(ASchemaJson, AInstanceJson, ADraft, True, 3);
end;

function SchemaIsInvalid(const ASchemaJson, ADraft: string): Boolean;
var
  V: TJsonSchemaValidator;
begin
  Result := False;
  V := NewValidator(ADraft);
  try
    try
      V.RegisterSchema('t', ASchemaJson);
    except
      on ESchemaError do
        Result := True;
    end;
  finally
    V.Free;
  end;
end;

function SchemaErrorCount(const ASchemaJson, ADraft: string): Integer;
var
  V: TJsonSchemaValidator;
begin
  Result := 0;
  V := NewValidator(ADraft);
  try
    try
      V.RegisterSchema('t', ASchemaJson);
    except
      on E: ESchemaError do
        Result := E.Errors.Count;
    end;
  finally
    V.Free;
  end;
end;

function SchemaErrorInfo(const ASchemaJson, ADraft: string): string;
var
  V: TJsonSchemaValidator;
begin
  Result := '';
  V := NewValidator(ADraft);
  try
    try
      V.RegisterSchema('t', ASchemaJson);
    except
      on E: ESchemaError do
        if E.Errors.Count > 0 then
          Result := E.Errors[0].Keyword + '|' + E.Errors[0].SchemaLocation;
    end;
  finally
    V.Free;
  end;
end;

function SchemaErrorMessage(const ASchemaJson, ADraft: string): string;
var
  V: TJsonSchemaValidator;
begin
  Result := '';
  V := NewValidator(ADraft);
  try
    try
      V.RegisterSchema('t', ASchemaJson);
    except
      on E: ESchemaError do
        Result := E.Message;
    end;
  finally
    V.Free;
  end;
end;

function TestTempDir: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    'tmp_schema_tests' + PathDelim;
end;

procedure WriteTextFile(const APath, AText: string);
var
  L: TStringList;
begin
  ForceDirectories(ExtractFilePath(APath));
  L := TStringList.Create;
  try
    L.Text := AText;
    L.SaveToFile(APath);
  finally
    L.Free;
  end;
end;

procedure RemoveDirTree(const ADir: string);
var
  SR: TSearchRec;
  Base: string;
begin
  if not DirectoryExists(ADir) then
    Exit;
  Base := IncludeTrailingPathDelimiter(ADir);
  if FindFirst(Base + '*', faAnyFile, SR) = 0 then
  begin
    try
      repeat
        if (SR.Name <> '.') and (SR.Name <> '..') then
        begin
          if (SR.Attr and faDirectory) <> 0 then
            RemoveDirTree(Base + SR.Name)
          else
            DeleteFile(Base + SR.Name);
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;
  RemoveDir(ADir);
end;

end.
