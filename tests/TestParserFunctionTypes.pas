{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestParserFunctionTypes;

{$APPTYPE CONSOLE}

uses
  TestSupport;

begin
  BeginSuite('Parser: function type checking (RFC 9535 2.4.3)');
  Check(QueryParses('$[?length(@) < 3]'), 'length of a singular query');
  Check(QueryParses('$[?count(@.*) == 1]'), 'count of a non-singular query');
  Check(QueryParses('$[?match(@.timezone, ''Europe/.*'')]'), 'match as a test expression');
  Check(QueryParses('$[?value(@..color) == "red"]'), 'value compared with a literal');
  Check(QueryParses('$[?search(@.a, "x")]'), 'search with literal arguments');
  Check(QueryParses('$[?length(value(@.a)) == 1]'), 'nested function arguments');
  Check(not QueryParses('$[?length(@.*) < 3]'), 'length of a non-singular query');
  Check(not QueryParses('$[?count(1) == 1]'), 'count of a literal');
  Check(not QueryParses('$[?match(@.timezone, ''Europe/.*'') == true]'), 'logical result used in a comparison');
  Check(not QueryParses('$[?value(@..color)]'), 'value result used as a test expression');
  Check(not QueryParses('$[?length(@)]'), 'length result used as a test expression');
  Check(not QueryParses('$[?match(@.a)]'), 'too few arguments');
  Check(not QueryParses('$[?length(@, @)]'), 'too many arguments');
  Check(not QueryParses('$[?foo(@)]'), 'unknown function');
  Check(not QueryParses('$[?count (@.*) == 1]'), 'whitespace before the opening parenthesis');
  Check(not QueryParses('$[?match(@.a, 1 == 1)]'), 'comparison passed as a value argument');
  Check(not QueryParses('$[?length(@,)]'), 'trailing comma in arguments');
  Check(not QueryParses('$[?Length(@) == 1]'), 'uppercase function name');
  Halt(EndSuite);
end.
