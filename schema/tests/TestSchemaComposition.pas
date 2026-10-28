{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestSchemaComposition;

{$APPTYPE CONSOLE}

uses
  TestSupport, SchemaTestSupport;

begin
  BeginSuite('Schema: allOf anyOf oneOf not if/then/else enum const');
  Check(SchemaAccepts('{"allOf":[{"type":"integer"},{"minimum":3}]}', '5'), 'allOf all match');
  Check(not SchemaAccepts('{"allOf":[{"type":"integer"},{"minimum":3}]}', '2'), 'allOf one fails');
  Check(SchemaAccepts('{"anyOf":[{"type":"integer"},{"type":"string"}]}', '1'), 'anyOf first');
  Check(SchemaAccepts('{"anyOf":[{"type":"integer"},{"type":"string"}]}', '"a"'), 'anyOf second');
  Check(not SchemaAccepts('{"anyOf":[{"type":"integer"},{"type":"string"}]}', 'null'), 'anyOf none');
  Check(SchemaAccepts('{"oneOf":[{"type":"integer"},{"minimum":3}]}', '2'), 'oneOf exactly one');
  Check(not SchemaAccepts('{"oneOf":[{"type":"integer"},{"minimum":3}]}', '5'), 'oneOf both match');
  Check(not SchemaAccepts('{"oneOf":[{"type":"integer"},{"minimum":3}]}', '1.5'), 'oneOf none match');
  Check(SchemaAccepts('{"oneOf":[{"type":"integer"},{"minimum":3}]}', '4.5'), 'oneOf second only');
  Check(SchemaAccepts('{"not":{"type":"string"}}', '1'), 'not passes');
  Check(not SchemaAccepts('{"not":{"type":"string"}}', '"a"'), 'not fails');
  Check(not SchemaAccepts('{"if":{"properties":{"a":{"const":1}}},"then":{"required":["b"]},"else":{"required":["c"]}}', '{"a":1}', 'draft-07'), 'if/then: condition true, then violated');
  Check(SchemaAccepts('{"if":{"properties":{"a":{"const":1}}},"then":{"required":["b"]},"else":{"required":["c"]}}', '{"a":1,"b":0}', 'draft-07'), 'if/then satisfied');
  Check(SchemaAccepts('{"if":{"properties":{"a":{"const":1}}},"then":{"required":["b"]},"else":{"required":["c"]}}', '{"a":2,"c":0}', 'draft-07'), 'if/else satisfied');
  Check(not SchemaAccepts('{"if":{"properties":{"a":{"const":1}}},"then":{"required":["b"]},"else":{"required":["c"]}}', '{"a":2}', 'draft-07'), 'if/else violated');
  Check(SchemaAccepts('{"if":{"type":"integer"}}', '"x"'), 'if without then/else is a no-op');
  Check(SchemaAccepts('{"if":{"properties":{"a":{"const":1}}},"then":{"required":["b"]}}', '{"a":1}', 'draft-06'), 'draft-06 ignores if/then');
  Check(SchemaAccepts('{"enum":[1,"a",null,{"x":1}]}', 'null'), 'enum member');
  Check(SchemaAccepts('{"enum":[1,"a",null,{"x":1}]}', '{"x":1}'), 'enum object member');
  Check(not SchemaAccepts('{"enum":[1,"a",null,{"x":1}]}', '2'), 'enum non-member');
  Check(SchemaAccepts('{"enum":[1,"a"]}', '1.0'), 'enum compares numbers by value');
  Check(SchemaAccepts('{"const":{"a":[1,2]}}', '{"a":[1,2]}'), 'const deep equal');
  Check(not SchemaAccepts('{"const":{"a":[1,2]}}', '{"a":[2,1]}'), 'const array order matters');
  Check(SchemaAccepts('{"const":null}', 'null'), 'const null');
  Check(not SchemaAccepts('{"const":null}', '0'), 'const null rejects zero');
  Check(not SchemaAccepts('{"const":1}', '2', 'draft-06'), 'draft-06 const');
  Check(SchemaAccepts('{"const":1}', '2', 'draft-04'), 'draft-04 ignores const');
  Check(SchemaIsInvalid('{"allOf":[]}'), 'allOf must not be empty');
  Check(SchemaIsInvalid('{"allOf":{}}'), 'allOf must be an array');
  Check(SchemaIsInvalid('{"enum":5}'), 'enum must be an array');
  Check(SchemaIsInvalid('{"enum":[]}', 'draft-04'), 'draft-04 enum must not be empty');
  Halt(EndSuite);
end.
