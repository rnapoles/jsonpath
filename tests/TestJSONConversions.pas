{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestJSONConversions;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils, JSONPathJSON;

{ letters of every Is* property that is True: N B D I S A O }
function Flags(const AText: string): string;
var
  V: TJSONValue;
begin
  V := ParseJSON(AText);
  try
    Result := '';
    if V.IsNull then Result := Result + 'N';
    if V.IsBoolean then Result := Result + 'B';
    if V.IsNumber then Result := Result + 'D';
    if V.IsInteger then Result := Result + 'I';
    if V.IsString then Result := Result + 'S';
    if V.IsArray then Result := Result + 'A';
    if V.IsObject then Result := Result + 'O';
  finally
    V.Free;
  end;
end;

function AsBool(const AText: string): Boolean;
var
  V: TJSONValue;
begin
  V := ParseJSON(AText);
  try
    Result := V.AsBoolean;
  finally
    V.Free;
  end;
end;

function AsNum(const AText: string): Double;
var
  V: TJSONValue;
begin
  V := ParseJSON(AText);
  try
    Result := V.AsNumber;
  finally
    V.Free;
  end;
end;

function AsInt(const AText: string): Int64;
var
  V: TJSONValue;
begin
  V := ParseJSON(AText);
  try
    Result := V.AsInteger;
  finally
    V.Free;
  end;
end;

function AsStr(const AText: string): string;
var
  V: TJSONValue;
begin
  V := ParseJSON(AText);
  try
    Result := V.AsString;
  finally
    V.Free;
  end;
end;

begin
  BeginSuite('JSON: Is* and As* properties');

  CheckEqualsStr('N', Flags('null'), 'null');
  CheckEqualsStr('B', Flags('true'), 'boolean');
  CheckEqualsStr('DI', Flags('3'), 'integer number');
  CheckEqualsStr('DI', Flags('3.0'), 'integer-valued float is an integer');
  CheckEqualsStr('D', Flags('3.5'), 'fractional number is not an integer');
  CheckEqualsStr('D', Flags('1e30'), 'a number beyond Int64 is not an integer');
  CheckEqualsStr('S', Flags('"3"'), 'a numeric string is still a string');
  CheckEqualsStr('A', Flags('[]'), 'array');
  CheckEqualsStr('O', Flags('{}'), 'object');

  Check(not AsBool('null'), 'AsBoolean: null is False');
  Check(AsBool('true'), 'AsBoolean: true');
  Check(not AsBool('false'), 'AsBoolean: false');
  Check(not AsBool('0'), 'AsBoolean: 0 is False');
  Check(not AsBool('0.0'), 'AsBoolean: 0.0 is False');
  Check(AsBool('1'), 'AsBoolean: 1 is True');
  Check(AsBool('-2.5'), 'AsBoolean: any non-zero number is True');
  Check(not AsBool('""'), 'AsBoolean: empty string is False');
  Check(AsBool('"x"'), 'AsBoolean: non-empty string is True');
  Check(AsBool('"false"'), 'AsBoolean: only the empty string is False');
  Check(not AsBool('[]'), 'AsBoolean: empty array is False');
  Check(AsBool('[0]'), 'AsBoolean: non-empty array is True');
  Check(not AsBool('{}'), 'AsBoolean: empty object is False');
  Check(AsBool('{"a":null}'), 'AsBoolean: non-empty object is True');

  Check(AsNum('null') = 0, 'AsNumber: null is 0');
  Check(AsNum('true') = 1, 'AsNumber: true is 1');
  Check(AsNum('false') = 0, 'AsNumber: false is 0');
  Check(AsNum('5.5') = 5.5, 'AsNumber: a number is itself');
  Check(AsNum('"12.5"') = 12.5, 'AsNumber: numeric strings are parsed');
  Check(AsNum('" 7 "') = 7, 'AsNumber: surrounding blanks are ignored');
  Check(AsNum('"1e3"') = 1000, 'AsNumber: exponents are parsed');
  Check(AsNum('"abc"') = 0, 'AsNumber: other strings give 0');
  Check(AsNum('""') = 0, 'AsNumber: the empty string gives 0');
  Check(AsNum('[1]') = 0, 'AsNumber: arrays give 0');
  Check(AsNum('{"a":1}') = 0, 'AsNumber: objects give 0');

  CheckEqualsInt(0, AsInt('null'), 'AsInteger: null is 0');
  CheckEqualsInt(1, AsInt('true'), 'AsInteger: true is 1');
  CheckEqualsInt(7, AsInt('7.9'), 'AsInteger truncates toward zero');
  CheckEqualsInt(-7, AsInt('-7.9'), 'AsInteger truncates negative numbers toward zero');
  CheckEqualsInt(42, AsInt('"42"'), 'AsInteger: numeric strings are parsed');
  CheckEqualsInt(3, AsInt('"3.9"'), 'AsInteger: fractional strings are truncated');
  CheckEqualsInt(0, AsInt('1e30'), 'AsInteger: out-of-range numbers give 0');
  CheckEqualsInt(0, AsInt('"x"'), 'AsInteger: non-numeric strings give 0');
  CheckEqualsInt(0, AsInt('[1]'), 'AsInteger: arrays give 0');
  CheckEqualsInt(9007199254740991, AsInt('9007199254740991'), 'AsInteger keeps large exact integers');

  CheckEqualsStr('', AsStr('null'), 'AsString: null is empty');
  CheckEqualsStr('true', AsStr('true'), 'AsString: true');
  CheckEqualsStr('false', AsStr('false'), 'AsString: false');
  CheckEqualsStr('42', AsStr('42'), 'AsString: integers have no decimals');
  CheckEqualsStr('1.5', AsStr('1.5'), 'AsString: fractions use a dot');
  CheckEqualsStr('hi', AsStr('"hi"'), 'AsString: a string is itself');
  CheckEqualsStr('[1,"a"]', AsStr('[1,"a"]'), 'AsString: arrays become compact JSON');
  CheckEqualsStr('{"a":null}', AsStr('{"a":null}'), 'AsString: objects become compact JSON');
  Halt(EndSuite);
end.
