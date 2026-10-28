{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit JsonSchemaDrafts;

{ The supported JSON Schema drafts. Each class derives from the previous
  draft and only states what CHANGED, so adding "draft N+1" never requires
  touching an existing class:

    TJsonSchemaDraft4        id, boolean exclusiveMinimum/Maximum, no boolean
                             schemas, $ref overrides its siblings
    TJsonSchemaDraft6        $id, numeric exclusiveMinimum/Maximum, const,
                             contains, propertyNames, boolean schemas
    TJsonSchemaDraft7        if / then / else
    TJsonSchemaDraft201909   dependentRequired/dependentSchemas, minContains/
                             maxContains, $defs, $anchor, $ref with siblings
    TJsonSchemaDraft202012   prefixItems and the new meaning of items

  Keywords that exist in a draft but are not implemented here
  (unevaluatedItems, unevaluatedProperties, $recursiveRef, $dynamicRef, ...)
  are registered as UNSUPPORTED: a schema that uses them is rejected instead
  of being silently ignored. }

interface

uses
  SysUtils, JsonSchemaCore, JsonSchemaKeywords;

type
  TJsonSchemaDraft4 = class(TJsonSchemaDraft)
  protected
    procedure RegisterKeywords; override;
  public
    function Name: string; override;
    function MetaSchemaUri: string; override;
    function IdKeyword: string; override;
    function RefOverridesSiblings: Boolean; override;
    function SupportsBooleanSchemas: Boolean; override;
  end;

  TJsonSchemaDraft6 = class(TJsonSchemaDraft4)
  protected
    procedure RegisterKeywords; override;
  public
    function Name: string; override;
    function MetaSchemaUri: string; override;
    function IdKeyword: string; override;
    function SupportsBooleanSchemas: Boolean; override;
  end;

  TJsonSchemaDraft7 = class(TJsonSchemaDraft6)
  protected
    procedure RegisterKeywords; override;
  public
    function Name: string; override;
    function MetaSchemaUri: string; override;
  end;

  TJsonSchemaDraft201909 = class(TJsonSchemaDraft7)
  protected
    procedure RegisterKeywords; override;
  public
    function Name: string; override;
    function MetaSchemaUri: string; override;
    function RefOverridesSiblings: Boolean; override;
  end;

  TJsonSchemaDraft202012 = class(TJsonSchemaDraft201909)
  protected
    procedure RegisterKeywords; override;
  public
    function Name: string; override;
    function MetaSchemaUri: string; override;
  end;

{ Registers all drafts above; the newest one becomes the default draft }
procedure RegisterBuiltinDrafts(ARegistry: TDraftRegistry);

implementation

{ shorthand used by every RegisterKeywords: later drafts replace earlier
  definitions, hence AllowOverride = True }
procedure Reg(AReg: TKeywordRegistry; const AName: string;
  AValidator: TKeywordValidatorFunc; AChecker: TKeywordCheckerProc);
begin
  AReg.RegisterKeyword(AName, AValidator, '', AChecker, True);
end;

procedure Struct(AReg: TKeywordRegistry; const AName: string; AChecker: TKeywordCheckerProc);
begin
  AReg.RegisterStructural(AName, AChecker, True);
end;

{ ---- Draft 4 ---- }

procedure TJsonSchemaDraft4.RegisterKeywords;
var
  K: TKeywordRegistry;
begin
  K := Keywords;
  Reg(K, 'type', KwType, CheckType);
  Reg(K, 'enum', KwEnum, CheckEnumLegacy);
  Reg(K, 'allOf', KwAllOf, CheckSchemaArray);
  Reg(K, 'anyOf', KwAnyOf, CheckSchemaArray);
  Reg(K, 'oneOf', KwOneOf, CheckSchemaArray);
  Reg(K, 'not', KwNot, CheckSchema);
  Reg(K, 'properties', KwProperties, CheckSchemaMap);
  Reg(K, 'patternProperties', KwPatternProperties, CheckPatternMap);
  Reg(K, 'additionalProperties', KwAdditionalProperties, CheckSchema);
  Reg(K, 'required', KwRequired, CheckRequiredLegacy);
  Reg(K, 'minProperties', KwMinProperties, CheckNonNegativeInteger);
  Reg(K, 'maxProperties', KwMaxProperties, CheckNonNegativeInteger);
  Reg(K, 'dependencies', KwDependencies, CheckDependencies);
  Reg(K, 'items', KwItems, CheckItems);
  Reg(K, 'additionalItems', KwAdditionalItems, CheckSchema);
  Reg(K, 'minItems', KwMinItems, CheckNonNegativeInteger);
  Reg(K, 'maxItems', KwMaxItems, CheckNonNegativeInteger);
  Reg(K, 'uniqueItems', KwUniqueItems, CheckBoolean);
  Reg(K, 'minimum', KwMinimumD4, CheckNumber);
  Reg(K, 'maximum', KwMaximumD4, CheckNumber);
  Struct(K, 'exclusiveMinimum', CheckExclusiveMinimumD4);
  Struct(K, 'exclusiveMaximum', CheckExclusiveMaximumD4);
  Reg(K, 'multipleOf', KwMultipleOf, CheckPositiveNumber);
  Reg(K, 'minLength', KwMinLength, CheckNonNegativeInteger);
  Reg(K, 'maxLength', KwMaxLength, CheckNonNegativeInteger);
  Reg(K, 'pattern', KwPattern, CheckPatternValue);
  Reg(K, 'format', KwFormat, CheckString);
  Reg(K, '$ref', KwRef, CheckRef);
  Struct(K, 'definitions', CheckSchemaMap);
  Struct(K, 'id', CheckString);
end;

function TJsonSchemaDraft4.Name: string;
begin
  Result := 'draft-04';
end;

function TJsonSchemaDraft4.MetaSchemaUri: string;
begin
  Result := 'http://json-schema.org/draft-04/schema';
end;

function TJsonSchemaDraft4.IdKeyword: string;
begin
  Result := 'id';
end;

function TJsonSchemaDraft4.RefOverridesSiblings: Boolean;
begin
  Result := True;
end;

function TJsonSchemaDraft4.SupportsBooleanSchemas: Boolean;
begin
  Result := False;
end;

{ ---- Draft 6 ---- }

procedure TJsonSchemaDraft6.RegisterKeywords;
var
  K: TKeywordRegistry;
begin
  inherited RegisterKeywords;
  K := Keywords;
  K.Unregister('id');
  Struct(K, '$id', CheckString);
  Reg(K, 'enum', KwEnum, CheckArray);
  Reg(K, 'required', KwRequired, CheckRequired);
  Reg(K, 'minimum', KwMinimum, CheckNumber);
  Reg(K, 'maximum', KwMaximum, CheckNumber);
  Reg(K, 'exclusiveMinimum', KwExclusiveMinimum, CheckNumber);
  Reg(K, 'exclusiveMaximum', KwExclusiveMaximum, CheckNumber);
  Reg(K, 'const', KwConst, nil);
  Reg(K, 'contains', KwContains, CheckSchema);
  Reg(K, 'propertyNames', KwPropertyNames, CheckSchema);
end;

function TJsonSchemaDraft6.Name: string;
begin
  Result := 'draft-06';
end;

function TJsonSchemaDraft6.MetaSchemaUri: string;
begin
  Result := 'http://json-schema.org/draft-06/schema';
end;

function TJsonSchemaDraft6.IdKeyword: string;
begin
  Result := '$id';
end;

function TJsonSchemaDraft6.SupportsBooleanSchemas: Boolean;
begin
  Result := True;
end;

{ ---- Draft 7 ---- }

procedure TJsonSchemaDraft7.RegisterKeywords;
var
  K: TKeywordRegistry;
begin
  inherited RegisterKeywords;
  K := Keywords;
  Reg(K, 'if', KwIf, CheckSchema);
  Struct(K, 'then', CheckSchema);
  Struct(K, 'else', CheckSchema);
end;

function TJsonSchemaDraft7.Name: string;
begin
  Result := 'draft-07';
end;

function TJsonSchemaDraft7.MetaSchemaUri: string;
begin
  Result := 'http://json-schema.org/draft-07/schema';
end;

{ ---- Draft 2019-09 ---- }

procedure TJsonSchemaDraft201909.RegisterKeywords;
var
  K: TKeywordRegistry;
begin
  inherited RegisterKeywords;
  K := Keywords;
  K.Unregister('dependencies');
  Reg(K, 'dependentRequired', KwDependentRequired, CheckDependentRequired);
  Reg(K, 'dependentSchemas', KwDependentSchemas, CheckSchemaMap);
  Reg(K, 'contains', KwContainsCounting, CheckSchema);
  Struct(K, 'minContains', CheckNonNegativeInteger);
  Struct(K, 'maxContains', CheckNonNegativeInteger);
  Struct(K, '$defs', CheckSchemaMap);
  Struct(K, '$anchor', CheckAnchor);
  K.RegisterUnsupported('$recursiveRef');
  K.RegisterUnsupported('$recursiveAnchor');
  K.RegisterUnsupported('unevaluatedItems');
  K.RegisterUnsupported('unevaluatedProperties');
end;

function TJsonSchemaDraft201909.Name: string;
begin
  Result := '2019-09';
end;

function TJsonSchemaDraft201909.MetaSchemaUri: string;
begin
  Result := 'https://json-schema.org/draft/2019-09/schema';
end;

function TJsonSchemaDraft201909.RefOverridesSiblings: Boolean;
begin
  Result := False;
end;

{ ---- Draft 2020-12 ---- }

procedure TJsonSchemaDraft202012.RegisterKeywords;
var
  K: TKeywordRegistry;
begin
  inherited RegisterKeywords;
  K := Keywords;
  K.Unregister('additionalItems');
  K.Unregister('$recursiveRef');
  K.Unregister('$recursiveAnchor');
  Reg(K, 'prefixItems', KwPrefixItems, CheckSchemaArray);
  Reg(K, 'items', KwItems2020, CheckSchema);
  K.RegisterUnsupported('$dynamicRef');
  K.RegisterUnsupported('$dynamicAnchor');
end;

function TJsonSchemaDraft202012.Name: string;
begin
  Result := '2020-12';
end;

function TJsonSchemaDraft202012.MetaSchemaUri: string;
begin
  Result := 'https://json-schema.org/draft/2020-12/schema';
end;

procedure RegisterBuiltinDrafts(ARegistry: TDraftRegistry);
begin
  ARegistry.RegisterDraft(TJsonSchemaDraft4.Create);
  ARegistry.RegisterDraft(TJsonSchemaDraft6.Create);
  ARegistry.RegisterDraft(TJsonSchemaDraft7.Create);
  ARegistry.RegisterDraft(TJsonSchemaDraft201909.Create);
  ARegistry.RegisterDraft(TJsonSchemaDraft202012.Create);
  ARegistry.DefaultDraftName := '2020-12';
end;

end.
