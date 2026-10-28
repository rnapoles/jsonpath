{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestSchemaNumeric;

{$APPTYPE CONSOLE}

uses
  TestSupport, SchemaTestSupport;

begin
  BeginSuite('Schema: numeric keywords');
  Check(SchemaAccepts('{"minimum":5}', '5'), 'minimum boundary');
  Check(not SchemaAccepts('{"minimum":5}', '4'), 'below minimum');
  Check(SchemaAccepts('{"minimum":5}', '"x"'), 'non-numbers ignore minimum');
  Check(not SchemaAccepts('{"exclusiveMinimum":5}', '5'), 'exclusiveMinimum boundary (2020-12)');
  Check(SchemaAccepts('{"exclusiveMinimum":5}', '5.1'), 'above exclusiveMinimum');
  Check(SchemaAccepts('{"maximum":5}', '5'), 'maximum boundary');
  Check(not SchemaAccepts('{"maximum":5}', '6'), 'above maximum');
  Check(not SchemaAccepts('{"exclusiveMaximum":5}', '5'), 'exclusiveMaximum boundary');
  Check(SchemaAccepts('{"exclusiveMaximum":5}', '4.9'), 'below exclusiveMaximum');
  Check(not SchemaAccepts('{"minimum":5,"exclusiveMinimum":true}', '5', 'draft-04'), 'draft-04 boolean exclusiveMinimum rejects the boundary');
  Check(SchemaAccepts('{"minimum":5,"exclusiveMinimum":true}', '5.5', 'draft-04'), 'draft-04 boolean exclusiveMinimum accepts larger');
  Check(SchemaAccepts('{"minimum":5,"exclusiveMinimum":false}', '5', 'draft-04'), 'draft-04 inclusive minimum when flag is false');
  Check(not SchemaAccepts('{"maximum":5,"exclusiveMaximum":true}', '5', 'draft-04'), 'draft-04 boolean exclusiveMaximum');
  Check(SchemaIsInvalid('{"minimum":5,"exclusiveMinimum":5}', 'draft-04'), 'draft-04 numeric exclusiveMinimum is invalid');
  Check(SchemaIsInvalid('{"exclusiveMinimum":true}'), '2020-12 boolean exclusiveMinimum is invalid');
  Check(SchemaIsInvalid('{"exclusiveMinimum":true}', 'draft-04'), 'draft-04 exclusiveMinimum needs minimum');
  Check(SchemaAccepts('{"multipleOf":3}', '9'), 'multipleOf');
  Check(not SchemaAccepts('{"multipleOf":3}', '10'), 'not a multiple');
  Check(SchemaAccepts('{"multipleOf":3}', '0'), 'zero is a multiple');
  Check(SchemaAccepts('{"multipleOf":0.1}', '0.3'), 'fractional multipleOf tolerates rounding');
  Check(not SchemaAccepts('{"multipleOf":0.1}', '0.35'), 'fractional miss');
  Check(SchemaIsInvalid('{"multipleOf":0}'), 'multipleOf 0 is invalid');
  Check(SchemaIsInvalid('{"multipleOf":-1}'), 'negative multipleOf is invalid');
  Check(SchemaIsInvalid('{"minimum":"1"}'), 'minimum must be a number');
  Halt(EndSuite);
end.
