{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestSchemaRefs;

{$APPTYPE CONSOLE}

uses
  TestSupport, SchemaTestSupport;

begin
  BeginSuite('Schema: $ref, $id, anchors');
  Check(SchemaAccepts('{"definitions":{"pos":{"type":"integer","minimum":1}},"properties":{"n":{"$ref":"#/definitions/pos"}}}', '{"n":2}', 'draft-07'), 'local definition (draft-07)');
  Check(not SchemaAccepts('{"definitions":{"pos":{"type":"integer","minimum":1}},"properties":{"n":{"$ref":"#/definitions/pos"}}}', '{"n":0}', 'draft-07'), 'local definition violated (draft-07)');
  Check(SchemaAccepts('{"$defs":{"pos":{"type":"integer","minimum":1}},"properties":{"n":{"$ref":"#/$defs/pos"}}}', '{"n":2}'), '$defs reference (2020-12)');
  Check(not SchemaAccepts('{"$defs":{"pos":{"type":"integer","minimum":1}},"properties":{"n":{"$ref":"#/$defs/pos"}}}', '{"n":0}'), '$defs reference violated');
  Check(SchemaAccepts('{"type":"object","properties":{"child":{"$ref":"#"}}}', '{"child":{"child":{}}}'), 'recursive $ref to the root');
  Check(not SchemaAccepts('{"type":"object","properties":{"child":{"$ref":"#"}}}', '{"child":{"child":5}}'), 'recursive $ref rejects a bad leaf');
  Check(SchemaAccepts('{"definitions":{"s":{"type":"string"}},"properties":{"a":{"$ref":"#/definitions/s","maxLength":1}}}', '{"a":"toolong"}', 'draft-07'), 'draft-07 ignores siblings of $ref');
  Check(not SchemaAccepts('{"definitions":{"s":{"type":"string"}},"properties":{"a":{"$ref":"#/definitions/s","maxLength":1}}}', '{"a":"toolong"}', '2019-09'), '2019-09 evaluates siblings of $ref');
  Check(SchemaAccepts('{"$id":"http://example.com/root.json","definitions":{"a":{"$id":"a.json","type":"integer"}},"properties":{"x":{"$ref":"a.json"}}}', '{"x":1}', 'draft-07'), '$id based resolution');
  Check(not SchemaAccepts('{"$id":"http://example.com/root.json","definitions":{"a":{"$id":"a.json","type":"integer"}},"properties":{"x":{"$ref":"a.json"}}}', '{"x":"s"}', 'draft-07'), '$id based resolution violated');
  Check(SchemaAccepts('{"$defs":{"s":{"$anchor":"foo","type":"string"}},"properties":{"x":{"$ref":"#foo"}}}', '{"x":"a"}'), '$anchor (2020-12)');
  Check(not SchemaAccepts('{"$defs":{"s":{"$anchor":"foo","type":"string"}},"properties":{"x":{"$ref":"#foo"}}}', '{"x":1}'), '$anchor violated');
  Check(SchemaAccepts('{"definitions":{"s":{"$id":"#foo","type":"string"}},"properties":{"x":{"$ref":"#foo"}}}', '{"x":"a"}', 'draft-07'), 'draft-07 plain-name $id');
  Check(not SchemaAccepts('{"definitions":{"s":{"$id":"#foo","type":"string"}},"properties":{"x":{"$ref":"#foo"}}}', '{"x":1}', 'draft-07'), 'draft-07 plain-name $id violated');
  Check(SchemaAccepts('{"definitions":{"a b":{"type":"integer"},"x/y":{"type":"string"}},"properties":{"p":{"$ref":"#/definitions/a%20b"},"q":{"$ref":"#/definitions/x~1y"}}}', '{"p":1,"q":"s"}', 'draft-07'), 'pointer escapes and percent decoding');
  Check(not SchemaAccepts('{"definitions":{"a b":{"type":"integer"},"x/y":{"type":"string"}},"properties":{"p":{"$ref":"#/definitions/a%20b"},"q":{"$ref":"#/definitions/x~1y"}}}', '{"p":1,"q":2}', 'draft-07'), 'pointer escapes violated');
  Check(SchemaAccepts('{"examples":[{"type":"string"}],"properties":{"x":{"$ref":"#/examples/0"}}}', '{"x":"s"}'), 'reference into an array element');
  Check(not SchemaAccepts('{"examples":[{"type":"string"}],"properties":{"x":{"$ref":"#/examples/0"}}}', '{"x":1}'), 'reference into an array element is enforced');
  Check(SchemaIsInvalid('{"$ref":"#/definitions/missing"}'), 'missing definition is a schema error');
  Check(SchemaIsInvalid('{"$ref":"#nowhere"}'), 'missing anchor is a schema error');
  Check(SchemaIsInvalid('{"$ref":5}'), '$ref must be a string');
  Check(not SchemaIsInvalid('{"$ref":"other-schema"}'), 'reference to a schema registered later is accepted');
  Check(SchemaIsInvalid('{"$anchor":"1bad"}'), '$anchor syntax is checked');
  Check(SchemaIsInvalid('{"$defs":{"x":{"type":"nope"}}}'), 'invalid subschema inside $defs is reported');
  CheckEqualsStr('type|/$defs/x/type', SchemaErrorInfo('{"$defs":{"x":{"type":"nope"}}}'), 'error location points into $defs');
  Halt(EndSuite);
end.
