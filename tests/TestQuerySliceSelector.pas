{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQuerySliceSelector;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '["a","b","c","d","e","f","g"]';
  Obj =
    '{"a":1}';

begin
  BeginSuite('Query: array slice selector');
  CheckEqualsStr('["b","c"]', QueryValues(Doc, '$[1:3]'), 'slice with default step');
  CheckEqualsStr('$[1];$[2]', QueryPaths(Doc, '$[1:3]'), 'paths of slice with default step');
  CheckEqualsStr('["f","g"]', QueryValues(Doc, '$[5:]'), 'slice with open end');
  CheckEqualsStr('["a","b"]', QueryValues(Doc, '$[:2]'), 'slice with open start');
  CheckEqualsStr('["f","g"]', QueryValues(Doc, '$[-2:]'), 'slice with negative start');
  CheckEqualsStr('["b","d"]', QueryValues(Doc, '$[1:5:2]'), 'slice with step 2');
  CheckEqualsStr('$[1];$[3]', QueryPaths(Doc, '$[1:5:2]'), 'paths of slice with step 2');
  CheckEqualsStr('["f","d"]', QueryValues(Doc, '$[5:1:-2]'), 'slice with negative step');
  CheckEqualsStr('["g","f","e","d","c","b","a"]', QueryValues(Doc, '$[::-1]'), 'full reverse slice');
  CheckEqualsStr('["a","c","e","g"]', QueryValues(Doc, '$[::2]'), 'every other element');
  CheckEqualsStr('[]', QueryValues(Doc, '$[::0]'), 'step of zero selects nothing');
  CheckEqualsStr('[]', QueryValues(Doc, '$[10:20]'), 'out-of-range slice is empty');
  CheckEqualsStr('[]', QueryValues(Obj, '$[0:1]'), 'slice on an object is empty');
  Halt(EndSuite);
end.
