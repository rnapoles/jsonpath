{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryNameSelector;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '{"o": {"j j": {"k.k": 3}}, "''": {"@": 2}}';

begin
  BeginSuite('Query: name selectors');
  CheckEqualsStr('[{"k.k":3}]', QueryValues(Doc, '$.o[''j j'']'), 'single-quoted name with space');
  CheckEqualsStr('$[''o''][''j j'']', QueryPaths(Doc, '$.o[''j j'']'), 'path of single-quoted name');
  CheckEqualsStr('[3]', QueryValues(Doc, '$.o[''j j''][''k.k'']'), 'nested member via brackets');
  CheckEqualsStr('[3]', QueryValues(Doc, '$.o["j j"]["k.k"]'), 'double-quoted names select the same node');
  CheckEqualsStr('$[''o''][''j j''][''k.k'']', QueryPaths(Doc, '$.o["j j"]["k.k"]'), 'normalized path uses single quotes for double-quoted query');
  CheckEqualsStr('[2]', QueryValues(Doc, '$["''"]["@"]'), 'unusual member names');
  CheckEqualsStr('$[''\''''][''@'']', QueryPaths(Doc, '$["''"]["@"]'), 'quote in member name is escaped in the normalized path');
  CheckEqualsStr('[]', QueryValues(Doc, '$.nope'), 'missing member gives an empty result');
  CheckEqualsStr('[]', QueryValues(Doc, '$.o[''j j''][''k.k''].z'), 'name selector on a number gives an empty result');
  CheckEqualsStr('[{"j j":{"k.k":3}}]', QueryValues(Doc, '$.o'), 'shorthand and bracket forms are equivalent');
  Halt(EndSuite);
end.
