{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit JsonSchemaLoader;

{ Reading schema files and listing schema directories.

  Pure file I/O: this unit knows nothing about validation. Every failure is
  reported as ESchemaLoadError (carrying the file name): missing or
  unreadable file, missing directory, malformed JSON. Text files are read as
  UTF-8; a UTF-8 byte order mark is ignored. }

interface

uses
  SysUtils, Classes, JSONPathJSON, JsonSchemaErrors;

type
  TSchemaFileLoader = class
  private
    FExtensions: string;
    function ExtensionList: TStringArray;
    function MatchesExtension(const AFileName: string; const AExts: TStringArray): Boolean;
    procedure Scan(const ADir: string; ARecursive: Boolean; const AExts: TStringArray;
      AFiles: TStringList);
  public
    constructor Create;
    { Reads and parses a JSON file. The caller owns the result. }
    function ReadJson(const AFileName: string): TJSONValue;
    function ReadText(const AFileName: string): string;
    { Lists matching files (sorted, full paths). The caller frees the list. }
    function ListFiles(const ADir: string; ARecursive: Boolean): TStringList;
    { Accepted file name endings separated by ";" or ",", compared
      case-insensitively, e.g. '.json;.schema.json'. Default: '.json' }
    property Extensions: string read FExtensions write FExtensions;
  end;

implementation

constructor TSchemaFileLoader.Create;
begin
  inherited Create;
  FExtensions := '.json';
end;

function TSchemaFileLoader.ReadText(const AFileName: string): string;
var
  FS: TFileStream;
  Size: Integer;
{$IFNDEF FPC}
  Offset: Integer;
  Bytes: TBytes;
{$ENDIF}
begin
  Result := '';
  if not FileExists(AFileName) then
    raise ESchemaLoadError.CreateForFile(AFileName, 'file not found');
  try
    FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
    try
      Size := Integer(FS.Size);
{$IFDEF FPC}
      SetLength(Result, Size);
      if Size > 0 then
        FS.ReadBuffer(Result[1], Size);
      if (Length(Result) >= 3) and (Result[1] = #$EF) and (Result[2] = #$BB)
        and (Result[3] = #$BF) then
        Delete(Result, 1, 3);
{$ELSE}
      SetLength(Bytes, Size);
      if Size > 0 then
        FS.ReadBuffer(Bytes[0], Size);
      Offset := 0;
      if (Size >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
        Offset := 3;
      Result := TEncoding.UTF8.GetString(Bytes, Offset, Size - Offset);
{$ENDIF}
    finally
      FS.Free;
    end;
  except
    on ESchemaLoadError do
      raise;
    on E: Exception do
      raise ESchemaLoadError.CreateForFile(AFileName, 'cannot read file: ' + E.Message);
  end;
end;

function TSchemaFileLoader.ReadJson(const AFileName: string): TJSONValue;
var
  Text: string;
begin
  Text := ReadText(AFileName);
  try
    Result := ParseJSON(Text);
  except
    on E: EJSONPathJSONError do
      raise ESchemaLoadError.CreateForFile(AFileName, 'malformed JSON: ' + E.Message);
  end;
end;

function TSchemaFileLoader.ExtensionList: TStringArray;
var
  I, Count: Integer;
  Cur: string;
  C: Char;
begin
  Count := 0;
  SetLength(Result, Length(FExtensions) + 1);
  Cur := '';
  for I := 1 to Length(FExtensions) + 1 do
  begin
    if I <= Length(FExtensions) then
      C := FExtensions[I]
    else
      C := ';';
    if (C = ';') or (C = ',') then
    begin
      Cur := Trim(Cur);
      if Cur <> '' then
      begin
        Result[Count] := LowerCase(Cur);
        Inc(Count);
      end;
      Cur := '';
    end
    else
      Cur := Cur + C;
  end;
  SetLength(Result, Count);
end;

function TSchemaFileLoader.MatchesExtension(const AFileName: string;
  const AExts: TStringArray): Boolean;
var
  I: Integer;
  Lower: string;
begin
  Result := False;
  Lower := LowerCase(AFileName);
  for I := 0 to Length(AExts) - 1 do
    if (Length(Lower) >= Length(AExts[I]))
      and (Copy(Lower, Length(Lower) - Length(AExts[I]) + 1, Length(AExts[I])) = AExts[I]) then
    begin
      Result := True;
      Exit;
    end;
end;

procedure TSchemaFileLoader.Scan(const ADir: string; ARecursive: Boolean;
  const AExts: TStringArray; AFiles: TStringList);
var
  SR: TSearchRec;
  Base: string;
begin
  Base := IncludeTrailingPathDelimiter(ADir);
  if FindFirst(Base + '*', faAnyFile, SR) = 0 then
  begin
    try
      repeat
        if (SR.Name <> '.') and (SR.Name <> '..') then
        begin
          if (SR.Attr and faDirectory) <> 0 then
          begin
            if ARecursive then
              Scan(Base + SR.Name, ARecursive, AExts, AFiles);
          end
          else if MatchesExtension(SR.Name, AExts) then
            AFiles.Add(Base + SR.Name);
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;
end;

function TSchemaFileLoader.ListFiles(const ADir: string; ARecursive: Boolean): TStringList;
begin
  if not DirectoryExists(ADir) then
    raise ESchemaLoadError.CreateForFile(ADir, 'directory not found');
  Result := TStringList.Create;
  try
    Scan(ADir, ARecursive, ExtensionList, Result);
    Result.Sort;
  except
    Result.Free;
    raise;
  end;
end;

end.
