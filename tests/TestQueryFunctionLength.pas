{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryFunctionLength;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '["abc","ab",[1,2,3],{"a":1,"b":2,"c":3},3]';
  Uni =
    '["\u00e9","\ud83d\ude00","ab"]';

begin
  BeginSuite('Query: length() function');
  CheckEqualsStr('["abc",[1,2,3],{"a":1,"b":2,"c":3}]', QueryValues(Doc, '$[?length(@) == 3]'), 'length of strings, arrays and objects; numbers have no length');
  CheckEqualsInt(2, QueryCount(Uni, '$[?length(@) == 1]'), 'length counts Unicode scalar values, not bytes');
  Halt(EndSuite);
end.
