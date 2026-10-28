{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit TestSupport;

{ Tiny dependency-free test harness plus helpers shared by the test programs.
  Every test program is a console application that returns a non-zero exit
  code when any check fails. }

interface

uses
  SysUtils, JSONPathCommon, JSONPathJSON, JSONPathLexer, JSONPathParser,
  JSONPathQuery, JSONPathRegex;

procedure BeginSuite(const ASuiteName: string);
procedure Check(Condition: Boolean; const TestName: string);
procedure CheckEqualsStr(const Expected, Actual, TestName: string);
procedure CheckEqualsInt(Expected, Actual: Int64; const TestName: string);
{ Prints a summary and returns the number of failed checks (use as exit code) }
function EndSuite: Integer;

{ Evaluates Query against JsonText and returns the selected values as a
  compact JSON array. Syntax errors yield 'ERROR: <message>'. }
function QueryValues(const JsonText, QueryText: string): string;
{ Normalized paths of the selected nodes joined with ';' }
function QueryPaths(const JsonText, QueryText: string): string;
function QueryCount(const JsonText, QueryText: string): Integer;
{ True when the filter expression selects at least one child of the root }
function ExprIsTrue(const JsonText, Expr: string): Boolean;
function QueryParses(const QueryText: string): Boolean;
{ 0-based offset of the syntax error, or -1 when the query parses }
function QueryErrorOffset(const QueryText: string): Integer;
function QueryErrorRule(const QueryText: string): string;

function RegexMatches(const Pattern, Text: string): Boolean;
function RegexSearches(const Pattern, Text: string): Boolean;
function RegexIsInvalid(const Pattern: string): Boolean;

function JSONRoundTrip(const Text: string): string;
function JSONIsInvalid(const Text: string): Boolean;

implementation

var
  GSuite: string;
  GPassed: Integer;
  GFailed: Integer;

procedure BeginSuite(const ASuiteName: string);
begin
  GSuite := ASuiteName;
  GPassed := 0;
  GFailed := 0;
end;

procedure Check(Condition: Boolean; const TestName: string);
begin
  if Condition then
    Inc(GPassed)
  else
  begin
    Inc(GFailed);
    WriteLn('  FAIL: ', TestName);
  end;
end;

procedure CheckEqualsStr(const Expected, Actual, TestName: string);
begin
  if Expected = Actual then
    Inc(GPassed)
  else
  begin
    Inc(GFailed);
    WriteLn('  FAIL: ', TestName);
    WriteLn('        expected: ', Expected);
    WriteLn('        actual:   ', Actual);
  end;
end;

procedure CheckEqualsInt(Expected, Actual: Int64; const TestName: string);
begin
  if Expected = Actual then
    Inc(GPassed)
  else
  begin
    Inc(GFailed);
    WriteLn('  FAIL: ', TestName);
    WriteLn('        expected: ', Expected);
    WriteLn('        actual:   ', Actual);
  end;
end;

function EndSuite: Integer;
begin
  WriteLn(GSuite, ': ', GPassed, ' passed, ', GFailed, ' failed');
  Result := GFailed;
end;

function RunQuery(const JsonText, QueryText: string; Mode: Integer): string;
var
  Doc: TJSONValue;
  Res: TJSONPathResult;
begin
  Result := '';
  Doc := ParseJSON(JsonText);
  try
    try
      Res := JSONPathSelect(QueryText, Doc);
      try
        case Mode of
          0: Result := Res.ToJSONText;
          1: Result := Res.PathsToText;
        else
          Result := IntToStr(Res.Count);
        end;
      finally
        Res.Free;
      end;
    except
      on E: EJSONPathParseException do
        Result := 'ERROR: ' + E.Message;
    end;
  finally
    Doc.Free;
  end;
end;

function QueryValues(const JsonText, QueryText: string): string;
begin
  Result := RunQuery(JsonText, QueryText, 0);
end;

function QueryPaths(const JsonText, QueryText: string): string;
begin
  Result := RunQuery(JsonText, QueryText, 1);
end;

function QueryCount(const JsonText, QueryText: string): Integer;
begin
  Result := StrToIntDef(RunQuery(JsonText, QueryText, 2), -1);
end;

function ExprIsTrue(const JsonText, Expr: string): Boolean;
begin
  Result := QueryCount(JsonText, '$[?' + Expr + ']') > 0;
end;

function QueryParses(const QueryText: string): Boolean;
var
  Q: TJSONPathQueryNode;
begin
  Result := False;
  try
    Q := ParseJSONPath(QueryText);
    Q.Free;
    Result := True;
  except
    on EJSONPathParseException do
      Result := False;
  end;
end;

function QueryErrorOffset(const QueryText: string): Integer;
var
  Q: TJSONPathQueryNode;
begin
  Result := -1;
  try
    Q := ParseJSONPath(QueryText);
    Q.Free;
  except
    on E: EJSONPathParseException do
      Result := E.Position;
  end;
end;

function QueryErrorRule(const QueryText: string): string;
var
  Q: TJSONPathQueryNode;
begin
  Result := '';
  try
    Q := ParseJSONPath(QueryText);
    Q.Free;
  except
    on E: EJSONPathParseException do
      Result := E.RuleName;
  end;
end;

function RegexMatches(const Pattern, Text: string): Boolean;
var
  R: TIRegexp;
begin
  R := TIRegexp.Create(Pattern);
  try
    Result := R.IsMatch(Text);
  finally
    R.Free;
  end;
end;

function RegexSearches(const Pattern, Text: string): Boolean;
var
  R: TIRegexp;
begin
  R := TIRegexp.Create(Pattern);
  try
    Result := R.IsSearch(Text);
  finally
    R.Free;
  end;
end;

function RegexIsInvalid(const Pattern: string): Boolean;
var
  R: TIRegexp;
begin
  Result := False;
  try
    R := TIRegexp.Create(Pattern);
    R.Free;
  except
    on EJSONPathRegexError do
      Result := True;
  end;
end;

function JSONRoundTrip(const Text: string): string;
var
  V: TJSONValue;
begin
  V := ParseJSON(Text);
  try
    Result := JSONToText(V);
  finally
    V.Free;
  end;
end;

function JSONIsInvalid(const Text: string): Boolean;
var
  V: TJSONValue;
begin
  Result := False;
  try
    V := ParseJSON(Text);
    V.Free;
  except
    on EJSONPathJSONError do
      Result := True;
  end;
end;

end.
