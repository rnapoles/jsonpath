{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestRegexQuantifiers;

{$APPTYPE CONSOLE}

uses
  TestSupport;

begin
  BeginSuite('Regex: quantifiers');
  Check(RegexMatches('ab*c', 'ac'), 'star matches zero');
  Check(RegexMatches('ab*c', 'abbbc'), 'star matches many');
  Check(not RegexMatches('ab+c', 'ac'), 'plus needs one');
  Check(RegexMatches('ab+c', 'abbc'), 'plus matches many');
  Check(RegexMatches('ab?c', 'ac'), 'question matches zero');
  Check(RegexMatches('ab?c', 'abc'), 'question matches one');
  Check(not RegexMatches('ab?c', 'abbc'), 'question rejects two');
  Check(RegexMatches('a{3}', 'aaa'), 'exact count');
  Check(not RegexMatches('a{3}', 'aa'), 'exact count rejects fewer');
  Check(RegexMatches('a{2,}', 'aaaaa'), 'open range');
  Check(not RegexMatches('a{2,}', 'a'), 'open range rejects fewer');
  Check(RegexMatches('a{1,2}', 'aa'), 'bounded range accepts the maximum');
  Check(not RegexMatches('a{1,2}', 'aaa'), 'bounded range rejects more');
  Check(RegexIsInvalid('a{2,1}'), 'reversed range is invalid');
  Check(RegexIsInvalid('a**'), 'double quantifier is invalid');
  Check(RegexIsInvalid('*a'), 'quantifier without atom is invalid');
  Check(RegexIsInvalid('a{2'), 'unterminated quantifier is invalid');
  Halt(EndSuite);
end.
