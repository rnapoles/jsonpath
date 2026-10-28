{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestSchemaTypes;

{$APPTYPE CONSOLE}

uses
  TestSupport, SchemaTestSupport;

begin
  BeginSuite('Schema: type keyword and built-in types');
  Check(SchemaAccepts('{"type":"string"}', '"x"'), 'string');
  Check(not SchemaAccepts('{"type":"string"}', '1'), 'string rejects number');
  Check(SchemaAccepts('{"type":"integer"}', '3'), 'integer');
  Check(SchemaAccepts('{"type":"integer"}', '3.0'), 'integer-valued float counts as integer');
  Check(not SchemaAccepts('{"type":"integer"}', '3.5'), 'fraction is not an integer');
  Check(SchemaAccepts('{"type":"number"}', '1.5'), 'number accepts floats');
  Check(not SchemaAccepts('{"type":"number"}', '"1"'), 'number rejects strings');
  Check(SchemaAccepts('{"type":"boolean"}', 'true'), 'boolean');
  Check(not SchemaAccepts('{"type":"boolean"}', 'null'), 'boolean rejects null');
  Check(SchemaAccepts('{"type":"null"}', 'null'), 'null');
  Check(SchemaAccepts('{"type":"array"}', '[]'), 'array');
  Check(not SchemaAccepts('{"type":"array"}', '{}'), 'array rejects object');
  Check(SchemaAccepts('{"type":"object"}', '{}'), 'object');
  Check(SchemaAccepts('{"type":["string","null"]}', 'null'), 'type list accepts either type');
  Check(not SchemaAccepts('{"type":["string","null"]}', '1'), 'type list rejects others');
  Check(SchemaAccepts('true', '{"a":1}'), 'true schema accepts anything');
  Check(not SchemaAccepts('false', '1'), 'false schema rejects everything');
  Check(SchemaAccepts('{}', '[1,2]'), 'empty schema accepts anything');
  Halt(EndSuite);
end.
