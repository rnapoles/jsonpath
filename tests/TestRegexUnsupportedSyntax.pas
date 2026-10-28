{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestRegexUnsupportedSyntax;

{$APPTYPE CONSOLE}

uses
  TestSupport;

begin
  BeginSuite('Regex: unsupported or invalid syntax is rejected');
  Check(RegexIsInvalid('\d'), 'shorthand classes are not part of I-Regexp');
  Check(RegexIsInvalid('\p{L}'), 'unicode category escapes are unsupported here');
  Check(RegexIsInvalid('a+?b*?{'), 'lazy quantifiers are not part of I-Regexp');
  Check(RegexIsInvalid('{'), 'lone opening brace');
  Check(RegexIsInvalid(']'), 'lone closing bracket');
  Check(RegexIsInvalid('a\'), 'trailing backslash');
  Halt(EndSuite);
end.
