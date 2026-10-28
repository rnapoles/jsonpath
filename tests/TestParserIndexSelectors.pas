{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestParserIndexSelectors;

{$APPTYPE CONSOLE}

uses
  TestSupport;

begin
  BeginSuite('Parser: index selectors');
  Check(QueryParses('$[0]'), 'zero');
  Check(QueryParses('$[-1]'), 'negative index');
  Check(QueryParses('$[9007199254740991]'), 'largest allowed integer');
  Check(not QueryParses('$[9007199254740992]'), 'integer above 2^53-1 is rejected');
  Check(not QueryParses('$[01]'), 'leading zero is rejected');
  Check(not QueryParses('$[-0]'), 'negative zero is rejected');
  Check(not QueryParses('$[1.5]'), 'decimal index is rejected');
  Check(not QueryParses('$[-]'), 'lone minus is rejected');
  Halt(EndSuite);
end.
