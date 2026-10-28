{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestSchemaFilesystem;

{$APPTYPE CONSOLE}

uses
  TestSupport, SchemaTestSupport, SysUtils, Classes, JSONPathJSON, JsonSchemaCore,
  JsonSchemaErrors, JsonSchemaValidator;

const
  AddressSchema =
    '{"$id":"https://example.com/schemas/address.json","type":"object","required":["city"]}';
  PersonSchema =
    '{"$id":"https://example.com/schemas/person.json","type":"object",' +
    '"properties":{"home":{"$ref":"address.json"}}}';

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

procedure WriteSchemaTree(const ARoot: string);
begin
  WriteTextFile(ARoot + 'address.schema.json', AddressSchema);
  WriteTextFile(ARoot + 'person.schema.json', PersonSchema);
  WriteTextFile(ARoot + 'sub' + PathDelim + 'note.schema.json', '{"type":"string"}');
  WriteTextFile(ARoot + 'readme.txt', 'not a schema');
  WriteTextFile(ARoot + 'plain.json', '{"type":"integer"}');
end;

function LoadFileRaises(V: TJsonSchemaValidator; const AFile: string; out AName: string): Integer;
begin
  { 0 = no error, 1 = load error, 2 = schema error, 3 = registration error }
  Result := 0;
  AName := '';
  try
    V.LoadSchemaFile(AFile);
  except
    on E: ESchemaLoadError do
    begin
      Result := 1;
      AName := E.FileName;
    end;
    on ESchemaError do
      Result := 2;
    on ESchemaRegistrationError do
      Result := 3;
  end;
end;

function LoadDirRaises(V: TJsonSchemaValidator; const ADir: string; ARecursive: Boolean): Integer;
begin
  Result := 0;
  try
    V.LoadSchemaDirectory(ADir, ARecursive);
  except
    on ESchemaLoadError do
      Result := 1;
    on ESchemaError do
      Result := 2;
    on ESchemaRegistrationError do
      Result := 3;
  end;
end;

var
  Tmp, FileName: string;
  V: TJsonSchemaValidator;
  Loaded: Integer;
begin
  BeginSuite('Schema: loading files and directories');
  Tmp := TestTempDir;
  RemoveDirTree(Tmp);
  try
    { ---- single files ---- }
    WriteTextFile(Tmp + 'plain.json', '{"type":"integer"}');
    WriteTextFile(Tmp + 'withid.json', AddressSchema);
    WriteTextFile(Tmp + 'broken.json', '{"type": ');
    WriteTextFile(Tmp + 'invalid.json', '{"type":"nope"}');
    WriteTextFile(Tmp + 'bom.json', #$EF#$BB#$BF + '{"type":"string"}');

    V := NewValidator;
    try
      CheckEqualsStr('plain', V.LoadSchemaFile(Tmp + 'plain.json'), 'the id defaults to the file name without extension');
      Check(Valid(V, '1', 'plain') and not Valid(V, '"x"', 'plain'), 'a loaded file validates');
      CheckEqualsStr('custom', V.LoadSchemaFile(Tmp + 'plain.json', 'custom'), 'an explicit id wins');
      CheckEqualsStr('https://example.com/schemas/address.json', V.LoadSchemaFile(Tmp + 'withid.json'),
        'the schema''s own $id is used when present');
      CheckEqualsStr('bom', V.LoadSchemaFile(Tmp + 'bom.json'), 'a UTF-8 byte order mark is ignored');
      Check(Valid(V, '"x"', 'bom'), 'a schema with a byte order mark validates');

      CheckEqualsInt(1, LoadFileRaises(V, Tmp + 'missing.json', FileName), 'a missing file raises ESchemaLoadError');
      CheckEqualsStr(Tmp + 'missing.json', FileName, 'ESchemaLoadError carries the file name');
      CheckEqualsInt(1, LoadFileRaises(V, Tmp + 'broken.json', FileName), 'malformed JSON raises ESchemaLoadError');
      CheckEqualsInt(2, LoadFileRaises(V, Tmp + 'invalid.json', FileName), 'an invalid schema file raises ESchemaError');
      CheckEqualsInt(3, LoadFileRaises(V, Tmp + 'plain.json', FileName), 'a duplicate id raises ESchemaRegistrationError');
      CheckEqualsInt(1, LoadFileRaises(V, Tmp, FileName), 'a directory is not a schema file');
    finally
      V.Free;
    end;
    RemoveDirTree(Tmp);

    { ---- directories ---- }
    WriteSchemaTree(Tmp + 'tree' + PathDelim);
    V := NewValidator;
    try
      V.SchemaFileExtensions := '.schema.json';
      Loaded := V.LoadSchemaDirectory(Tmp + 'tree');
      CheckEqualsInt(3, Loaded, 'recursive loading finds files in sub directories');
      Check(V.HasSchema('https://example.com/schemas/person.json'), 'files with $id are registered under it');
      Check(V.HasSchema('note.schema'), 'files without $id use the file name');
      Check(not V.HasSchema('plain'), 'files with other extensions are ignored');
      Check(Valid(V, '{"home":{"city":"x"}}', 'https://example.com/schemas/person.json'),
        'references between loaded files resolve through their $id');
      Check(not Valid(V, '{"home":{}}', 'https://example.com/schemas/person.json'),
        'references between loaded files are enforced');
    finally
      V.Free;
    end;

    V := NewValidator;
    try
      V.SchemaFileExtensions := '.schema.json';
      CheckEqualsInt(2, V.LoadSchemaDirectory(Tmp + 'tree', False), 'non-recursive loading skips sub directories');
    finally
      V.Free;
    end;

    V := NewValidator;
    try
      CheckEqualsInt(3, V.LoadSchemaDirectory(Tmp + 'tree', False), 'the default extension is .json');
      V.SchemaFileExtensions := '.schema.json; .txt';
      CheckEqualsStr('.schema.json; .txt', V.SchemaFileExtensions, 'extensions are configurable');
    finally
      V.Free;
    end;

    V := NewValidator;
    try
      CheckEqualsInt(1, LoadDirRaises(V, Tmp + 'does-not-exist', True), 'a missing directory raises ESchemaLoadError');
    finally
      V.Free;
    end;
    RemoveDirTree(Tmp);

    { ---- error policies for directories ---- }
    WriteTextFile(Tmp + 'bad' + PathDelim + 'a-good.json', '{"type":"integer"}');
    WriteTextFile(Tmp + 'bad' + PathDelim + 'b-malformed.json', '{oops');
    WriteTextFile(Tmp + 'bad' + PathDelim + 'c-invalid.json', '{"minimum":"x"}');
    WriteTextFile(Tmp + 'bad' + PathDelim + 'd-good.json', '{"type":"string"}');

    V := NewValidator;
    try
      CheckEqualsInt(1, LoadDirRaises(V, Tmp + 'bad', True), 'lpRaise stops at the first bad file');
      Check(V.HasSchema('a-good'), 'files loaded before the failure stay registered');
      Check(not V.HasSchema('d-good'), 'files after the failure are not loaded');
    finally
      V.Free;
    end;

    V := NewValidator;
    try
      V.LoadErrorPolicy := lpCollect;
      Loaded := V.LoadSchemaDirectory(Tmp + 'bad');
      CheckEqualsInt(2, Loaded, 'lpCollect loads every good file');
      CheckEqualsInt(2, V.LoadErrors.Count, 'lpCollect records every bad file');
      Check(Pos('b-malformed.json', V.LoadErrors[0].SchemaLocation) > 0, 'a recorded error names its file');
      Check(Pos('c-invalid.json', V.LoadErrors[1].SchemaLocation) > 0, 'recorded errors keep the directory order');
      Check(V.HasSchema('d-good'), 'good files after a bad one are loaded');
      Loaded := V.LoadSchemaDirectory(Tmp + 'bad');
      CheckEqualsInt(0, Loaded, 'a second pass loads nothing: every good file is now a duplicate');
      CheckEqualsInt(4, V.LoadErrors.Count, 'duplicates are collected next to the bad files');
      V.LoadSchemaDirectory(Tmp + 'bad');
      CheckEqualsInt(4, V.LoadErrors.Count, 'LoadErrors is reset on every call');
    finally
      V.Free;
    end;
  finally
    RemoveDirTree(Tmp);
  end;
  Halt(EndSuite);
end.
