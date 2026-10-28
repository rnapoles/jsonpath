{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryNullHandling;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '{"a":null,"b":[null],"c":[{}],"null":1}';

begin
  BeginSuite('Query: JSON null handling');
  CheckEqualsStr('[null]', QueryValues(Doc, '$.a'), 'null member value');
  CheckEqualsStr('$[''a'']', QueryPaths(Doc, '$.a'), 'path of null member');
  CheckEqualsStr('[]', QueryValues(Doc, '$.a[0]'), 'index into null is empty');
  CheckEqualsStr('[]', QueryValues(Doc, '$.a.d'), 'member of null is empty');
  CheckEqualsStr('[null]', QueryValues(Doc, '$.b[0]'), 'null array element');
  CheckEqualsStr('[null]', QueryValues(Doc, '$.b[*]'), 'wildcard returns null elements');
  CheckEqualsStr('[null]', QueryValues(Doc, '$.b[?@]'), 'existence test is true for null');
  CheckEqualsStr('[null]', QueryValues(Doc, '$.b[?@==null]'), 'comparison with null literal');
  CheckEqualsStr('[]', QueryValues(Doc, '$.c[?@.d==null]'), 'missing value is not equal to null');
  CheckEqualsStr('[1]', QueryValues(Doc, '$.null'), 'member named null');
  Halt(EndSuite);
end.
