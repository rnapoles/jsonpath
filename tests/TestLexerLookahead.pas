{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestLexerLookahead;

{$APPTYPE CONSOLE}

uses
  TestSupport, JSONPathLexer;

var
  L: TJSONPathLexer;
  M: Integer;

begin
  BeginSuite('Lexer: lookahead primitives');
  L := TJSONPathLexer.Create('$.ab');
  try
  CheckEqualsStr('$', L.PeekChar, 'PeekChar returns the first character');
  CheckEqualsStr('$', L.PeekChar, 'PeekChar does not consume');
  CheckEqualsStr('$', L.ConsumeChar, 'ConsumeChar returns the character');
  CheckEqualsStr('.', L.PeekChar, 'ConsumeChar advances');
  CheckEqualsStr('a', L.PeekCharAt(1), 'PeekCharAt looks ahead');
  Check(not L.MatchToken('x'), 'MatchToken fails on mismatch');
  CheckEqualsStr('.', L.PeekChar, 'a failed MatchToken does not consume');
  Check(L.MatchToken('.a'), 'MatchToken succeeds on a prefix');
  CheckEqualsStr('b', L.PeekChar, 'a successful MatchToken consumes');
  Check(not L.IsAtEnd, 'not at end before the last character');
  L.ConsumeChar;
  Check(L.IsAtEnd, 'at end after the last character');
  Check(L.PeekChar = #0, 'PeekChar returns #0 at the end');
  Check(L.PeekCharAt(5) = #0, 'PeekCharAt returns #0 past the end');
  finally
  L.Free;
  end;
  L := TJSONPathLexer.Create('abc');
  try
  M := L.Mark;
  L.ConsumeChar;
  L.ConsumeChar;
  L.Reset(M);
  CheckEqualsStr('a', L.PeekChar, 'Reset restores a saved mark');
  finally
  L.Free;
  end;
  Halt(EndSuite);
end.
