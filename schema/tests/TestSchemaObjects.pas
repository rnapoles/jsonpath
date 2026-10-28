{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestSchemaObjects;

{$APPTYPE CONSOLE}

uses
  TestSupport, SchemaTestSupport;

begin
  BeginSuite('Schema: object keywords');
  Check(SchemaAccepts('{"required":["a","b"]}', '{"a":1,"b":2}'), 'required present');
  Check(not SchemaAccepts('{"required":["a","b"]}', '{"a":1}'), 'required missing');
  Check(SchemaAccepts('{"required":["a"]}', '5'), 'required ignores non-objects');
  Check(SchemaAccepts('{"properties":{"a":{"type":"integer"}}}', '{"a":1}'), 'properties match');
  Check(not SchemaAccepts('{"properties":{"a":{"type":"integer"}}}', '{"a":"x"}'), 'properties mismatch');
  Check(SchemaAccepts('{"properties":{"a":{"type":"integer"}}}', '{"b":"x"}'), 'unlisted properties are free');
  Check(SchemaAccepts('{"properties":{"a":{}},"additionalProperties":false}', '{"a":1}'), 'additionalProperties false accepts listed');
  Check(not SchemaAccepts('{"properties":{"a":{}},"additionalProperties":false}', '{"a":1,"b":2}'), 'additionalProperties false rejects others');
  Check(SchemaAccepts('{"properties":{"a":{}},"additionalProperties":{"type":"integer"}}', '{"a":"s","b":1}'), 'additionalProperties schema ok');
  Check(not SchemaAccepts('{"properties":{"a":{}},"additionalProperties":{"type":"integer"}}', '{"b":"s"}'), 'additionalProperties schema violated');
  Check(SchemaAccepts('{"patternProperties":{"^x-":{"type":"string"}}}', '{"x-a":"s"}'), 'patternProperties match');
  Check(not SchemaAccepts('{"patternProperties":{"^x-":{"type":"string"}}}', '{"x-a":1}'), 'patternProperties violated');
  Check(SchemaAccepts('{"patternProperties":{"^x-":{}},"additionalProperties":false}', '{"x-1":1}'), 'additionalProperties skips pattern matches');
  Check(not SchemaAccepts('{"patternProperties":{"^x-":{}},"additionalProperties":false}', '{"y":1}'), 'additionalProperties rejects unmatched');
  Check(not SchemaAccepts('{"minProperties":1}', '{}'), 'minProperties');
  Check(SchemaAccepts('{"minProperties":1}', '{"a":1}'), 'minProperties boundary');
  Check(not SchemaAccepts('{"maxProperties":1}', '{"a":1,"b":2}'), 'maxProperties');
  Check(SchemaAccepts('{"propertyNames":{"maxLength":2}}', '{"ab":1}'), 'propertyNames accepts short names');
  Check(not SchemaAccepts('{"propertyNames":{"maxLength":2}}', '{"abc":1}'), 'propertyNames rejects long names');
  Check(SchemaAccepts('{"propertyNames":{"maxLength":2}}', '{"abc":1}', 'draft-04'), 'draft-04 ignores propertyNames');
  Check(SchemaAccepts('{"dependencies":{"a":["b"]}}', '{"a":1,"b":2}', 'draft-07'), 'dependencies satisfied');
  Check(not SchemaAccepts('{"dependencies":{"a":["b"]}}', '{"a":1}', 'draft-07'), 'dependencies violated');
  Check(SchemaAccepts('{"dependencies":{"a":["b"]}}', '{}', 'draft-07'), 'dependencies inactive without trigger');
  Check(not SchemaAccepts('{"dependencies":{"a":{"required":["c"]}}}', '{"a":1}', 'draft-07'), 'schema dependency violated');
  Check(SchemaAccepts('{"dependencies":{"a":{"required":["c"]}}}', '{"a":1,"c":1}', 'draft-07'), 'schema dependency satisfied');
  Check(not SchemaAccepts('{"dependentRequired":{"a":["b"]}}', '{"a":1}'), 'dependentRequired violated');
  Check(SchemaAccepts('{"dependentRequired":{"a":["b"]}}', '{"a":1,"b":1}'), 'dependentRequired satisfied');
  Check(not SchemaAccepts('{"dependentSchemas":{"a":{"required":["c"]}}}', '{"a":1}'), 'dependentSchemas violated');
  Check(SchemaAccepts('{"dependentSchemas":{"a":{"required":["c"]}}}', '{"b":1}'), 'dependentSchemas inactive');
  Check(SchemaAccepts('{"dependencies":{"a":["b"]}}', '{"a":1}'), '2020-12 does not know dependencies');
  Check(SchemaIsInvalid('{"required":[]}', 'draft-04'), 'draft-04 rejects an empty required array');
  Check(not SchemaIsInvalid('{"required":[]}', 'draft-06'), 'draft-06 allows an empty required array');
  Check(SchemaIsInvalid('{"required":"a"}'), 'required must be an array');
  Check(SchemaIsInvalid('{"required":[1]}'), 'required entries must be strings');
  Check(SchemaIsInvalid('{"required":["a","a"]}'), 'required must not repeat names');
  Check(SchemaIsInvalid('{"properties":[]}'), 'properties must be an object');
  Check(SchemaIsInvalid('{"properties":{"a":5}}'), 'property schemas must be schemas');
  Halt(EndSuite);
end.
