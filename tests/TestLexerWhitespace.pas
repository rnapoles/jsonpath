{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestLexerWhitespace;

{$APPTYPE CONSOLE}

uses
  TestSupport, JSONPathLexer;

var
  L: TJSONPathLexer;

begin
  BeginSuite('Lexer: whitespace skipping');
  L := TJSONPathLexer.Create(' '#9#10#13'x y');
  try
  L.SkipWhitespace;
  CheckEqualsStr('x', L.PeekChar, 'space, tab, LF and CR are whitespace');
  L.ConsumeChar;
  L.SkipWhitespace;
  CheckEqualsStr('y', L.PeekChar, 'SkipWhitespace stops at the next token');
  finally
  L.Free;
  end;
  L := TJSONPathLexer.Create(#12'x');
  try
  L.SkipWhitespace;
  Check(L.PeekChar = #12, 'form feed is not JSONPath whitespace');
  finally
  L.Free;
  end;
  Halt(EndSuite);
end.
