{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestLexerNames;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils, JSONPathLexer;

var
  L: TJSONPathLexer;
  Failed: Boolean;

begin
  BeginSuite('Lexer: member names and function names');
  L := TJSONPathLexer.Create('abc_1.x');
  try
  CheckEqualsStr('abc_1', L.ScanNameShorthand, 'name stops at the dot');
  CheckEqualsStr('.', L.PeekChar, 'dot is left for the parser');
  finally
  L.Free;
  end;
  Check(TJSONPathLexer.IsNameFirst('_'), 'underscore starts a name');
  Check(TJSONPathLexer.IsNameFirst('Z'), 'uppercase letter starts a name');
  Check(not TJSONPathLexer.IsNameFirst('1'), 'digit cannot start a name');
  Check(TJSONPathLexer.IsNameChar('1'), 'digit can continue a name');
  Check(not TJSONPathLexer.IsNameChar('-'), 'hyphen cannot continue a name');
  L := TJSONPathLexer.Create('match_2(');
  try
  CheckEqualsStr('match_2', L.ScanFunctionName, 'function name with underscore and digit');
  finally
  L.Free;
  end;
  L := TJSONPathLexer.Create('Match(');
  try
  Failed := False;
  try
    L.ScanFunctionName;
  except
    on EJSONPathParseException do
      Failed := True;
  end;
  Check(Failed, 'function name must start with a lowercase letter');
  finally
  L.Free;
  end;
  Halt(EndSuite);
end.
