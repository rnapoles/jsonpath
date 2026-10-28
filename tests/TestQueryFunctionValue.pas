{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryFunctionValue;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '[{"x":{"c":1}},{"c":2},{"c":1,"d":{"c":1}}]';

begin
  BeginSuite('Query: value() function');
  CheckEqualsStr('[{"x":{"c":1}}]', QueryValues(Doc, '$[?value(@..c) == 1]'), 'value of a single descendant node');
  CheckEqualsStr('[{"c":2}]', QueryValues(Doc, '$[?value(@..c) == 2]'), 'value of several nodes is nothing');
  Halt(EndSuite);
end.
