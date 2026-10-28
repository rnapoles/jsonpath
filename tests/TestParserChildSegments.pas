{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestParserChildSegments;

{$APPTYPE CONSOLE}

uses
  TestSupport;

begin
  BeginSuite('Parser: child segments');
  Check(QueryParses('$.a'), 'dot member');
  Check(QueryParses('$.a.b.c'), 'chained dot members');
  Check(QueryParses('$[''a'']'), 'bracketed name');
  Check(QueryParses('$["a"]'), 'bracketed name with double quotes');
  Check(QueryParses('$.*'), 'dot wildcard');
  Check(QueryParses('$._a1'), 'member names may start with underscore');
  Check(not QueryParses('$.1a'), 'member names cannot start with a digit');
  Check(not QueryParses('$.'), 'dangling dot');
  Check(not QueryParses('$.a-b'), 'hyphen is not a name character');
  Check(QueryParses('$.caf'#$C3#$A9), 'non-ASCII member name');
  Halt(EndSuite);
end.
