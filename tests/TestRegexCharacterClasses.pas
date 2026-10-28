{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestRegexCharacterClasses;

{$APPTYPE CONSOLE}

uses
  TestSupport;

begin
  BeginSuite('Regex: character classes');
  Check(RegexMatches('[a-c]', 'b'), 'range match');
  Check(not RegexMatches('[a-c]', 'd'), 'range mismatch');
  Check(RegexMatches('[^a-c]', 'd'), 'negated class');
  Check(not RegexMatches('[^a-c]', 'a'), 'negated class mismatch');
  Check(RegexMatches('[ax-z]', 'y'), 'multiple items');
  Check(RegexMatches('[-a]', '-'), 'leading hyphen is literal');
  Check(RegexMatches('[a-]', '-'), 'trailing hyphen is literal');
  Check(RegexMatches('[\]]', ']'), 'escaped bracket inside class');
  Check(RegexMatches('[0-9]+', '2024'), 'class repeated');
  Check(RegexIsInvalid('[]'), 'empty class is invalid');
  Check(RegexIsInvalid('[a'), 'unterminated class is invalid');
  Check(RegexIsInvalid('[z-a]'), 'reversed range is invalid');
  Halt(EndSuite);
end.
