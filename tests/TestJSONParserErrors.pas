{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestJSONParserErrors;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils;

begin
  BeginSuite('JSON: parsing invalid documents');
  Check(JSONIsInvalid(''), 'empty input');
  Check(JSONIsInvalid('[1,]'), 'trailing comma in array');
  Check(JSONIsInvalid('{"a":1,}'), 'trailing comma in object');
  Check(JSONIsInvalid('{a:1}'), 'unquoted member name');
  Check(JSONIsInvalid('01'), 'leading zero');
  Check(JSONIsInvalid('1.'), 'missing fraction digits');
  Check(JSONIsInvalid('"abc'), 'unterminated string');
  Check(JSONIsInvalid('"\q"'), 'unknown escape');
  Check(JSONIsInvalid('"\ud800"'), 'lone surrogate');
  Check(JSONIsInvalid('[1] x'), 'trailing characters');
  Check(JSONIsInvalid('nul'), 'truncated literal');
  Check(JSONIsInvalid(StringOfChar('[', 600) + StringOfChar(']', 600)), 'nesting beyond the depth limit');
  Halt(EndSuite);
end.
