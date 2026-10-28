{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryFilterComparisons;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '{"a":[3,5,1,2,4,6,{"b":"j"},{"b":"k"},{"b":{}},{"b":"kilo"}],"o":{"p":1,"q":2,"r":3,"s":5,"t":{"u":6}},"e":"f"}';
  Store =
    '{"store":{"book":[{"category":"reference","author":"Nigel Rees","title":"Sayings of the Century","price":8.95},{"category":"fiction","author":"Evelyn Waugh","title":"Sword of Honour","price":12.99},{"category":"fiction","author":"Herman Melville","title":"Moby Dick","isbn":"0-553-21311-3","price":8.99},{"category":"fiction","author":"J. R. R. Tolkien","title":"The Lord of the Rings","isbn":"0-395-19395-8","price":22.99}],"bicycle":{"color":"red","price":399}}}';

begin
  BeginSuite('Query: filter comparisons');
  CheckEqualsStr('[{"b":"kilo"}]', QueryValues(Doc, '$.a[?@.b == ''kilo'']'), 'string equality on a member');
  CheckEqualsStr('$[''a''][9]', QueryPaths(Doc, '$.a[?@.b == ''kilo'']'), 'path of string equality match');
  CheckEqualsStr('[{"b":"kilo"}]', QueryValues(Doc, '$.a[?(@.b == ''kilo'')]'), 'parenthesised comparison is equivalent');
  CheckEqualsStr('[5,4,6]', QueryValues(Doc, '$.a[?@>3.5]'), 'numeric greater-than on array values');
  CheckEqualsStr('$[''a''][1];$[''a''][4];$[''a''][5]', QueryPaths(Doc, '$.a[?@>3.5]'), 'paths of numeric greater-than');
  CheckEqualsStr('[3,5,1,2,4,6]', QueryValues(Doc, '$.a[?@.b == $.x]'), 'comparison with an absent query matches absent members');
  CheckEqualsInt(10, QueryCount(Doc, '$.a[?@ == @]'), 'every value equals itself');
  CheckEqualsInt(9, QueryCount(Doc, '$.a[?@ != 3]'), 'not-equal to a number matches everything else');
  CheckEqualsStr('[1,2]', QueryValues(Doc, '$.a[?@ <= 2]'), 'less-or-equal on numbers');
  CheckEqualsStr('[{"b":"j"}]', QueryValues(Doc, '$.a[?@.b < ''k'']'), 'string ordering');
  CheckEqualsStr('[]', QueryValues(Doc, '$.a[?@ == ''x'']'), 'type mismatch never equals');
  CheckEqualsStr('["Sayings of the Century","Moby Dick"]', QueryValues(Store, '$.store.book[?@.price<10].title'), 'filter price below 10');
  CheckEqualsStr('["Sayings of the Century","Sword of Honour","Moby Dick","The Lord of the Rings"]', QueryValues(Store, '$.store.book[?@.price < $.store.bicycle.price].title'), 'filter compares against a root query');
  Halt(EndSuite);
end.
