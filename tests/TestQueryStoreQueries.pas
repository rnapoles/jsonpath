{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryStoreQueries;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Store =
    '{"store":{"book":[{"category":"reference","author":"Nigel Rees","title":"Sayings of the Century","price":8.95},{"category":"fiction","author":"Evelyn Waugh","title":"Sword of Honour","price":12.99},{"category":"fiction","author":"Herman Melville","title":"Moby Dick","isbn":"0-553-21311-3","price":8.99},{"category":"fiction","author":"J. R. R. Tolkien","title":"The Lord of the Rings","isbn":"0-395-19395-8","price":22.99}],"bicycle":{"color":"red","price":399}}}';

begin
  BeginSuite('Query: classic store examples');
  CheckEqualsStr('["Nigel Rees","Evelyn Waugh","Herman Melville","J. R. R. Tolkien"]', QueryValues(Store, '$.store.book[*].author'), 'authors of all books');
  CheckEqualsStr('$[''store''][''book''];$[''store''][''bicycle'']', QueryPaths(Store, '$.store.*'), 'everything in the store');
  CheckEqualsStr('[8.95,12.99,8.99,22.99,399]', QueryValues(Store, '$.store..price'), 'prices of everything in the store');
  CheckEqualsStr('["Herman Melville"]', QueryValues(Store, '$..book[2].author'), 'third book''s author');
  CheckEqualsStr('[]', QueryValues(Store, '$..book[2].publisher'), 'third book has no publisher');
  CheckEqualsStr('["The Lord of the Rings"]', QueryValues(Store, '$..book[-1].title'), 'last book''s title');
  CheckEqualsStr('["Sayings of the Century","Sword of Honour"]', QueryValues(Store, '$..book[0,1].title'), 'first two books by index list');
  CheckEqualsStr('["Sayings of the Century","Sword of Honour"]', QueryValues(Store, '$..book[:2].title'), 'first two books by slice');
  CheckEqualsStr('["Moby Dick","The Lord of the Rings"]', QueryValues(Store, '$..book[?@.isbn].title'), 'books with isbn');
  CheckEqualsStr('["Sayings of the Century","Moby Dick"]', QueryValues(Store, '$..book[?@.price<10].title'), 'books cheaper than 10');
  CheckEqualsInt(27, QueryCount(Store, '$..*'), 'all member values and elements');
  Halt(EndSuite);
end.
