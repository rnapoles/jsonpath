{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryWildcardSelector;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '{"o": {"j": 1, "k": 2}, "a": [5, 3]}';

begin
  BeginSuite('Query: wildcard selector');
  CheckEqualsStr('[{"j":1,"k":2},[5,3]]', QueryValues(Doc, '$[*]'), 'wildcard on the root object');
  CheckEqualsStr('$[''o''];$[''a'']', QueryPaths(Doc, '$[*]'), 'paths of wildcard on the root object');
  CheckEqualsStr('[1,2]', QueryValues(Doc, '$.o[*]'), 'wildcard on an object selects member values');
  CheckEqualsStr('$[''o''][''j''];$[''o''][''k'']', QueryPaths(Doc, '$.o[*]'), 'paths of wildcard on an object');
  CheckEqualsStr('[5,3]', QueryValues(Doc, '$.a[*]'), 'wildcard on an array selects elements');
  CheckEqualsStr('$[''a''][0];$[''a''][1]', QueryPaths(Doc, '$.a[*]'), 'paths of wildcard on an array');
  CheckEqualsStr('[5,3]', QueryValues(Doc, '$.a.*'), 'dot wildcard equals bracket wildcard');
  CheckEqualsStr('[1,2,1,2]', QueryValues(Doc, '$.o[*, *]'), 'duplicate wildcards select twice');
  CheckEqualsStr('[]', QueryValues(Doc, '$.a[0][*]'), 'wildcard on a scalar is empty');
  Halt(EndSuite);
end.
