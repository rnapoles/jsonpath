{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryNormalizedPaths;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '{"a":{"b":[1,2,3]}}';
  Five =
    '[1,2,3,4,5]';

begin
  BeginSuite('Query: normalized paths');
  CheckEqualsStr('$[''a'']', QueryPaths(Doc, '$.a'), 'member access');
  CheckEqualsStr('$[''a''][''b''][1]', QueryPaths(Doc, '$.a.b[1]'), 'nested member and index');
  CheckEqualsStr('$[''a''][''b''][1];$[''a''][''b''][2]', QueryPaths(Doc, '$.a.b[1:3]'), 'slice results are individual indices');
  CheckEqualsStr('$[2]', QueryPaths(Five, '$[-3]'), 'negative index in a five element array');
  CheckEqualsStr('$[0];$[1]', QueryPaths(Five, '$[0:2]'), 'wildcard on array');
  Halt(EndSuite);
end.
