{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryReferenceExpectedOutputs;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '{"store":{"book":[{"category":"reference","author":"Nigel Rees","title":"Sayings of the Century","price":8.95},{"category":"fiction","author":"Evelyn Waugh","title":"Sword of Honour","price":12.99},{"category":"fiction","author":"Herman Melville","title":"Moby Dick","isbn":"0-553-21311-3","price":8.99},{"category":"fiction","author":"J. R. R. Tolkien","title":"The Lord of the Rings","isbn":"0-395-19395-8","price":22.99}],"bicycle":{"color":"red","price":399}},"expensive":10}';

begin
  BeginSuite('Query: expected-output table from the reference');
  CheckEqualsStr('["Sword of Honour","The Lord of the Rings"]', QueryValues(Doc, '$.store.book[?(@.price > $.expensive)].title'), 'titles above the expensive threshold');
  CheckEqualsStr('[{"category":"reference","author":"Nigel Rees","title":"Sayings of the Century","price":8.95},{"category":"fiction","author":"Evelyn Waugh","title":"Sword of Honour","price":12.99},{"category":"fiction","author":"Herman Melville","title":"Moby Dick","isbn":"0-553-21311-3","price":8.99},{"category":"fiction","author":"J. R. R. Tolkien","title":"The Lord of the Rings","isbn":"0-395-19395-8","price":22.99}]', QueryValues(Doc, '$..[?(@.author)]'), 'books that have an author (descendant filter)');
  CheckEqualsStr('[{"category":"fiction","author":"Evelyn Waugh","title":"Sword of Honour","price":12.99}]', QueryValues(Doc, '$.store.book[?(@.price >= 10 && @.price <= 20)]'), 'books priced between 10 and 20');
  CheckEqualsStr('["Sword of Honour","Moby Dick","The Lord of the Rings"]', QueryValues(Doc, '$.store.book[?(@.category == ''fiction'')].title'), 'titles of fiction books');
  Check(not QueryParses('[?(@.price < 10)]'), 'a query without root identifier is rejected');
  CheckEqualsStr('[{"category":"reference","author":"Nigel Rees","title":"Sayings of the Century","price":8.95},{"category":"fiction","author":"Herman Melville","title":"Moby Dick","isbn":"0-553-21311-3","price":8.99}]', QueryValues(Doc, '$.store.book[?(@.price < 10)]'), 'books cheaper than 10');
  CheckEqualsStr('[{"category":"fiction","author":"Evelyn Waugh","title":"Sword of Honour","price":12.99},{"category":"fiction","author":"Herman Melville","title":"Moby Dick","isbn":"0-553-21311-3","price":8.99},{"category":"fiction","author":"J. R. R. Tolkien","title":"The Lord of the Rings","isbn":"0-395-19395-8","price":22.99}]', QueryValues(Doc, '$.store.book[?(@.category == ''fiction'')]'), 'fiction books');
  CheckEqualsStr('[{"category":"reference","author":"Nigel Rees","title":"Sayings of the Century","price":8.95},{"category":"fiction","author":"Herman Melville","title":"Moby Dick","isbn":"0-553-21311-3","price":8.99}]', QueryValues(Doc, '$.store.book[?(@.price < $.expensive)]'), 'books cheaper than the threshold');
  CheckEqualsStr('[{"category":"fiction","author":"J. R. R. Tolkien","title":"The Lord of the Rings","isbn":"0-395-19395-8","price":22.99}]', QueryValues(Doc, '$.store.book[?(@.author && @.price > 20)]'), 'books with an author costing more than 20');
  Halt(EndSuite);
end.
