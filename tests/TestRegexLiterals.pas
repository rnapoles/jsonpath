{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestRegexLiterals;

{$APPTYPE CONSOLE}

uses
  TestSupport;

begin
  BeginSuite('Regex: literals and dot');
  Check(RegexMatches('abc', 'abc'), 'literal string matches itself');
  Check(not RegexMatches('abc', 'abd'), 'literal mismatch');
  Check(not RegexMatches('abc', 'abcd'), 'match is anchored at both ends');
  Check(RegexMatches('a.c', 'axc'), 'dot matches any character');
  Check(not RegexMatches('a.c', 'a'#10'c'), 'dot does not match line feed');
  Check(not RegexMatches('a.c', 'a'#13'c'), 'dot does not match carriage return');
  Check(RegexMatches('a\.c', 'a.c'), 'escaped dot is literal');
  Check(not RegexMatches('a\.c', 'abc'), 'escaped dot does not match other characters');
  Check(RegexMatches('^a$', '^a$'), 'caret and dollar are ordinary characters');
  Check(RegexMatches('', ''), 'empty pattern matches the empty string');
  Check(RegexMatches('a\nb', 'a'#10'b'), 'escaped newline');
  Halt(EndSuite);
end.
