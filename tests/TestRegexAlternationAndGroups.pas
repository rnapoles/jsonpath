{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestRegexAlternationAndGroups;

{$APPTYPE CONSOLE}

uses
  TestSupport;

begin
  BeginSuite('Regex: alternation and groups');
  Check(RegexMatches('a|b', 'a'), 'alternation first branch');
  Check(RegexMatches('a|b', 'b'), 'alternation second branch');
  Check(not RegexMatches('a|b', 'c'), 'alternation rejects others');
  Check(not RegexMatches('a|b', 'ab'), 'alternation is anchored as a whole');
  Check(RegexMatches('(ab)+', 'ababab'), 'group with quantifier');
  Check(not RegexMatches('(ab)+', 'aba'), 'group with quantifier rejects partial');
  Check(RegexMatches('x(a|b)y', 'xby'), 'alternation inside a group');
  Check(RegexMatches('a(b|)c', 'ac'), 'empty alternative');
  Check(RegexMatches('((a)(b))+', 'abab'), 'nested groups');
  Check(RegexIsInvalid('(a'), 'unbalanced open parenthesis');
  Check(RegexIsInvalid('a)'), 'unbalanced close parenthesis');
  Halt(EndSuite);
end.
