{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestSchemaArrays;

{$APPTYPE CONSOLE}

uses
  TestSupport, SchemaTestSupport;

begin
  BeginSuite('Schema: array keywords');
  Check(SchemaAccepts('{"items":{"type":"integer"}}', '[1,2]'), 'items schema accepts matching elements');
  Check(not SchemaAccepts('{"items":{"type":"integer"}}', '[1,"a"]'), 'items schema rejects others');
  Check(SchemaAccepts('{"items":{"type":"integer"}}', '[]'), 'items accepts empty arrays');
  Check(SchemaAccepts('{"prefixItems":[{"type":"string"},{"type":"integer"}]}', '["a",1,true]'), 'prefixItems positional match (2020-12)');
  Check(not SchemaAccepts('{"prefixItems":[{"type":"string"},{"type":"integer"}]}', '[1,"a"]'), 'prefixItems positional mismatch');
  Check(SchemaAccepts('{"prefixItems":[{"type":"string"},{"type":"integer"}]}', '["a"]'), 'prefixItems allows shorter arrays');
  Check(SchemaAccepts('{"prefixItems":[{"type":"string"}],"items":false}', '["a"]'), 'items false after prefixItems: exact tuple');
  Check(not SchemaAccepts('{"prefixItems":[{"type":"string"}],"items":false}', '["a",1]'), 'items false rejects extra elements');
  Check(SchemaAccepts('{"items":[{"type":"string"}],"additionalItems":false}', '["a"]', 'draft-07'), 'draft-07 tuple with additionalItems false');
  Check(not SchemaAccepts('{"items":[{"type":"string"}],"additionalItems":false}', '["a",1]', 'draft-07'), 'draft-07 additionalItems false rejects extras');
  Check(SchemaAccepts('{"items":[{"type":"string"}],"additionalItems":{"type":"integer"}}', '["a",1]', 'draft-07'), 'draft-07 additionalItems schema');
  Check(not SchemaAccepts('{"items":[{"type":"string"}],"additionalItems":{"type":"integer"}}', '["a","b"]', 'draft-07'), 'draft-07 additionalItems schema mismatch');
  Check(SchemaIsInvalid('{"items":[{"type":"string"}]}'), 'array-form items is invalid in 2020-12');
  Check(SchemaIsInvalid('{"items":[5]}', 'draft-07'), 'array-form items entries must be schemas (draft-07)');
  Check(not SchemaAccepts('{"minItems":2}', '[1]'), 'minItems');
  Check(SchemaAccepts('{"minItems":2}', '[1,2]'), 'minItems boundary');
  Check(not SchemaAccepts('{"maxItems":1}', '[1,2]'), 'maxItems');
  Check(not SchemaAccepts('{"uniqueItems":true}', '[1,2,1]'), 'uniqueItems rejects duplicates');
  Check(SchemaAccepts('{"uniqueItems":true}', '[1,2]'), 'uniqueItems accepts distinct');
  Check(not SchemaAccepts('{"uniqueItems":true}', '[{"a":1},{"a":1}]'), 'uniqueItems compares objects deeply');
  Check(not SchemaAccepts('{"uniqueItems":true}', '[1,1.0]'), 'uniqueItems treats 1 and 1.0 as equal');
  Check(not SchemaAccepts('{"uniqueItems":true}', '[[1],[1]]'), 'uniqueItems compares arrays');
  Check(SchemaAccepts('{"uniqueItems":true}', '[1,true,"1"]'), 'uniqueItems keeps types apart');
  Check(SchemaAccepts('{"uniqueItems":false}', '[1,1]'), 'uniqueItems false is a no-op');
  Check(SchemaAccepts('{"contains":{"type":"integer"}}', '["a",1]'), 'contains finds a match');
  Check(not SchemaAccepts('{"contains":{"type":"integer"}}', '["a"]'), 'contains without match');
  Check(not SchemaAccepts('{"contains":{"type":"integer"}}', '[]'), 'contains fails on empty arrays');
  Check(SchemaAccepts('{"contains":{"type":"integer"},"minContains":2}', '[1,2]'), 'minContains satisfied');
  Check(not SchemaAccepts('{"contains":{"type":"integer"},"minContains":2}', '[1,"a"]'), 'minContains not satisfied');
  Check(not SchemaAccepts('{"contains":{"type":"integer"},"maxContains":1}', '[1,2]'), 'maxContains exceeded');
  Check(SchemaAccepts('{"contains":{"type":"integer"},"maxContains":1}', '[1,"a"]'), 'maxContains respected');
  Check(SchemaAccepts('{"contains":{"type":"integer"},"minContains":0}', '["a"]'), 'minContains 0 allows no match');
  Check(SchemaAccepts('{"contains":{"type":"integer"},"minContains":2}', '[1,"x"]', 'draft-07'), 'draft-07 ignores minContains');
  Check(SchemaIsInvalid('{"minItems":-1}'), 'minItems must be a non-negative integer');
  Check(SchemaIsInvalid('{"uniqueItems":"yes"}'), 'uniqueItems must be boolean');
  Halt(EndSuite);
end.
