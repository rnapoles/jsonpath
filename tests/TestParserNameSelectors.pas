{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestParserNameSelectors;

{$APPTYPE CONSOLE}

uses
  TestSupport;

begin
  BeginSuite('Parser: name selector string literals');
  Check(QueryParses('$[''a'']'), 'single-quoted');
  Check(QueryParses('$["a"]'), 'double-quoted');
  Check(QueryParses('$['''']'), 'empty name');
  Check(QueryParses('$["it''s"]'), 'single quote inside double quotes');
  Check(QueryParses('$[''it\''s'']'), 'escaped single quote inside single quotes');
  Check(not QueryParses('$[''a\"b'']'), 'escaped double quote inside single quotes');
  Check(not QueryParses('$["a\''b"]'), 'escaped single quote inside double quotes');
  Check(not QueryParses('$[''abc'), 'unterminated string');
  Check(not QueryParses('$[''\q'']'), 'unknown escape');
  Check(QueryParses('$[''\u0041'']'), 'unicode escape');
  Check(QueryParses('$[''\uD83D\uDE00'']'), 'surrogate pair escape');
  Check(not QueryParses('$[''\uD83D'']'), 'lone high surrogate');
  Check(not QueryParses('$[''\uDE00'']'), 'lone low surrogate');
  Check(not QueryParses('$[''\u00'']'), 'short unicode escape');
  Halt(EndSuite);
end.
