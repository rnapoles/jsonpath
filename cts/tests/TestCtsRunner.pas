{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestCtsRunner;

{$APPTYPE CONSOLE}

uses
  TestSupport, SchemaTestSupport, SysUtils, Classes, JSONPathJSON, JSONPathCTS;

type
  TLines = class
  public
    Items: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Add(const ALine: string);
    function Text: string;
  end;

constructor TLines.Create;
begin
  inherited Create;
  Items := TStringList.Create;
end;

destructor TLines.Destroy;
begin
  Items.Free;
  inherited Destroy;
end;

procedure TLines.Add(const ALine: string);
begin
  Items.Add(ALine);
end;

function TLines.Text: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Items.Count - 1 do
    Result := Result + Items[I] + #10;
end;

const
  PassDoc =
    '{"tests":[' +
    '{"name":"root node","selector":"$","document":[1,2],"result":[[1,2]],"result_paths":["$"]},' +
    '{"name":"child member","selector":"$.a","document":{"a":5},"result":[5],' +
    '"result_paths":["$[''a'']"],"tags":["x"]},' +
    '{"name":"wildcard object","selector":"$.*","document":{"a":1,"b":2},' +
    '"results":[[1,2],[2,1]],"results_paths":[["$[''a'']","$[''b'']"],["$[''b'']","$[''a'']"]]},' +
    '{"name":"bad syntax","selector":"$..","invalid_selector":true}]}';

  FailDoc =
    '{"tests":[' +
    '{"name":"wrong result","selector":"$.a","document":{"a":5},"result":[6],' +
    '"result_paths":["$[''a'']"],"tags":["x"]},' +
    '{"name":"wrong paths","selector":"$.a","document":{"a":5},"result":[5],"result_paths":["$[''b'']"]},' +
    '{"name":"accepted selector","selector":"$.a","invalid_selector":true},' +
    '{"name":"rejected selector","selector":"$[","document":[],"result":[],"result_paths":[]},' +
    '{"name":"alternative paths differ","selector":"$.*","document":{"a":1,"b":2},' +
    '"results":[[1,2],[2,1]],"results_paths":[["$[''b'']","$[''a'']"],["$[''a'']","$[''b'']"]]},' +
    '{"name":"no document","selector":"$","result":[],"result_paths":[]},' +
    '{"name":"good one","selector":"$","document":1,"result":[1],"result_paths":["$"]}]}';

  MiniSchema =
    '{"$id":"http://example.com/mini-cts.json","type":"object","required":["tests"],' +
    '"properties":{"tests":{"type":"array","items":{"type":"object","required":["name","selector"]}}}}';

function Has(const AText, ASub: string): Boolean;
begin
  Result := Pos(ASub, AText) > 0;
end;

{ runs a suite document; returns the runner's verdict }
function RunDoc(const AJson: string; const AOptions: TCtsOptions; ALines: TLines;
  out AStats: TCtsStats; out AStopped: Boolean): Boolean;
var
  Doc: TJSONValue;
  Runner: TCtsRunner;
begin
  Doc := ParseJSON(AJson);
  try
    Runner := TCtsRunner.Create(AOptions, ALines.Add);
    try
      Result := Runner.RunDocument('test', Doc);
      AStats := Runner.Stats;
      AStopped := Runner.Stopped;
    finally
      Runner.Free;
    end;
  finally
    Doc.Free;
  end;
end;

{ runs a path; returns the verdict, statistics and output }
function RunPathOf(const APath: string; const AOptions: TCtsOptions; ALines: TLines;
  out AStats: TCtsStats): Boolean;
var
  Runner: TCtsRunner;
begin
  Runner := TCtsRunner.Create(AOptions, ALines.Add);
  try
    Result := Runner.RunPath(APath);
    AStats := Runner.Stats;
  finally
    Runner.Free;
  end;
end;

procedure DocumentTests;
var
  Lines: TLines;
  Stats: TCtsStats;
  Opts: TCtsOptions;
  Stopped, Ok: Boolean;
begin
  Opts := DefaultCtsOptions;

  Lines := TLines.Create;
  try
    Ok := RunDoc(PassDoc, Opts, Lines, Stats, Stopped);
    Check(Ok, 'a suite where every test passes returns True');
    CheckEqualsInt(4, Stats.Tests, 'passing suite: tests');
    CheckEqualsInt(4, Stats.Passed, 'passing suite: passed');
    CheckEqualsInt(0, Stats.Failed, 'passing suite: failed');
    Check(Lines.Items.Count = 0, 'passing tests are not listed by default');
  finally
    Lines.Free;
  end;

  Lines := TLines.Create;
  try
    Ok := RunDoc(FailDoc, Opts, Lines, Stats, Stopped);
    Check(not Ok, 'a suite with failures returns False');
    CheckEqualsInt(7, Stats.Tests, 'failing suite: tests');
    CheckEqualsInt(1, Stats.Passed, 'failing suite: passed');
    CheckEqualsInt(6, Stats.Failed, 'failing suite: failed');
    Check(Has(Lines.Text, 'FAIL [test] wrong result'), 'a failure names the file and the test');
    Check(Has(Lines.Text, 'expected: [6]'), 'a failure shows the expected values');
    Check(Has(Lines.Text, 'actual:   [5]'), 'a failure shows the actual values');
    Check(Has(Lines.Text, 'selector: $.a'), 'a failure shows the selector');
    Check(Has(Lines.Text, 'result_paths'), 'a path mismatch is reported');
    Check(Has(Lines.Text, 'expected: ["$[''b'']"]'), 'a path mismatch shows the expected paths');
    Check(Has(Lines.Text, 'actual:   ["$[''a'']"]'), 'a path mismatch shows the actual paths');
    Check(Has(Lines.Text, 'accepted'), 'an invalid selector that is accepted is reported');
    Check(Has(Lines.Text, 'rejected'), 'a valid selector that is rejected is reported');
    Check(Has(Lines.Text, 'no alternative'), 'no matching alternative of "results" is reported');
    Check(Has(Lines.Text, '"document"'), 'a missing document is reported');
    Check(not Has(Lines.Text, 'good one'), 'passing tests are not listed in the failure output');
  finally
    Lines.Free;
  end;

  { verbose and quiet }
  Opts := DefaultCtsOptions;
  Opts.Verbose := True;
  Lines := TLines.Create;
  try
    RunDoc(PassDoc, Opts, Lines, Stats, Stopped);
    Check(Has(Lines.Text, 'ok   root node'), 'verbose mode lists passing tests');
  finally
    Lines.Free;
  end;
  Opts := DefaultCtsOptions;
  Opts.Quiet := True;
  Lines := TLines.Create;
  try
    RunDoc(FailDoc, Opts, Lines, Stats, Stopped);
    Check(not Has(Lines.Text, 'FAIL'), 'quiet mode hides failure details');
    CheckEqualsInt(6, Stats.Failed, 'quiet mode still counts failures');
  finally
    Lines.Free;
  end;

  { filters }
  Opts := DefaultCtsOptions;
  Opts.NameFilter := 'CHILD';
  Lines := TLines.Create;
  try
    RunDoc(PassDoc, Opts, Lines, Stats, Stopped);
    CheckEqualsInt(1, Stats.Tests, 'name filter: tests run (case-insensitive)');
    CheckEqualsInt(3, Stats.Skipped, 'name filter: tests skipped');
  finally
    Lines.Free;
  end;
  Opts := DefaultCtsOptions;
  Opts.TagFilter := 'x';
  Lines := TLines.Create;
  try
    RunDoc(PassDoc, Opts, Lines, Stats, Stopped);
    CheckEqualsInt(1, Stats.Tests, 'tag filter: tests run');
    CheckEqualsInt(3, Stats.Skipped, 'tag filter: tests skipped');
  finally
    Lines.Free;
  end;
  Opts := DefaultCtsOptions;
  Opts.NameFilter := 'nothing matches this';
  Lines := TLines.Create;
  try
    Ok := RunDoc(PassDoc, Opts, Lines, Stats, Stopped);
    Check(Ok and (Stats.Tests = 0) and (Stats.Skipped = 4), 'a filter that matches nothing runs nothing');
  finally
    Lines.Free;
  end;

  { fail fast }
  Opts := DefaultCtsOptions;
  Opts.FailFast := True;
  Lines := TLines.Create;
  try
    RunDoc(FailDoc, Opts, Lines, Stats, Stopped);
    CheckEqualsInt(1, Stats.Tests, 'fail-fast stops after the first failure');
    CheckEqualsInt(1, Stats.Failed, 'fail-fast: one failure');
    Check(Stopped, 'the runner reports that it stopped');
  finally
    Lines.Free;
  end;
end;

procedure MalformedTests;
var
  Lines: TLines;
  Stats: TCtsStats;
  Stopped, Ok: Boolean;
  Opts: TCtsOptions;
begin
  Opts := DefaultCtsOptions;
  Lines := TLines.Create;
  try
    Ok := RunDoc('{"nothing":1}', Opts, Lines, Stats, Stopped);
    Check(not Ok, 'a document without "tests" is rejected');
    CheckEqualsInt(1, Stats.FileErrors, 'missing "tests" is a file error');
    Check(Has(Lines.Text, '"tests"'), 'the message mentions "tests"');
  finally
    Lines.Free;
  end;
  Lines := TLines.Create;
  try
    Ok := RunDoc('[]', Opts, Lines, Stats, Stopped);
    Check((not Ok) and (Stats.FileErrors = 1), 'a document that is not an object is a file error');
  finally
    Lines.Free;
  end;
  Lines := TLines.Create;
  try
    Ok := RunDoc('{"tests":[5]}', Opts, Lines, Stats, Stopped);
    Check((not Ok) and (Stats.Failed = 1), 'a test case that is not an object fails');
    Check(Has(Lines.Text, 'not an object'), 'the message says what is wrong');
  finally
    Lines.Free;
  end;
  Lines := TLines.Create;
  try
    Ok := RunDoc('{"tests":[{"name":"no selector","document":1,"result":[]}]}', Opts, Lines, Stats, Stopped);
    Check((not Ok) and (Stats.Failed = 1), 'a test case without a selector fails (no crash)');
    Check(Has(Lines.Text, '"selector"'), 'the message mentions the selector');
  finally
    Lines.Free;
  end;
  Lines := TLines.Create;
  try
    Ok := RunDoc('{"tests":[{"name":"no expectation","selector":"$","document":1}]}', Opts, Lines, Stats, Stopped);
    Check((not Ok) and Has(Lines.Text, 'neither'), 'a test case without an expectation fails');
  finally
    Lines.Free;
  end;
end;

procedure FileTests;
var
  Tmp: string;
  Lines: TLines;
  Stats: TCtsStats;
  Opts: TCtsOptions;
  Ok: Boolean;
begin
  Tmp := TestTempDir + 'cts' + PathDelim;
  RemoveDirTree(Tmp);
  try
    WriteTextFile(Tmp + 'bad.json', '{oops');
    WriteTextFile(Tmp + 'good.json', PassDoc);
    WriteTextFile(Tmp + 'sub' + PathDelim + 'deep.json', PassDoc);
    WriteTextFile(Tmp + 'notes.txt', PassDoc);
    WriteTextFile(Tmp + 'suite.cts', PassDoc);
    WriteTextFile(Tmp + 'cts.schema.json', MiniSchema);

    Opts := DefaultCtsOptions;
    Lines := TLines.Create;
    try
      Ok := RunPathOf(Tmp, Opts, Lines, Stats);
      Check(not Ok, 'a directory with a broken file returns False');
      CheckEqualsInt(3, Stats.Files, 'recursive scan: bad.json, good.json and sub/deep.json');
      CheckEqualsInt(1, Stats.FileErrors, 'the malformed file is a file error');
      CheckEqualsInt(8, Stats.Tests, 'both good files are run');
      CheckEqualsInt(8, Stats.Passed, 'both good files pass');
      Check(Has(Lines.Text, 'bad.json'), 'the broken file is named');
      Check(not Has(Lines.Text, 'cts.schema.json:'), 'the schema file is not treated as a suite');
    finally
      Lines.Free;
    end;

    Opts := DefaultCtsOptions;
    Opts.Recursive := False;
    Lines := TLines.Create;
    try
      RunPathOf(Tmp, Opts, Lines, Stats);
      CheckEqualsInt(2, Stats.Files, 'non-recursive scan skips sub directories');
      CheckEqualsInt(4, Stats.Tests, 'non-recursive scan runs only the top level suite');
    finally
      Lines.Free;
    end;

    Opts := DefaultCtsOptions;
    Opts.Extensions := '.cts';
    Lines := TLines.Create;
    try
      Ok := RunPathOf(Tmp, Opts, Lines, Stats);
      Check(Ok, 'a configured extension finds other suite files');
      CheckEqualsInt(1, Stats.Files, 'only files with the configured extension are scanned');
      CheckEqualsInt(4, Stats.Passed, 'the .cts suite passes');
    finally
      Lines.Free;
    end;

    Opts := DefaultCtsOptions;
    Lines := TLines.Create;
    try
      Ok := RunPathOf(Tmp + 'good.json', Opts, Lines, Stats);
      Check(Ok and (Stats.Files = 1) and (Stats.Passed = 4), 'a single file can be run directly');
    finally
      Lines.Free;
    end;

    Lines := TLines.Create;
    try
      Ok := RunPathOf(Tmp + 'does-not-exist.json', Opts, Lines, Stats);
      Check(not Ok, 'a missing path returns False');
      CheckEqualsInt(1, Stats.FileErrors, 'a missing path is a file error');
      Check(Has(Lines.Text, 'not found'), 'the message says "not found"');
    finally
      Lines.Free;
    end;
  finally
    RemoveDirTree(Tmp);
  end;
end;

procedure SchemaTests;
var
  Tmp: string;
  Lines: TLines;
  Stats: TCtsStats;
  Opts: TCtsOptions;
  Ok: Boolean;
begin
  Tmp := TestTempDir + 'ctsschema' + PathDelim;
  RemoveDirTree(Tmp);
  try
    WriteTextFile(Tmp + 'cts.schema.json', MiniSchema);
    WriteTextFile(Tmp + 'shape.json', '{"tests":[{"name":"only a name"}]}');
    WriteTextFile(Tmp + 'pass.json', PassDoc);

    Opts := DefaultCtsOptions;
    Lines := TLines.Create;
    try
      Ok := RunPathOf(Tmp + 'shape.json', Opts, Lines, Stats);
      Check(not Ok, 'a suite file that violates the schema is rejected');
      CheckEqualsInt(1, Stats.FileErrors, 'a schema violation is a file error');
      CheckEqualsInt(0, Stats.Tests, 'a rejected file runs no tests');
      Check(Has(Lines.Text, 'not a valid compliance test suite file'), 'the message explains the rejection');
      Check(Has(Lines.Text, 'selector'), 'the schema error names the missing property');
    finally
      Lines.Free;
    end;

    Opts := DefaultCtsOptions;
    Opts.Validate := False;
    Lines := TLines.Create;
    try
      RunPathOf(Tmp + 'shape.json', Opts, Lines, Stats);
      CheckEqualsInt(0, Stats.FileErrors, 'with validation off the file is not rejected');
      CheckEqualsInt(1, Stats.Failed, 'with validation off the bad test case fails on its own');
    finally
      Lines.Free;
    end;

    Opts := DefaultCtsOptions;
    Opts.SchemaFile := Tmp + 'no-such-schema.json';
    Lines := TLines.Create;
    try
      RunPathOf(Tmp + 'pass.json', Opts, Lines, Stats);
      CheckEqualsInt(1, Stats.FileErrors, 'an unusable explicit schema is reported');
      CheckEqualsInt(4, Stats.Passed, 'the tests still run without validation');
    finally
      Lines.Free;
    end;
  finally
    RemoveDirTree(Tmp);
  end;
end;

{ number of file errors when a suite text is checked against the real cts.schema.json }
function ErrorsAgainst(const ASchemaFile, ASuiteJson: string): Integer;
var
  Tmp: string;
  Lines: TLines;
  Stats: TCtsStats;
  Opts: TCtsOptions;
begin
  Tmp := TestTempDir + 'ctsreal' + PathDelim;
  RemoveDirTree(Tmp);
  try
    WriteTextFile(Tmp + 'suite.json', ASuiteJson);
    Opts := DefaultCtsOptions;
    Opts.SchemaFile := ASchemaFile;
    Lines := TLines.Create;
    try
      RunPathOf(Tmp + 'suite.json', Opts, Lines, Stats);
      Result := Stats.FileErrors;
    finally
      Lines.Free;
    end;
  finally
    RemoveDirTree(Tmp);
  end;
end;

procedure RealSchemaTests;
var
  Schema: string;
begin
  Schema := ExtractFilePath(ParamStr(0)) + 'cts.schema.json';
  if not FileExists(Schema) then
    Schema := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'cts' + PathDelim + 'cts.schema.json';
  if not FileExists(Schema) then
  begin
    WriteLn('  (skipped: ', Schema, ' not found)');
    Exit;
  end;
  CheckEqualsInt(0, ErrorsAgainst(Schema, PassDoc), 'the real cts.schema.json accepts a valid suite');
  CheckEqualsInt(1, ErrorsAgainst(Schema, '{"tests":[{"selector":"$","document":1,"result":[1],"result_paths":["$"]}]}'),
    'the real schema requires a name');
  CheckEqualsInt(1, ErrorsAgainst(Schema, '{"tests":[{"name":"a","selector":"$","document":1,"result":[1],"result_paths":["$"]}]}'),
    'the real schema requires names of at least two characters without outer blanks');
  CheckEqualsInt(1, ErrorsAgainst(Schema, '{"tests":[{"name":" padded ","selector":"$","document":1,"result":[1],"result_paths":["$"]}]}'),
    'the real schema rejects names with leading or trailing blanks');
  CheckEqualsInt(1, ErrorsAgainst(Schema, '{"tests":[{"name":"both forms","selector":"$","document":1,"result":[1],' +
    '"result_paths":["$"],"results":[[1],[1]],"results_paths":[["$"],["$"]]}]}'),
    'the real schema allows only one of result and results');
  CheckEqualsInt(1, ErrorsAgainst(Schema, '{"tests":[{"name":"missing paths","selector":"$","document":1,"result":[1]}]}'),
    'the real schema requires result_paths together with result');
  CheckEqualsInt(1, ErrorsAgainst(Schema, '{"tests":[{"name":"flag false","selector":"$","invalid_selector":false}]}'),
    'the real schema requires invalid_selector to be true');
  CheckEqualsInt(1, ErrorsAgainst(Schema, '{"tests":[{"name":"one alternative","selector":"$","document":1,' +
    '"results":[[1]],"results_paths":[["$"]]}]}'),
    'the real schema requires at least two alternatives in results');
  CheckEqualsInt(1, ErrorsAgainst(Schema, '{"tests":{}}'), 'the real schema requires "tests" to be an array');
  CheckEqualsInt(1, ErrorsAgainst(Schema, '{"cases":[]}'), 'the real schema requires "tests"');
  CheckEqualsInt(0, ErrorsAgainst(Schema, '{"tests":[{"name":"invalid selector","selector":"$..","invalid_selector":true}]}'),
    'the real schema accepts an invalid_selector test');
end;

var
  Lines: TLines;
  Stats: TCtsStats;
  Opts: TCtsOptions;
  Runner: TCtsRunner;
  Doc: TJSONValue;
begin
  BeginSuite('CTS runner');
  Opts := DefaultCtsOptions;
  Check(Opts.Recursive and Opts.Validate and (Opts.Extensions = '.json'), 'default options');
  Check(not Opts.FailFast and not Opts.Verbose and not Opts.Quiet, 'default options: quiet flags off');

  DocumentTests;
  MalformedTests;
  FileTests;
  SchemaTests;
  RealSchemaTests;

  Lines := TLines.Create;
  Doc := ParseJSON(FailDoc);
  try
    Runner := TCtsRunner.Create(DefaultCtsOptions, Lines.Add);
    try
      Runner.RunDocument('x', Doc);
      Stats := Runner.Stats;
      Check(Has(Runner.SummaryLine, 'Tests: 7') and Has(Runner.SummaryLine, 'Passed: 1')
        and Has(Runner.SummaryLine, 'Failed: 6'), 'the summary line reports the counts');
    finally
      Runner.Free;
    end;
  finally
    Doc.Free;
    Lines.Free;
  end;
  Halt(EndSuite);
end.
