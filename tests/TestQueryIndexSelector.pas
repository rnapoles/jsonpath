{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryIndexSelector;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '["a","b"]';
  Obj =
    '{"a":1}';

begin
  BeginSuite('Query: array index selector');
  CheckEqualsStr('["b"]', QueryValues(Doc, '$[1]'), 'positive index');
  CheckEqualsStr('$[1]', QueryPaths(Doc, '$[1]'), 'path of positive index');
  CheckEqualsStr('["a"]', QueryValues(Doc, '$[-2]'), 'negative index counts from the end');
  CheckEqualsStr('$[0]', QueryPaths(Doc, '$[-2]'), 'negative index is normalized in the path');
  CheckEqualsStr('[]', QueryValues(Doc, '$[2]'), 'index past the end is empty');
  CheckEqualsStr('[]', QueryValues(Doc, '$[-3]'), 'negative index past the start is empty');
  CheckEqualsStr('[]', QueryValues(Obj, '$[0]'), 'index on an object is empty');
  Halt(EndSuite);
end.
