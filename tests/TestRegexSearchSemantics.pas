{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestRegexSearchSemantics;

{$APPTYPE CONSOLE}

uses
  TestSupport;

begin
  BeginSuite('Regex: substring search');
  Check(RegexSearches('b+', 'abbbc'), 'search finds a middle substring');
  Check(not RegexSearches('x', 'abc'), 'search fails when absent');
  Check(RegexSearches('[jk]', 'kilo'), 'search with a class');
  Check(RegexSearches('foo|bar', 'xxbarxx'), 'search with alternation');
  Check(RegexSearches('', 'abc'), 'search with empty pattern matches anything');
  Check(RegexSearches('z{3}', 'azzzb'), 'search with a bounded repeat');
  Check(not RegexSearches('z{3}', 'azzb'), 'search needs the full repeat');
  Halt(EndSuite);
end.
