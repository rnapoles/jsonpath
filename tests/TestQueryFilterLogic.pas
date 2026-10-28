{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryFilterLogic;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '{"a":[3,5,1,2,4,6,{"b":"j"},{"b":"k"},{"b":{}},{"b":"kilo"}],"o":{"p":1,"q":2,"r":3,"s":5,"t":{"u":6}},"e":"f"}';

begin
  BeginSuite('Query: filter logical operators');
  CheckEqualsStr('[1,{"b":"k"}]', QueryValues(Doc, '$.a[?@<2 || @.b == "k"]'), 'logical or');
  CheckEqualsStr('$[''a''][2];$[''a''][7]', QueryPaths(Doc, '$.a[?@<2 || @.b == "k"]'), 'paths of logical or');
  CheckEqualsStr('[2,3]', QueryValues(Doc, '$.o[?@>1 && @<4]'), 'logical and');
  CheckEqualsStr('[{"u":6}]', QueryValues(Doc, '$.o[?@.u || @.x]'), 'or of existence tests');
  CheckEqualsStr('[3,1,2,{"b":"j"},{"b":"k"},{"b":{}},{"b":"kilo"}]', QueryValues(Doc, '$.a[?!(@ > 3)]'), 'negated parenthesised comparison');
  CheckEqualsStr('[1]', QueryValues(Doc, '$.a[?@ == 1 || @ == 2 && @ == 3]'), 'and binds tighter than or');
  CheckEqualsStr('[2]', QueryValues(Doc, '$.a[?(@ == 1 || @ == 2) && @ == 2]'), 'parentheses override precedence');
  Halt(EndSuite);
end.
