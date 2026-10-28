{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryNameEscapes;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '{"a":1,"\u000b":2}';

begin
  BeginSuite('Query: name selector escapes');
  CheckEqualsStr('[1]', QueryValues(Doc, '$["\u0061"]'), 'unicode escape in name selects the member');
  CheckEqualsStr('$[''a'']', QueryPaths(Doc, '$["\u0061"]'), 'unicode escape normalizes to the plain character');
  CheckEqualsStr('$[''\u000b'']', QueryPaths(Doc, '$["\u000B"]'), 'control character is normalized to lowercase hex escape');
  Halt(EndSuite);
end.
