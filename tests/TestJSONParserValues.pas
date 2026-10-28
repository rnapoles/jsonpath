{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestJSONParserValues;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils, JSONPathCommon, JSONPathJSON;

function UnescapedOf(const S: string): string;
var
  V: TJSONValue;
begin
  V := ParseJSON(S);
  try
    Result := V.StringValue;
  finally
    V.Free;
  end;
end;

begin
  BeginSuite('JSON: parsing valid documents');
  CheckEqualsStr('null', JSONRoundTrip('null'), 'null');
  CheckEqualsStr('true', JSONRoundTrip(' true '), 'boolean with surrounding whitespace');
  CheckEqualsStr('-12.5', JSONRoundTrip('-12.5'), 'negative decimal');
  CheckEqualsStr('100', JSONRoundTrip('1e2'), 'exponent notation');
  CheckEqualsStr('"a\nb"', JSONRoundTrip('"a\nb"'), 'string escapes round-trip');
  CheckEqualsStr('[]', JSONRoundTrip('[ ]'), 'empty array');
  CheckEqualsStr('{}', JSONRoundTrip('{ }'), 'empty object');
  CheckEqualsStr('{"a":[1,2,{"b":null}]}', JSONRoundTrip('{ "a" : [ 1 , 2 , { "b" : null } ] }'), 'nested structure');
  CheckEqualsStr('{"a":2}', JSONRoundTrip('{"a":1,"a":2}'), 'duplicate member names keep the last value');
  CheckEqualsStr('{"b":1,"a":2}', JSONRoundTrip('{"b":1,"a":2}'), 'member order is preserved');
  CheckEqualsInt(1, CodePointLength(UnescapedOf('"\ud83d\ude00"')), 'surrogate pair escape decodes to one code point');
  Halt(EndSuite);
end.
