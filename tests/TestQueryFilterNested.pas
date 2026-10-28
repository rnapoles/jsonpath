{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryFilterNested;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '{"a":[3,5,1,2,4,6,{"b":"j"},{"b":"k"},{"b":{}},{"b":"kilo"}],"o":{"p":1,"q":2,"r":3,"s":5,"t":{"u":6}},"e":"f"}';

begin
  BeginSuite('Query: nested filters');
  CheckEqualsStr('$[''a'']', QueryPaths(Doc, '$[?@[?@.b]]'), 'filter inside a filter');
  CheckEqualsStr('[1,2,1,2]', QueryValues(Doc, '$.o[?@<3, ?@<3]'), 'repeated filter selectors select twice');
  CheckEqualsStr('[{"b":"j"}]', QueryValues(Doc, '$..[?@.b == ''j'']'), 'descendant segment with a filter');
  Halt(EndSuite);
end.
