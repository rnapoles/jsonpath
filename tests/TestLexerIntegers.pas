{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestLexerIntegers;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils, JSONPathLexer;

function ScanIntOf(const S: string): Int64;
var
  L: TJSONPathLexer;
begin
  L := TJSONPathLexer.Create(S);
  try
    Result := L.ScanInt('int');
  finally
    L.Free;
  end;
end;

function ScanIntFails(const S: string): Boolean;
begin
  Result := False;
  try
    ScanIntOf(S);
  except
    on EJSONPathParseException do
      Result := True;
  end;
end;

begin
  BeginSuite('Lexer: integer literals');
  CheckEqualsInt(42, ScanIntOf('42'), 'plain integer');
  CheckEqualsInt(-17, ScanIntOf('-17'), 'negative integer');
  CheckEqualsInt(0, ScanIntOf('0'), 'zero');
  CheckEqualsInt(9007199254740991, ScanIntOf('9007199254740991'), 'largest I-JSON integer');
  CheckEqualsInt(-9007199254740991, ScanIntOf('-9007199254740991'), 'smallest I-JSON integer');
  Check(ScanIntFails('9007199254740992'), 'one above the range is rejected');
  Check(ScanIntFails('99999999999999999999'), 'very long integers are rejected');
  Check(ScanIntFails('01'), 'leading zero is rejected');
  Check(ScanIntFails('-0'), 'negative zero is rejected');
  Check(ScanIntFails('-'), 'lone minus is rejected');
  Check(ScanIntFails('x'), 'non-digit is rejected');
  Halt(EndSuite);
end.
