{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestSchemaCustomDraft;

{$APPTYPE CONSOLE}

uses
  TestSupport, SchemaTestSupport, SysUtils, JSONPathJSON, JsonSchemaCore, JsonSchemaErrors,
  JsonSchemaDrafts, JsonSchemaValidator;

type
  { A new "draft" added WITHOUT touching any existing draft class }
  TDraftStrict = class(TJsonSchemaDraft202012)
  protected
    procedure RegisterKeywords; override;
  public
    function Name: string; override;
    function MetaSchemaUri: string; override;
  end;

function KwNoNulls(Ctx: TKeywordContext): Boolean;
var
  I: Integer;
begin
  Result := True;
  if (Ctx.Instance.Kind <> jkObject) or not Ctx.KeywordValue.BoolValue then
    Exit;
  for I := 0 to Ctx.Instance.Count - 1 do
    if Ctx.Instance[I].Kind = jkNull then
    begin
      Ctx.AddError('property "' + Ctx.Instance.Names[I] + '" must not be null');
      Result := False;
    end;
end;

procedure TDraftStrict.RegisterKeywords;
begin
  inherited RegisterKeywords;
  Keywords.RegisterKeyword('noNulls', KwNoNulls, '', nil, True);
end;

function TDraftStrict.Name: string;
begin
  Result := 'strict-2020';
end;

function TDraftStrict.MetaSchemaUri: string;
begin
  Result := 'http://example.com/strict-schema';
end;

function Valid(V: TJsonSchemaValidator; const ASchema, AInstance: string): Boolean;
var
  R: TValidationResult;
begin
  V.RegisterSchema('s', ASchema);
  try
    R := V.ValidateText(AInstance, 's');
    try
      Result := R.IsValid;
    finally
      R.Free;
    end;
  finally
    V.UnregisterSchema('s');
  end;
end;

var
  V: TJsonSchemaValidator;
  Raised: Boolean;
begin
  BeginSuite('Schema: adding a draft without modifying existing ones');
  V := NewValidator;
  try
    V.Drafts.RegisterDraft(TDraftStrict.Create);
    CheckEqualsInt(6, V.Drafts.Count, 'the new draft is registered next to the built-in ones');
    Check(V.Drafts.FindByUri('http://example.com/strict-schema#') <> nil, 'it can be found by its meta-schema URI');
    Check(not Valid(V, '{"$schema":"http://example.com/strict-schema","noNulls":true}', '{"a":null}'),
      'the new draft brings its own keyword');
    Check(Valid(V, '{"$schema":"http://example.com/strict-schema","noNulls":true}', '{"a":1}'),
      'the new draft keeps the inherited behaviour');
    Check(not Valid(V, '{"$schema":"http://example.com/strict-schema","type":"integer"}', '"x"'),
      'inherited keywords still work in the new draft');
    Check(Valid(V, '{"noNulls":true}', '{"a":null}'), 'other drafts do not know the new keyword');
    Check(Valid(V, '{"$schema":"http://json-schema.org/draft-07/schema#","noNulls":true}', '{"a":null}'),
      'existing drafts are unchanged (draft-07)');

    Raised := False;
    try
      V.Drafts.RegisterDraft(TDraftStrict.Create);
    except
      on ESchemaRegistrationError do
        Raised := True;
    end;
    Check(Raised, 'registering the same draft twice raises ESchemaRegistrationError');
    CheckEqualsInt(6, V.Drafts.Count, 'a rejected draft is not added');

    V.UseDraft('strict-2020');
    Check(not Valid(V, '{"noNulls":true}', '{"a":null}'), 'the new draft can become the default draft');
  finally
    V.Free;
  end;
  Halt(EndSuite);
end.
