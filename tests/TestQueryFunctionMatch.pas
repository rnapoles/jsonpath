{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryFunctionMatch;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '["abc","abcd","xabc"]';
  Nl =
    '["a\nb","axb"]';
  Mixed =
    '[1,"abc",null]';
  Alt =
    '["a","b","c","ab"]';
  Pat =
    '[{"s":"abc","p":"a.c"},{"s":"abc","p":"b"}]';

begin
  BeginSuite('Query: match() function');
  CheckEqualsStr('["abc"]', QueryValues(Doc, '$[?match(@, "a.c")]'), 'match requires the whole string to match');
  CheckEqualsStr('["axb"]', QueryValues(Nl, '$[?match(@, "a.b")]'), 'dot does not match a newline');
  CheckEqualsStr('["abc"]', QueryValues(Mixed, '$[?match(@, "abc")]'), 'non-string input never matches');
  CheckEqualsStr('["a","b"]', QueryValues(Alt, '$[?match(@, "a|b")]'), 'alternation inside match');
  CheckEqualsStr('[]', QueryValues(Doc, '$[?match(@, "[")]'), 'invalid pattern yields false');
  CheckEqualsStr('[{"s":"abc","p":"a.c"}]', QueryValues(Pat, '$[?match(@.s, @.p)]'), 'pattern may come from the document');
  CheckEqualsStr('[]', QueryValues(Doc, '$[?match(@, "\\p{L}+")]'), 'unsupported property escape yields false');
  Halt(EndSuite);
end.
