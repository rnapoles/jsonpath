{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestLexerStringLiterals;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils, JSONPathCommon, JSONPathLexer;

function ScanStringOf(const S: string): string;
var
  L: TJSONPathLexer;
begin
  L := TJSONPathLexer.Create(S);
  try
    Result := L.ScanStringLiteral;
  finally
    L.Free;
  end;
end;

function StringScanFails(const S: string): Boolean;
begin
  Result := False;
  try
    ScanStringOf(S);
  except
    on EJSONPathParseException do
      Result := True;
  end;
end;

begin
  BeginSuite('Lexer: string literals');
  CheckEqualsStr('abc', ScanStringOf('''abc'''), 'single-quoted');
  CheckEqualsStr('abc', ScanStringOf('"abc"'), 'double-quoted');
  CheckEqualsStr('', ScanStringOf(''''''), 'empty string');
  CheckEqualsStr('a''b', ScanStringOf('"a''b"'), 'single quote inside double quotes');
  CheckEqualsStr('a''b', ScanStringOf('''a\''b'''), 'escaped single quote');
  CheckEqualsStr('a"b', ScanStringOf('"a\"b"'), 'escaped double quote');
  CheckEqualsStr('a'#10'b', ScanStringOf('''a\nb'''), 'newline escape');
  CheckEqualsStr('a'#9'b', ScanStringOf('''a\tb'''), 'tab escape');
  CheckEqualsStr('a\b', ScanStringOf('''a\\b'''), 'backslash escape');
  CheckEqualsStr('a/b', ScanStringOf('''a\/b'''), 'solidus escape');
  CheckEqualsStr('A', ScanStringOf('''\u0041'''), 'unicode escape');
  CheckEqualsStr('J', ScanStringOf('''\u004A'''), 'uppercase hex digits are accepted');
  CheckEqualsInt(1, CodePointLength(ScanStringOf('''\uD83D\uDE00''')), 'surrogate pair becomes one code point');
  Check(StringScanFails('''\uD83D'''), 'lone high surrogate is rejected');
  Check(StringScanFails('''\uDE00'''), 'lone low surrogate is rejected');
  Check(StringScanFails('''\uD83D\u0041'''), 'high surrogate followed by a non-surrogate is rejected');
  Check(StringScanFails('"a\''b"'), 'escaped single quote in a double-quoted string is rejected');
  Check(StringScanFails('''a\"b'''), 'escaped double quote in a single-quoted string is rejected');
  Check(StringScanFails('''abc'), 'unterminated string is rejected');
  Check(StringScanFails('''a'#1'b'''), 'raw control character is rejected');
  Check(StringScanFails('''\q'''), 'unknown escape is rejected');
  Check(StringScanFails('''\u12'''), 'short unicode escape is rejected');
  Halt(EndSuite);
end.
