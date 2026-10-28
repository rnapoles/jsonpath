{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryDescendantSegment;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Store =
    '{"store":{"book":[{"category":"reference","author":"Nigel Rees","title":"Sayings of the Century","price":8.95},{"category":"fiction","author":"Evelyn Waugh","title":"Sword of Honour","price":12.99},{"category":"fiction","author":"Herman Melville","title":"Moby Dick","isbn":"0-553-21311-3","price":8.99},{"category":"fiction","author":"J. R. R. Tolkien","title":"The Lord of the Rings","isbn":"0-395-19395-8","price":22.99}],"bicycle":{"color":"red","price":399}}}';
  Scalar =
    '5';

begin
  BeginSuite('Query: descendant segment');
  CheckEqualsStr('["Nigel Rees","Evelyn Waugh","Herman Melville","J. R. R. Tolkien"]', QueryValues(Store, '$..author'), 'all authors anywhere');
  CheckEqualsStr('[8.95,12.99,8.99,22.99,399]', QueryValues(Store, '$.store..price'), 'prices within the store');
  CheckEqualsStr('$[''store''][''book''][0][''price''];$[''store''][''book''][1][''price''];$[''store''][''book''][2][''price''];$[''store''][''book''][3][''price''];$[''store''][''bicycle''][''price'']', QueryPaths(Store, '$..price'), 'paths of descendant prices');
  CheckEqualsStr('["Herman Melville"]', QueryValues(Store, '$..book[2].author'), 'descendant then index');
  CheckEqualsStr('[]', QueryValues(Store, '$..book[2].publisher'), 'descendant then missing member');
  CheckEqualsStr('["The Lord of the Rings"]', QueryValues(Store, '$..book[-1].title'), 'descendant then negative index');
  CheckEqualsInt(27, QueryCount(Store, '$..*'), 'descendant wildcard visits every value');
  CheckEqualsStr('[]', QueryValues(Scalar, '$..a'), 'descendant on a scalar document is empty');
  CheckEqualsStr('["red"]', QueryValues(Store, '$..[''color'']'), 'descendant with bracketed name');
  Halt(EndSuite);
end.
