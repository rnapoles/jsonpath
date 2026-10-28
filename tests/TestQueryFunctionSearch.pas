{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryFunctionSearch;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '["abc","abcd","xabc","zzz"]';
  Cls =
    '["xyz","k","kilo","a"]';

begin
  BeginSuite('Query: search() function');
  CheckEqualsStr('["abc","abcd","xabc"]', QueryValues(Doc, '$[?search(@, "a.c")]'), 'search finds substrings');
  CheckEqualsStr('["k","kilo"]', QueryValues(Cls, '$[?search(@, "[jk]")]'), 'search with a character class');
  CheckEqualsStr('["zzz"]', QueryValues(Doc, '$[?search(@, "z{3}")]'), 'search with a quantifier');
  Halt(EndSuite);
end.
