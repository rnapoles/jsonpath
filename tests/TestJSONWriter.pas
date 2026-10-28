{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestJSONWriter;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils, JSONPathCommon, JSONPathJSON;

function Emit(const AText: string; const AOptions: TJSONWriteOptions): string;
var
  V: TJSONValue;
begin
  V := ParseJSON(AText);
  try
    Result := JSONToText(V, AOptions);
  finally
    V.Free;
  end;
end;

function Sorted(const AText: string; AIndent: Integer): string;
var
  O: TJSONWriteOptions;
begin
  O := DefaultJSONWriteOptions;
  O.SortKeys := True;
  O.Indent := AIndent;
  Result := Emit(AText, O);
end;

function Escaped(const AText: string): string;
var
  O: TJSONWriteOptions;
begin
  O := DefaultJSONWriteOptions;
  O.EscapeNonAscii := True;
  Result := Emit(AText, O);
end;

function Canon(const AText: string): string;
var
  V: TJSONValue;
begin
  V := ParseJSON(AText);
  try
    Result := JSONCanonicalText(V);
  finally
    V.Free;
  end;
end;

{ the first member name of an object, as its first code point }
function FirstKeyCodePoint(const AText: string): Cardinal;
var
  V: TJSONValue;
  CPs: TCodePointArray;
begin
  V := ParseJSON(AText);
  try
    CPs := StringToCodePoints(V.Names[0]);
    Result := CPs[0];
  finally
    V.Free;
  end;
end;

var
  O: TJSONWriteOptions;
begin
  BeginSuite('JSON: writer options and canonical output');

  O := DefaultJSONWriteOptions;
  CheckEqualsInt(0, O.Indent, 'default: compact');
  Check(not O.SortKeys and not O.EscapeNonAscii and not O.Canonical, 'default: no sorting, escaping or canonical mode');
  Check(O.OriginalNumbers, 'default: numbers are written as parsed');

  { sorted keys }
  CheckEqualsStr('{"B":4,"a":2,"aa":3,"b":1}', Sorted('{"b":1,"a":2,"aa":3,"B":4}', 0), 'keys are sorted');
  CheckEqualsStr('{"a":{"x":1,"y":2},"b":[{"m":1,"n":2},3]}',
    Sorted('{"b":[{"n":2,"m":1},3],"a":{"y":2,"x":1}}', 0),
    'nested objects are sorted, arrays keep their order');
  CheckEqualsStr('{' + #10 + '  "a": [' + #10 + '    1' + #10 + '  ],' + #10 + '  "b": 1' + #10 + '}',
    Sorted('{"b":1,"a":[1]}', 2), 'sorting combines with indentation');
  CheckEqualsStr('{"b":1,"a":2}', Emit('{"b":1,"a":2}', DefaultJSONWriteOptions), 'without SortKeys the order is kept');
  CheckEqualsInt($1F600, FirstKeyCodePoint(Sorted('{"\uffff":1,"\ud83d\ude00":2}', 0)),
    'keys are ordered by UTF-16 code units (a surrogate pair sorts before U+FFFF)');

  { escaping non-ASCII }
  CheckEqualsStr('"\u00e9\ud83d\ude00x"', Escaped('"\u00e9\ud83d\ude00x"'), 'non-ASCII characters become \u escapes');
  CheckEqualsStr('{"\u00e9":1}', Escaped('{"\u00e9":1}'), 'member names are escaped too');
  CheckEqualsStr('"abc\n"', Escaped('"abc\n"'), 'ASCII text is unchanged');
  CheckEqualsStr('"\u0001' + #127 + '"', Escaped('"\u0001\u007f"'), 'control characters are escaped, DEL is not');
  CheckEqualsInt(5, CodePointLength(Emit('"\u00e9\ud83d\ude00x"', DefaultJSONWriteOptions)),
    'without EscapeNonAscii the characters are written as they are');

  { numbers }
  O := DefaultJSONWriteOptions;
  O.OriginalNumbers := False;
  CheckEqualsStr('[1,100,1.5]', Emit('[1.0,1e2,1.50]', O), 'OriginalNumbers=False normalises numbers');
  CheckEqualsStr('[1.0,1e2,1.50]', Emit('[1.0,1e2,1.50]', DefaultJSONWriteOptions), 'OriginalNumbers=True keeps them');

  { canonical output (RFC 8785) }
  CheckEqualsStr('{"a":1,"b":2}', Canon('{"b":2,"a":1}'), 'canonical: sorted members');
  CheckEqualsStr('{"y":[{"c":2,"d":1}],"z":{"a":2,"b":1}}', Canon('{"z":{"b":1,"a":2},"y":[{"d":1,"c":2}]}'),
    'canonical: nested objects are sorted');
  CheckEqualsStr('[4.5,0.002,1e+30,1e-27,100,0,0,-1.5,1e+21,100000000000000000000,123456789]',
    Canon('[4.50,2e-3,1E30,1e-27,100,0,-0,-1.5,1e21,1e20,123456789]'),
    'canonical: ECMAScript number formatting');
  CheckEqualsStr('"\u000f\nA''B\"\\\\\"/"', Canon('"\u000f\u000aA''B\u0022\u005c\\\"/"'),
    'canonical: minimal string escaping');
  CheckEqualsStr('"/"', Canon('"\/"'), 'canonical: the solidus is not escaped');
  CheckEqualsStr('[true,false,null]', Canon(' [ true , false , null ] '), 'canonical: no whitespace, literals');
  CheckEqualsStr('{"a":{},"b":[]}', Canon('{"b":[],"a":{}}'), 'canonical: empty containers');
  CheckEqualsStr('{"literals":[null,true,false],"numbers":[333333333.5,1e+30,4.5,0.002,1e-27],"string":"\u000f\nA''B\"\\\\\"/"}',
    Canon('{"numbers":[333333333.5,1E30,4.50,2e-3,1e-27],"string":"\u000f\u000aA''B\u0022\u005c\\\"/","literals":[null,true,false]}'),
    'canonical: the RFC 8785 sample (with simpler numbers)');
  CheckEqualsStr('9007199254740992', Canon('9007199254740993'), 'canonical: numbers follow IEEE 754 doubles');
  CheckEqualsStr('1.5', Canon('1.50'), 'canonical ignores OriginalNumbers');
  CheckEqualsInt($1F600, FirstKeyCodePoint(Canon('{"\uffff":1,"\ud83d\ude00":2}')),
    'canonical: UTF-16 code unit order of member names');
  O := DefaultJSONWriteOptions;
  O.Canonical := True;
  O.Indent := 4;
  O.EscapeNonAscii := True;
  CheckEqualsStr('{"a":[1,2],"b":1}', Emit('{"b":1.0,"a":[1,2]}', O), 'canonical overrides Indent and the other options');
  Halt(EndSuite);
end.
