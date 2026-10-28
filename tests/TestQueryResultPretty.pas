{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryResultPretty;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils, JSONPathJSON, JSONPathQuery;

function PrettyResult(const AJson, AQuery: string): string;
var
  Doc: TJSONValue;
  Res: TJSONPathResult;
begin
  Doc := ParseJSON(AJson);
  try
    Res := JSONPathSelect(AQuery, Doc);
    try
      Result := Res.JSONToTextPretty;
    finally
      Res.Free;
    end;
  finally
    Doc.Free;
  end;
end;

begin
  BeginSuite('Query result: pretty printing');
  CheckEqualsStr('[]', PrettyResult('{"a":1}', '$.zzz'), 'empty result is []');
  CheckEqualsStr('[' + #10 + '  1' + #10 + ']', PrettyResult('{"a":1}', '$.a'),
    'single scalar result');
  CheckEqualsStr(
    '[' + #10 +
    '  1,' + #10 +
    '  {' + #10 +
    '    "b": 2' + #10 +
    '  }' + #10 +
    ']',
    PrettyResult('{"a":[1,{"b":2}]}', '$.a[*]'),
    'nested values are indented one level deeper inside the result array');
  CheckEqualsStr(
    '[' + #10 +
    '  [],' + #10 +
    '  {}' + #10 +
    ']',
    PrettyResult('{"a":[[],{}]}', '$.a[*]'), 'empty containers stay compact');
  Halt(EndSuite);
end.
