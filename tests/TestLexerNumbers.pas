{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestLexerNumbers;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils, JSONPathLexer;

function ScanNumberOf(const S: string): Double;
var
  L: TJSONPathLexer;
begin
  L := TJSONPathLexer.Create(S);
  try
    Result := L.ScanNumberLiteral;
  finally
    L.Free;
  end;
end;

function NumberFails(const S: string): Boolean;
begin
  Result := False;
  try
    ScanNumberOf(S);
  except
    on EJSONPathParseException do
      Result := True;
  end;
end;

begin
  BeginSuite('Lexer: number literals');
  Check(ScanNumberOf('1') = 1, 'integer');
  Check(ScanNumberOf('-1.5') = -1.5, 'negative fraction');
  Check(ScanNumberOf('1e3') = 1000, 'exponent');
  Check(Abs(ScanNumberOf('1E-2') - 0.01) < 1E-15, 'negative exponent');
  Check(ScanNumberOf('2.5e+1') = 25, 'explicit plus in exponent');
  Check(ScanNumberOf('-0') = 0, 'negative zero is a valid number');
  Check(NumberFails('01'), 'leading zero is rejected');
  Check(NumberFails('1.'), 'missing fraction digits are rejected');
  Check(NumberFails('.5'), 'missing integer part is rejected');
  Check(NumberFails('1e'), 'missing exponent digits are rejected');
  Check(NumberFails('-'), 'lone minus is rejected');
  Halt(EndSuite);
end.
