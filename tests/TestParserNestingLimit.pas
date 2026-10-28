{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestParserNestingLimit;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils;

begin
  BeginSuite('Parser: deep nesting fails cleanly');
  Check(not QueryParses('$[?' + StringOfChar('(', 1000) + '@.a' + StringOfChar(')', 1000) + ']'),
  'excessively nested parentheses are rejected');
  Check(QueryParses('$[?' + StringOfChar('(', 20) + '@.a' + StringOfChar(')', 20) + ']'),
  'moderate nesting is accepted');
  CheckEqualsStr('filter-selector', QueryErrorRule('$[?' + StringOfChar('(', 1000) + '@.a' + StringOfChar(')', 1000) + ']'),
  'nesting error names the filter rule');
  Halt(EndSuite);
end.
