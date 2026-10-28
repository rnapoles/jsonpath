{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryMultipleSelectors;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '["a","b","c","d","e","f","g"]';

begin
  BeginSuite('Query: multiple selectors in one bracket');
  CheckEqualsStr('["a","d"]', QueryValues(Doc, '$[0, 3]'), 'two indices');
  CheckEqualsStr('["a","b","f"]', QueryValues(Doc, '$[0:2, 5]'), 'slice and index');
  CheckEqualsStr('["a","a"]', QueryValues(Doc, '$[0, 0]'), 'duplicate indices select twice');
  CheckEqualsStr('["d","a"]', QueryValues(Doc, '$[3, 0]'), 'selectors apply in written order');
  Halt(EndSuite);
end.
