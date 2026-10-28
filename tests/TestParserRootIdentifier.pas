{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestParserRootIdentifier;

{$APPTYPE CONSOLE}

uses
  TestSupport;

begin
  BeginSuite('Parser: root identifier and whitespace');
  Check(QueryParses('$'), 'bare root parses');
  Check(not QueryParses(''), 'empty query is rejected');
  Check(not QueryParses('a.b'), 'query must start with $');
  Check(not QueryParses(' $'), 'leading whitespace is rejected');
  Check(not QueryParses('$ '), 'trailing whitespace is rejected');
  Check(not QueryParses('@.a'), 'relative query is not a top-level query');
  Check(QueryParses('$ .a  .b'), 'whitespace between segments is allowed');
  Check(not QueryParses('$. a'), 'whitespace after the dot is rejected');
  Halt(EndSuite);
end.
