{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestJSONNumbersLossless;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils, JSONPathCommon, JSONPathJSON;

function Same(const A, B: string): Boolean;
var
  VA, VB: TJSONValue;
begin
  VA := ParseJSON(A);
  try
    VB := ParseJSON(B);
    try
      Result := JSONEquals(VA, VB);
    finally
      VB.Free;
    end;
  finally
    VA.Free;
  end;
end;

function Compare(const A, B: string): Integer;
var
  VA, VB: TJSONValue;
begin
  VA := ParseJSON(A);
  try
    VB := ParseJSON(B);
    try
      Result := JSONNumberCompare(VA, VB);
    finally
      VB.Free;
    end;
  finally
    VA.Free;
  end;
end;

function Exact64(const T: string): Boolean;
var
  V: TJSONValue;
begin
  V := ParseJSON(T);
  try
    Result := V.IsExactInt64;
  finally
    V.Free;
  end;
end;

function TryInt(const T: string; out AValue: Int64): Boolean;
var
  V: TJSONValue;
begin
  V := ParseJSON(T);
  try
    Result := V.TryGetInt64(AValue);
  finally
    V.Free;
  end;
end;

function DecimalOf(const T: string): string;
var
  V: TJSONValue;
  U: Int64;
  S: Integer;
begin
  V := ParseJSON(T);
  try
    if V.TryGetDecimal(U, S) then
      Result := IntToStr(U) + '/' + IntToStr(S)
    else
      Result := 'none';
  finally
    V.Free;
  end;
end;

function CentsOf(const T: string): Int64;
var
  V: TJSONValue;
begin
  V := ParseJSON(T);
  try
    Result := Round(V.AsCurrency * 10000);
  finally
    V.Free;
  end;
end;

function Normalised(const T: string): string;
var
  V: TJSONValue;
  O: TJSONWriteOptions;
begin
  O := DefaultJSONWriteOptions;
  O.OriginalNumbers := False;
  V := ParseJSON(T);
  try
    Result := JSONToText(V, O);
  finally
    V.Free;
  end;
end;

function InvalidNumberText(const T: string): Boolean;
var
  V: TJSONValue;
begin
  Result := False;
  try
    V := NewJSONNumberText(T);
    V.Free;
  except
    on EJSONPathJSONError do
      Result := True;
  end;
end;

var
  V: TJSONValue;
  I: Int64;
  Raised: Boolean;
begin
  BeginSuite('JSON: lossless numbers');

  { the original text survives }
  CheckEqualsStr('1.0', JSONRoundTrip('1.0'), '1.0 is written back as 1.0');
  CheckEqualsStr('1', JSONRoundTrip('1'), '1 stays 1');
  CheckEqualsStr('1.50', JSONRoundTrip('1.50'), 'trailing zeros are kept');
  CheckEqualsStr('-0', JSONRoundTrip('-0'), 'negative zero is kept');
  CheckEqualsStr('1E2', JSONRoundTrip('1E2'), 'exponent notation is kept');
  CheckEqualsStr('12345678901234567890123', JSONRoundTrip('12345678901234567890123'),
    'integers beyond Int64 are kept');
  CheckEqualsStr('0.1000000000000000055511151231257827', JSONRoundTrip('0.1000000000000000055511151231257827'),
    'long decimals are kept');
  CheckEqualsStr('[1,1.0,1.00]', JSONRoundTrip('[1,1.0,1.00]'), 'numbers inside containers are kept');

  { equality is by value, exact when possible }
  Check(Same('1', '1.0'), '1 equals 1.0');
  Check(Same('1.50', '1.5'), '1.50 equals 1.5');
  Check(Same('0.1', '0.10'), '0.1 equals 0.10');
  Check(Same('1e2', '100'), 'an exponent literal equals the integer');
  Check(not Same('9007199254740993', '9007199254740992'), 'integers above 2^53 are compared exactly');
  Check(not Same('9223372036854775807', '9223372036854775806'), 'neighbouring 64-bit ids differ');
  Check(Same('9223372036854775807', '9223372036854775807'), 'identical 64-bit ids are equal');
  CheckEqualsInt(1, Compare('9007199254740993', '9007199254740992'), 'exact ordering of large integers');
  CheckEqualsInt(-1, Compare('-1', '1'), 'negative below positive');
  CheckEqualsInt(0, Compare('1.5', '1.50'), 'equal decimals');
  CheckEqualsInt(1, Compare('1e2', '99'), 'ordering falls back to Double for exponent literals');

  { exact Int64 }
  Check(Exact64('9223372036854775807'), 'the largest Int64 is exact');
  Check(Exact64('-9223372036854775808'), 'the smallest Int64 is exact');
  Check(not Exact64('9223372036854775808'), 'one above the range is not exact');
  Check(not Exact64('12345678901234567890'), 'a 20 digit integer is not exact');
  Check(not Exact64('1.0'), 'a decimal literal is not an integer literal');
  Check(not Exact64('1e2'), 'an exponent literal is not exact');
  Check(TryInt('9223372036854775807', I) and (I = High(Int64)), 'TryGetInt64 returns the largest Int64');
  Check(TryInt('-9223372036854775808', I) and (I = Low(Int64)), 'TryGetInt64 returns the smallest Int64');
  Check(TryInt('1.0', I) and (I = 1), 'TryGetInt64 accepts integral decimals');
  Check(TryInt('12.50', I) = False, 'TryGetInt64 rejects fractions');
  Check(TryInt('1e2', I) and (I = 100), 'TryGetInt64 falls back to integral Doubles');
  Check(not TryInt('9223372036854775808', I), 'TryGetInt64 rejects numbers beyond Int64');
  V := ParseJSON('9223372036854775807');
  try
    Check(V.AsInteger = High(Int64), 'AsInteger is exact for 64-bit ids');
    Check(V.IsInteger, 'IsInteger is true for 64-bit ids');
  finally
    V.Free;
  end;

  { decimals and money }
  CheckEqualsStr('1999/2', DecimalOf('19.99'), 'TryGetDecimal 19.99');
  CheckEqualsStr('5/0', DecimalOf('5'), 'TryGetDecimal of an integer');
  CheckEqualsStr('-5/2', DecimalOf('-0.05'), 'TryGetDecimal keeps the sign');
  CheckEqualsStr('0/2', DecimalOf('0.00'), 'TryGetDecimal of 0.00');
  CheckEqualsStr('none', DecimalOf('1e2'), 'exponent literals have no decimal form');
  CheckEqualsStr('none', DecimalOf('0.1234567890123456789'), 'more than 18 decimals have no decimal form');
  CheckEqualsInt(199900, CentsOf('19.99'), 'AsCurrency is exact for 19.99');
  CheckEqualsInt(1, CentsOf('0.0001'), 'AsCurrency keeps four decimals');
  CheckEqualsInt(-50000, CentsOf('-5'), 'AsCurrency of an integer');
  CheckEqualsInt(123457, CentsOf('12.34567'), 'AsCurrency rounds beyond four decimals');

  { numbers that were not parsed }
  V := NewJSONInt64(High(Int64));
  try
    CheckEqualsStr('9223372036854775807', V.NumberText, 'NewJSONInt64 text');
    CheckEqualsStr('9223372036854775807', JSONToText(V), 'NewJSONInt64 is written exactly');
    Check(V.IsExactInt64, 'NewJSONInt64 is exact');
  finally
    V.Free;
  end;
  V := NewJSONDecimal(1999, 2);
  try
    CheckEqualsStr('19.99', V.NumberText, 'NewJSONDecimal text');
    Check(Abs(V.NumberValue - 19.99) < 1E-12, 'NewJSONDecimal also has a Double value');
  finally
    V.Free;
  end;
  V := NewJSONDecimal(-5, 2);
  CheckEqualsStr('-0.05', V.NumberText, 'NewJSONDecimal pads with zeros');
  V.Free;
  V := NewJSONDecimal(5, 0);
  CheckEqualsStr('5', V.NumberText, 'NewJSONDecimal with scale 0');
  V.Free;
  V := NewJSONDecimal(7, 3);
  CheckEqualsStr('0.007', V.NumberText, 'NewJSONDecimal 0.007');
  V.Free;
  Raised := False;
  try
    NewJSONDecimal(1, 19).Free;
  except
    on EJSONPathJSONError do
      Raised := True;
  end;
  Check(Raised, 'a decimal scale above 18 is rejected');

  V := NewJSONNumberText('12345678901234567890123');
  try
    CheckEqualsStr('12345678901234567890123', JSONToText(V), 'NewJSONNumberText keeps arbitrary text');
    Check(V.NumberValue > 1E22, 'NewJSONNumberText also has a Double value');
  finally
    V.Free;
  end;
  Check(InvalidNumberText(''), 'empty text is not a number');
  Check(InvalidNumberText('01'), 'leading zeros are not allowed');
  Check(InvalidNumberText('1.'), 'a trailing dot is not allowed');
  Check(InvalidNumberText('.5'), 'a leading dot is not allowed');
  Check(InvalidNumberText('+1'), 'a plus sign is not allowed');
  Check(InvalidNumberText('1e'), 'an empty exponent is not allowed');
  Check(InvalidNumberText(' 1'), 'blanks are not allowed');
  Check(InvalidNumberText('abc'), 'words are not numbers');
  Check(InvalidNumberText('1e999'), 'values beyond Double are rejected');

  { assigning a Double discards the exact forms }
  V := NewJSONNumberText('1.50');
  try
    V.NumberValue := 2;
    CheckEqualsStr('2', V.NumberText, 'assigning NumberValue resets the text');
    Check(not V.IsExactInt64, 'assigning NumberValue resets the exact form');
  finally
    V.Free;
  end;
  V := ParseJSON('1.50');
  try
    CheckEqualsStr('1.50', V.AsString, 'AsString of a number is its original text');
  finally
    V.Free;
  end;

  { normalising writer }
  CheckEqualsStr('[1,100,1.5,9223372036854775807]', Normalised('[1.0,1e2,1.50,9223372036854775807]'),
    'OriginalNumbers=False normalises through Double but keeps exact integers');
  Halt(EndSuite);
end.
