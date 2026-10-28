{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestJSONPretty;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils, JSONPathJSON;

function Pretty(const AText: string; AIdent: Integer): string;
var
  V: TJSONValue;
begin
  V := ParseJSON(AText);
  try
    Result := JSONToTextPretty(V, AIdent);
  finally
    V.Free;
  end;
end;

begin
  BeginSuite('JSON: pretty printing');
  CheckEqualsStr('42', Pretty('42', 2), 'scalars are printed as-is');
  CheckEqualsStr('[]', Pretty('[ ]', 2), 'empty array stays on one line');
  CheckEqualsStr('{}', Pretty('{ }', 2), 'empty object stays on one line');
  CheckEqualsStr('[' + #10 + '  1,' + #10 + '  2' + #10 + ']', Pretty('[1,2]', 2),
    'array elements go on separate lines');
  CheckEqualsStr('{' + #10 + '    "a": 1' + #10 + '}', Pretty('{"a":1}', 4),
    'indent width is configurable');
  CheckEqualsStr(
    '{' + #10 +
    '  "a": [' + #10 +
    '    1,' + #10 +
    '    2' + #10 +
    '  ],' + #10 +
    '  "b": {},' + #10 +
    '  "c": []' + #10 +
    '}',
    Pretty('{"a":[1,2],"b":{},"c":[]}', 2), 'nested structures are indented per level');
  CheckEqualsStr('{"a":[1,2]}', Pretty('{"a":[1,2]}', 0), 'zero indent falls back to compact output');
  CheckEqualsStr('"a\nb"', Pretty('"a\nb"', 2), 'strings are escaped');
  CheckEqualsStr('', JSONToTextPretty(nil, 2), 'nil value gives an empty string');
  Halt(EndSuite);
end.
