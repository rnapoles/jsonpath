{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryFunctionCount;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '[{"a":1,"b":2},{"a":1},[1,2],[1]]';

begin
  BeginSuite('Query: count() function');
  CheckEqualsStr('[{"a":1,"b":2},[1,2]]', QueryValues(Doc, '$[?count(@.*) == 2]'), 'count of wildcard children');
  CheckEqualsStr('[{"a":1,"b":2},{"a":1}]', QueryValues(Doc, '$[?count(@.a) == 1]'), 'count of a singular query');
  CheckEqualsStr('[{"a":1,"b":2},{"a":1},[1,2],[1]]', QueryValues(Doc, '$[?count(@.zzz) == 0]'), 'count of zero nodes');
  Halt(EndSuite);
end.
