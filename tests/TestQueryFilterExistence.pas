{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryFilterExistence;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '{"a":[3,5,1,2,4,6,{"b":"j"},{"b":"k"},{"b":{}},{"b":"kilo"}],"o":{"p":1,"q":2,"r":3,"s":5,"t":{"u":6}},"e":"f"}';
  Store =
    '{"store":{"book":[{"category":"reference","author":"Nigel Rees","title":"Sayings of the Century","price":8.95},{"category":"fiction","author":"Evelyn Waugh","title":"Sword of Honour","price":12.99},{"category":"fiction","author":"Herman Melville","title":"Moby Dick","isbn":"0-553-21311-3","price":8.99},{"category":"fiction","author":"J. R. R. Tolkien","title":"The Lord of the Rings","isbn":"0-395-19395-8","price":22.99}],"bicycle":{"color":"red","price":399}}}';

begin
  BeginSuite('Query: filter existence tests');
  CheckEqualsStr('$[''a''][6];$[''a''][7];$[''a''][8];$[''a''][9]', QueryPaths(Doc, '$.a[?@.b]'), 'members that have b');
  CheckEqualsStr('$[''a''][0];$[''a''][1];$[''a''][2];$[''a''][3];$[''a''][4];$[''a''][5]', QueryPaths(Doc, '$.a[?!@.b]'), 'members that lack b');
  CheckEqualsStr('$[''a''];$[''o'']', QueryPaths(Doc, '$[?@.*]'), 'non-singular existence test selects non-empty containers');
  CheckEqualsStr('["Moby Dick","The Lord of the Rings"]', QueryValues(Store, '$..book[?@.isbn].title'), 'books with an isbn');
  CheckEqualsStr('[]', QueryValues(Doc, '$.e[?@]'), 'filter on a scalar parent selects nothing');
  Halt(EndSuite);
end.
