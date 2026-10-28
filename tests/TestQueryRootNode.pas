{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryRootNode;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '{"k": "v"}';
  Arr =
    '[1,2]';

begin
  BeginSuite('Query: root node');
  CheckEqualsStr('[{"k":"v"}]', QueryValues(Doc, '$'), 'root query returns the whole document');
  CheckEqualsStr('$', QueryPaths(Doc, '$'), 'root query has the normalized path $');
  CheckEqualsStr('[[1,2]]', QueryValues(Arr, '$'), 'root query works on arrays');
  CheckEqualsStr('[42]', QueryValues('42', '$'), 'root query works on scalar documents');
  Halt(EndSuite);
end.
