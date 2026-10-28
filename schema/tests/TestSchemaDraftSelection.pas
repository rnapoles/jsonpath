{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestSchemaDraftSelection;

{$APPTYPE CONSOLE}

uses
  TestSupport, SchemaTestSupport, SysUtils, JsonSchemaErrors, JsonSchemaValidator;

procedure ValidatorTests;
var
  V: TJsonSchemaValidator;
  Raised: Boolean;
  R1, R2: TValidationResult;
begin
  V := NewValidator;
  try
    CheckEqualsStr('2020-12', V.DefaultDraftName, 'the default draft is the newest one');
    V.UseDraft('draft-07');
    CheckEqualsStr('draft-07', V.DefaultDraftName, 'UseDraft changes the default');
    Raised := False;
    try
      V.UseDraft('draft-99');
    except
      on ESchemaError do
        Raised := True;
    end;
    Check(Raised, 'selecting an unknown draft raises ESchemaError');
    CheckEqualsStr('draft-07', V.DefaultDraftName, 'a failed selection keeps the previous default');
    V.RegisterSchema('d4', '{"$schema":"http://json-schema.org/draft-04/schema#","minimum":5,"exclusiveMinimum":true}');
    V.RegisterSchema('d7', '{"minimum":5}');
    R1 := V.ValidateText('5', 'd4');
    R2 := V.ValidateText('5', 'd7');
    try
      Check(not R1.IsValid, 'each schema follows its own declared draft (draft-04)');
      Check(R2.IsValid, 'each schema follows its own draft (default draft-07)');
    finally
      R1.Free;
      R2.Free;
    end;
    CheckEqualsInt(5, V.Drafts.Count, 'five drafts are registered');
    Check(V.Drafts.FindByName('draft-06') <> nil, 'drafts can be looked up by name');
    Check(V.Drafts.FindByUri('https://json-schema.org/draft/2020-12/schema#') <> nil, 'drafts can be looked up by URI');
  finally
    V.Free;
  end;
end;

begin
  BeginSuite('Schema: draft detection and draft-specific rules');
  Check(not SchemaAccepts('{"$schema":"http://json-schema.org/draft-04/schema#","minimum":5,"exclusiveMinimum":true}', '5'), '$schema draft-04 selects boolean exclusiveMinimum');
  Check(SchemaAccepts('{"$schema":"http://json-schema.org/draft-04/schema","minimum":5,"exclusiveMinimum":true}', '6'), 'trailing # in $schema is optional');
  Check(not SchemaAccepts('{"$schema":"http://json-schema.org/draft-07/schema#","if":{"type":"integer"},"then":{"minimum":5}}', '1'), '$schema draft-07 enables if/then');
  Check(not SchemaAccepts('{"$schema":"https://json-schema.org/draft/2019-09/schema","definitions":{"s":{"type":"string"}},"properties":{"a":{"$ref":"#/definitions/s","maxLength":1}}}', '{"a":"toolong"}'), '$schema 2019-09 evaluates $ref siblings');
  Check(SchemaAccepts('{"$schema":"http://json-schema.org/draft-07/schema#","definitions":{"s":{"type":"string"}},"properties":{"a":{"$ref":"#/definitions/s","maxLength":1}}}', '{"a":"toolong"}'), '$schema draft-07 ignores $ref siblings');
  Check(not SchemaAccepts('{"minimum":5,"exclusiveMinimum":true}', '5', 'draft-04'), 'configurable default draft: draft-04');
  Check(SchemaIsInvalid('{"minimum":5,"exclusiveMinimum":true}'), 'same schema is invalid under the default 2020-12');
  Check(SchemaIsInvalid('{"$schema":"http://json-schema.org/draft-03/schema#"}'), 'unsupported $schema is a schema error');
  Check(Pos('draft-03', SchemaErrorMessage('{"$schema":"http://json-schema.org/draft-03/schema#"}')) > 0, 'the message names the unsupported draft');
  Check(Pos('supported drafts', SchemaErrorMessage('{"$schema":"http://example.com/x"}')) > 0, 'the message lists the supported drafts');
  Check(SchemaIsInvalid('{"$schema":5}'), '$schema must be a string');
  Check(SchemaIsInvalid('true', 'draft-04'), 'boolean schemas are invalid in draft-04');
  Check(not SchemaIsInvalid('true', 'draft-06'), 'boolean schemas are valid in draft-06');
  Check(SchemaIsInvalid('{"properties":{"a":true}}', 'draft-04'), 'nested boolean schemas are invalid in draft-04');
  Check(SchemaAccepts('{"const":1}', '2', 'draft-04'), 'draft-04 ignores const');
  Check(not SchemaAccepts('{"const":1}', '2', 'draft-06'), 'draft-06 knows const');
  Check(SchemaAccepts('{"if":{"type":"integer"},"then":false}', '1', 'draft-06'), 'draft-06 ignores if');
  Check(not SchemaAccepts('{"if":{"type":"integer"},"then":false}', '1', 'draft-07'), 'draft-07 knows if');
  CheckEqualsStr('', SchemaErrorInfo('{"type":"string"}'), 'valid schemas report no schema error');
  ValidatorTests;
  Halt(EndSuite);
end.
