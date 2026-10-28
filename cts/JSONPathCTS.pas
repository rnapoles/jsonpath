{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit JSONPathCTS;

(* Runs the official JSONPath Compliance Test Suite
  (https://github.com/jsonpath-standard/jsonpath-compliance-test-suite)
  against this library.

  A suite file looks like (see cts.schema.json):
    { "tests": [ { "name": "...", "selector": "$.a", "document": {...},
                   "result": [...], "result_paths": [...] },
                 { "name": "...", "selector": "$.*", "document": {...},
                   "results": [[...], [...]], "results_paths": [[...], [...]] },
                 { "name": "...", "selector": "$..", "invalid_selector": true } ] }

  How one test case is judged
    invalid_selector   passes when the selector is REJECTED by the parser
    result             passes when the selected values equal "result" (same order,
                       JSON equality) and, if given, the normalized paths equal
                       "result_paths"
    results            passes when ONE alternative i matches: the values equal
                       results[i] and, if given, the paths equal results_paths[i]

  Files can be validated against cts.schema.json first (with the JSON Schema
  framework of this project); invalid files are reported and skipped. *)

interface

uses
  SysUtils, Classes, JSONPathJSON, JSONPathLexer, JSONPathParser, JSONPathQuery,
  JsonSchemaErrors, JsonSchemaLoader, JsonSchemaValidator;

type
  TCtsLineEvent = procedure(const ALine: string) of object;

  TCtsOptions = record
    { only run tests whose name contains this text (case-insensitive) }
    NameFilter: string;
    { only run tests that carry exactly this tag }
    TagFilter: string;
    { stop after the first failing test }
    FailFast: Boolean;
    { also report passing tests }
    Verbose: Boolean;
    { report only the summary }
    Quiet: Boolean;
    { descend into sub directories }
    Recursive: Boolean;
    { file name endings to scan, separated by ";" or "," }
    Extensions: string;
    { cts.schema.json to validate against; empty = search for it }
    SchemaFile: string;
    { validate suite files against cts.schema.json when it can be found }
    Validate: Boolean;
  end;

  TCtsStats = record
    { suite files that were attempted }
    Files: Integer;
    { files that could not be read, parsed or validated }
    FileErrors: Integer;
    Tests: Integer;
    Passed: Integer;
    Failed: Integer;
    { tests excluded by the name or tag filter }
    Skipped: Integer;
  end;

  TCtsRunner = class
  private
    FOptions: TCtsOptions;
    FOnLine: TCtsLineEvent;
    FStats: TCtsStats;
    FValidator: TJsonSchemaValidator;
    FSchemaId: string;
    FSchemaState: Integer; { 0 = not tried, 1 = ready, 2 = unavailable }
    FStop: Boolean;
    procedure Emit(const ALine: string);
    procedure FileError(const ASource, AMessage: string);
    function FindSchemaFile(const ADir: string): string;
    function EnsureSchema(const ADir: string): Boolean;
    function ValidateDocument(const ASource: string; ADoc: TJSONValue): Boolean;
    function Selected(ACase: TJSONValue): Boolean;
    function RunCase(ACase: TJSONValue; out AReason, AExpected, AActual: string): Boolean;
  public
    constructor Create(const AOptions: TCtsOptions; AOnLine: TCtsLineEvent);
    destructor Destroy; override;
    { A file or a directory. Returns True when everything ran and passed. }
    function RunPath(const APath: string): Boolean;
    function RunFile(const AFileName: string): Boolean;
    { An already parsed suite document; ASource is used in messages }
    function RunDocument(const ASource: string; ADoc: TJSONValue): Boolean;
    function SummaryLine: string;
    { True after FailFast stopped the run }
    property Stopped: Boolean read FStop;
    property Stats: TCtsStats read FStats;
  end;

function DefaultCtsOptions: TCtsOptions;

implementation

function DefaultCtsOptions: TCtsOptions;
begin
  Result.NameFilter := '';
  Result.TagFilter := '';
  Result.FailFast := False;
  Result.Verbose := False;
  Result.Quiet := False;
  Result.Recursive := True;
  Result.Extensions := '.json';
  Result.SchemaFile := '';
  Result.Validate := True;
end;

{ ---- helpers ---- }

function ValuesMatch(AExpected: TJSONValue; ARes: TJSONPathResult): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (AExpected = nil) or (AExpected.Kind <> jkArray) or (AExpected.Count <> ARes.Count) then
    Exit;
  for I := 0 to ARes.Count - 1 do
    if not JSONEquals(AExpected[I], ARes.Values[I]) then
      Exit;
  Result := True;
end;

function PathsMatch(AExpected: TJSONValue; ARes: TJSONPathResult): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (AExpected = nil) or (AExpected.Kind <> jkArray) or (AExpected.Count <> ARes.Count) then
    Exit;
  for I := 0 to ARes.Count - 1 do
    if (AExpected[I].Kind <> jkString) or (AExpected[I].StringValue <> ARes.Paths[I]) then
      Exit;
  Result := True;
end;

function PathsAsJson(ARes: TJSONPathResult): string;
var
  I: Integer;
begin
  Result := '[';
  for I := 0 to ARes.Count - 1 do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + JSONQuoteString(ARes.Paths[I]);
  end;
  Result := Result + ']';
end;

function EndsWithText(const AText, ASuffix: string): Boolean;
begin
  Result := (Length(AText) >= Length(ASuffix))
    and (LowerCase(Copy(AText, Length(AText) - Length(ASuffix) + 1, Length(ASuffix))) = ASuffix);
end;

{ ---- TCtsRunner ---- }

constructor TCtsRunner.Create(const AOptions: TCtsOptions; AOnLine: TCtsLineEvent);
begin
  inherited Create;
  FOptions := AOptions;
  FOnLine := AOnLine;
end;

destructor TCtsRunner.Destroy;
begin
  FValidator.Free;
  inherited Destroy;
end;

procedure TCtsRunner.Emit(const ALine: string);
begin
  if Assigned(FOnLine) then
    FOnLine(ALine);
end;

procedure TCtsRunner.FileError(const ASource, AMessage: string);
begin
  Inc(FStats.FileErrors);
  Emit('ERROR ' + ASource + ': ' + AMessage);
end;

function TCtsRunner.SummaryLine: string;
begin
  Result := Format('Files: %d  Tests: %d  Passed: %d  Failed: %d  Skipped: %d  File errors: %d',
    [FStats.Files, FStats.Tests, FStats.Passed, FStats.Failed, FStats.Skipped,
     FStats.FileErrors]);
end;

{ ---- schema validation of suite files ---- }

function TCtsRunner.FindSchemaFile(const ADir: string): string;
var
  ExeDir: string;
  Candidates: array[0..3] of string;
  I: Integer;
begin
  Result := '';
  ExeDir := ExtractFilePath(ParamStr(0));
  Candidates[0] := IncludeTrailingPathDelimiter(ADir) + 'cts.schema.json';
  Candidates[1] := IncludeTrailingPathDelimiter(GetCurrentDir) + 'cts.schema.json';
  Candidates[2] := ExeDir + 'cts.schema.json';
  Candidates[3] := ExeDir + '..' + PathDelim + 'cts' + PathDelim + 'cts.schema.json';
  for I := 0 to 3 do
    if FileExists(Candidates[I]) then
    begin
      Result := Candidates[I];
      Exit;
    end;
end;

function TCtsRunner.EnsureSchema(const ADir: string): Boolean;
var
  SchemaFile: string;
  Explicit: Boolean;
begin
  if FSchemaState = 0 then
  begin
    FSchemaState := 2;
    Explicit := FOptions.SchemaFile <> '';
    if Explicit then
      SchemaFile := FOptions.SchemaFile
    else
      SchemaFile := FindSchemaFile(ADir);
    if SchemaFile = '' then
    begin
      if not FOptions.Quiet then
        Emit('note: cts.schema.json not found, files are not validated');
    end
    else
    begin
      FValidator := TJsonSchemaValidator.Create;
      try
        FSchemaId := FValidator.LoadSchemaFile(SchemaFile);
        FSchemaState := 1;
        if FOptions.Verbose then
          Emit('validating suite files against ' + SchemaFile);
      except
        on E: EJsonSchemaError do
        begin
          FreeAndNil(FValidator);
          FileError(SchemaFile, 'cannot use this schema: ' + E.Message);
        end;
      end;
    end;
  end;
  Result := FSchemaState = 1;
end;

function TCtsRunner.ValidateDocument(const ASource: string; ADoc: TJSONValue): Boolean;
var
  R: TValidationResult;
  I, Shown: Integer;
begin
  Result := True;
  if not FOptions.Validate then
    Exit;
  if not EnsureSchema(ExtractFilePath(ExpandFileName(ASource))) then
    Exit;
  try
    R := FValidator.Validate(ADoc, FSchemaId);
  except
    on E: EJsonSchemaError do
    begin
      FileError(ASource, 'validation against cts.schema.json failed: ' + E.Message);
      Result := False;
      Exit;
    end;
  end;
  try
    if not R.IsValid then
    begin
      Result := False;
      FileError(ASource, Format('not a valid compliance test suite file (%d schema error(s))',
        [R.Errors.Count]));
      Shown := R.Errors.Count;
      if Shown > 5 then
        Shown := 5;
      for I := 0 to Shown - 1 do
        Emit('    ' + R.Errors[I].Describe);
      if R.Errors.Count > Shown then
        Emit(Format('    ... and %d more', [R.Errors.Count - Shown]));
    end;
  finally
    R.Free;
  end;
end;

{ ---- one test case ---- }

function TCtsRunner.Selected(ACase: TJSONValue): Boolean;
var
  V, Tags: TJSONValue;
  I: Integer;
  Found: Boolean;
begin
  Result := True;
  if FOptions.NameFilter <> '' then
  begin
    V := ACase.FindMember('name');
    if (V = nil) or (V.Kind <> jkString)
      or (Pos(LowerCase(FOptions.NameFilter), LowerCase(V.StringValue)) = 0) then
    begin
      Result := False;
      Exit;
    end;
  end;
  if FOptions.TagFilter <> '' then
  begin
    Tags := ACase.FindMember('tags');
    Found := False;
    if (Tags <> nil) and (Tags.Kind = jkArray) then
      for I := 0 to Tags.Count - 1 do
        if (Tags[I].Kind = jkString) and (Tags[I].StringValue = FOptions.TagFilter) then
          Found := True;
    Result := Found;
  end;
end;

function TCtsRunner.RunCase(ACase: TJSONValue; out AReason, AExpected,
  AActual: string): Boolean;
var
  Sel, Inv, Doc, ResV, PathsV, ResultsV, ResultsPathsV: TJSONValue;
  Path: TJSONPath;
  Res: TJSONPathResult;
  I: Integer;
begin
  Result := False;
  AReason := '';
  AExpected := '';
  AActual := '';
  Sel := ACase.FindMember('selector');
  if (Sel = nil) or (Sel.Kind <> jkString) then
  begin
    AReason := 'the test case has no string "selector"';
    Exit;
  end;

  Inv := ACase.FindMember('invalid_selector');
  if (Inv <> nil) and (Inv.Kind = jkBoolean) and Inv.BoolValue then
  begin
    try
      Path := TJSONPath.Create(Sel.StringValue);
      Path.Free;
      AReason := 'the selector is invalid but it was accepted';
      AExpected := 'a syntax error';
      AActual := 'the selector was parsed';
    except
      on EJSONPathParseException do
        Result := True;
    end;
    Exit;
  end;

  Doc := ACase.FindMember('document');
  if Doc = nil then
  begin
    AReason := 'the test case has no "document"';
    Exit;
  end;
  try
    Path := TJSONPath.Create(Sel.StringValue);
  except
    on E: EJSONPathParseException do
    begin
      AReason := 'a valid selector was rejected: ' + E.Message;
      Exit;
    end;
  end;
  try
    try
      Res := Path.Evaluate(Doc);
    except
      on E: Exception do
      begin
        AReason := 'evaluation failed: ' + E.ClassName + ': ' + E.Message;
        Exit;
      end;
    end;
    try
      ResV := ACase.FindMember('result');
      PathsV := ACase.FindMember('result_paths');
      ResultsV := ACase.FindMember('results');
      ResultsPathsV := ACase.FindMember('results_paths');
      if (ResV <> nil) and (ResV.Kind = jkArray) then
      begin
        AExpected := JSONToText(ResV);
        AActual := Res.ToJSONText;
        if not ValuesMatch(ResV, Res) then
        begin
          AReason := 'the selected values differ from "result"';
          Exit;
        end;
        if PathsV <> nil then
        begin
          if not PathsMatch(PathsV, Res) then
          begin
            AReason := 'the normalized paths differ from "result_paths"';
            AExpected := JSONToText(PathsV);
            AActual := PathsAsJson(Res);
            Exit;
          end;
        end;
        Result := True;
      end
      else if (ResultsV <> nil) and (ResultsV.Kind = jkArray) then
      begin
        for I := 0 to ResultsV.Count - 1 do
          if ValuesMatch(ResultsV[I], Res) and
            ((ResultsPathsV = nil) or (ResultsPathsV.Kind <> jkArray)
              or (I >= ResultsPathsV.Count) or PathsMatch(ResultsPathsV[I], Res)) then
          begin
            Result := True;
            Break;
          end;
        if not Result then
        begin
          AReason := 'no alternative of "results" (with its "results_paths") matches';
          AExpected := JSONToText(ResultsV);
          AActual := Res.ToJSONText + ' with paths ' + PathsAsJson(Res);
        end;
      end
      else
        AReason := 'the test case has neither "result" nor "results"';
    finally
      Res.Free;
    end;
  finally
    Path.Free;
  end;
end;

{ ---- documents, files, directories ---- }

function TCtsRunner.RunDocument(const ASource: string; ADoc: TJSONValue): Boolean;
var
  Tests, Case_, NameV: TJSONValue;
  I: Integer;
  TestName, Reason, Expected, Actual: string;
  Ok: Boolean;
  FailedBefore, ErrorsBefore: Integer;
begin
  Result := False;
  FailedBefore := FStats.Failed;
  ErrorsBefore := FStats.FileErrors;
  if (ADoc = nil) or (ADoc.Kind <> jkObject) then
  begin
    FileError(ASource, 'not a compliance test suite file: the document is not an object');
    Exit;
  end;
  Tests := ADoc.FindMember('tests');
  if (Tests = nil) or (Tests.Kind <> jkArray) then
  begin
    FileError(ASource, 'not a compliance test suite file: there is no "tests" array');
    Exit;
  end;
  for I := 0 to Tests.Count - 1 do
  begin
    if FStop then
      Break;
    Case_ := Tests[I];
    if Case_.Kind <> jkObject then
    begin
      Inc(FStats.Tests);
      Inc(FStats.Failed);
      Emit(Format('FAIL [%s] test #%d: the test case is not an object', [ASource, I + 1]));
      Continue;
    end;
    if not Selected(Case_) then
    begin
      Inc(FStats.Skipped);
      Continue;
    end;
    NameV := Case_.FindMember('name');
    if (NameV <> nil) and (NameV.Kind = jkString) then
      TestName := NameV.StringValue
    else
      TestName := Format('(unnamed test #%d)', [I + 1]);
    Inc(FStats.Tests);
    Ok := RunCase(Case_, Reason, Expected, Actual);
    if Ok then
    begin
      Inc(FStats.Passed);
      if FOptions.Verbose and not FOptions.Quiet then
        Emit('ok   ' + TestName);
    end
    else
    begin
      Inc(FStats.Failed);
      if not FOptions.Quiet then
      begin
        Emit('FAIL [' + ASource + '] ' + TestName);
        if Case_.FindMember('selector') <> nil then
          Emit('     selector: ' + Case_.FindMember('selector').AsString);
        Emit('     reason:   ' + Reason);
        if Expected <> '' then
          Emit('     expected: ' + Expected);
        if Actual <> '' then
          Emit('     actual:   ' + Actual);
      end;
      if FOptions.FailFast then
        FStop := True;
    end;
  end;
  Result := (FStats.Failed = FailedBefore) and (FStats.FileErrors = ErrorsBefore);
end;

function TCtsRunner.RunFile(const AFileName: string): Boolean;
var
  Loader: TSchemaFileLoader;
  Doc: TJSONValue;
begin
  Result := False;
  Inc(FStats.Files);
  Loader := TSchemaFileLoader.Create;
  try
    try
      Doc := Loader.ReadJson(AFileName);
    except
      on E: ESchemaLoadError do
      begin
        FileError(AFileName, E.Message);
        Exit;
      end;
    end;
  finally
    Loader.Free;
  end;
  try
    if ValidateDocument(AFileName, Doc) then
      Result := RunDocument(AFileName, Doc);
  finally
    Doc.Free;
  end;
end;

function TCtsRunner.RunPath(const APath: string): Boolean;
var
  Loader: TSchemaFileLoader;
  Files: TStringList;
  I: Integer;
begin
  Result := True;
  if DirectoryExists(APath) then
  begin
    Loader := TSchemaFileLoader.Create;
    try
      Loader.Extensions := FOptions.Extensions;
      try
        Files := Loader.ListFiles(APath, FOptions.Recursive);
      except
        on E: ESchemaLoadError do
        begin
          FileError(APath, E.Message);
          Result := False;
          Exit;
        end;
      end;
    finally
      Loader.Free;
    end;
    try
      for I := 0 to Files.Count - 1 do
      begin
        if FStop then
          Break;
        { the schema of the suite is not a suite }
        if EndsWithText(Files[I], '.schema.json') then
          Continue;
        if not RunFile(Files[I]) then
          Result := False;
      end;
    finally
      Files.Free;
    end;
  end
  else if FileExists(APath) then
    Result := RunFile(APath)
  else
  begin
    FileError(APath, 'file or directory not found');
    Result := False;
  end;
end;

end.
