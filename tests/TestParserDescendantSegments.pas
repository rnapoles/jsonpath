{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestParserDescendantSegments;

{$APPTYPE CONSOLE}

uses
  TestSupport;

begin
  BeginSuite('Parser: descendant segments');
  Check(QueryParses('$..a'), 'descendant member');
  Check(QueryParses('$..*'), 'descendant wildcard');
  Check(QueryParses('$..[0]'), 'descendant bracket');
  Check(QueryParses('$..[''a'']'), 'descendant bracketed name');
  Check(not QueryParses('$...a'), 'three dots are rejected');
  Check(not QueryParses('$..'), 'descendant needs a selector');
  Halt(EndSuite);
end.
