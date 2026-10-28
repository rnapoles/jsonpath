{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit JsonSchemaEvaluator;

{ Runs a compiled schema against an instance.

  The evaluator implements TKeywordContext, so keyword validators never
  depend on it directly. One evaluator is created per validation run; it owns
  no schemas and no registries, it only borrows them.

  Evaluation of a (sub)schema:
    * boolean schema ........ true accepts everything, false rejects it
    * object schema ......... every keyword known to the schema's draft (or
                              registered at validator level) is executed in
                              the order it appears in the schema. In drafts up
                              to 07 a "$ref" replaces all of its siblings.
  Errors are appended to one list; sub-checks used for anyOf/oneOf/not/if/
  contains run quietly (their errors are discarded). }

interface

uses
  SysUtils, Classes, JSONPathCommon, JSONPathJSON, JsonSchemaErrors, JsonSchemaCore,
  JsonSchemaRegex, JsonSchemaStore;

type
  TEvalOptions = record
    AssertFormats: Boolean;
    { stop evaluating a schema object after its first failing keyword }
    StopOnFirstError: Boolean;
    MaxDepth: Integer;
  end;

  TSchemaEvaluator = class(TKeywordContext)
  private
    FStore: TSchemaStore;
    FTypes: TTypeRegistry;
    FFormats: TFormatRegistry;
    FKeywords: TKeywordRegistry;
    FRegex: TSchemaRegexCache;
    FOptions: TEvalOptions;
    FErrors: TValidationErrors;
    FOwner: TCompiledSchema;
    FSchema: TJSONValue;
    FInstance: TJSONValue;
    FKeywordValue: TJSONValue;
    FConfig: TJSONValue;
    FKeyword: string;
    FSchemaLoc: string;
    FInstLoc: string;
    FDepth: Integer;
    function KeywordLocation: string;
    function FindDefinition(const AName: string): TKeywordDefinition;
    function Evaluate(AOwner: TCompiledSchema; ASchema, AInstance: TJSONValue;
      const ASchemaLoc, AInstLoc: string): Boolean;
    procedure RunKeyword(const AName: string; AValue: TJSONValue);
    procedure RunKeywords(AMark: Integer);
  public
    constructor Create(AStore: TSchemaStore; ATypes: TTypeRegistry;
      AFormats: TFormatRegistry; AKeywords: TKeywordRegistry;
      ARegex: TSchemaRegexCache; const AOptions: TEvalOptions);
    { Validates AInstance against ACompiled. The caller owns the returned list
      (empty when the instance is valid). Raises ESchemaError when a $ref
      cannot be resolved or the evaluation nests too deeply. }
    function Run(ACompiled: TCompiledSchema; AInstance: TJSONValue): TValidationErrors;
    { TKeywordContext }
    function Instance: TJSONValue; override;
    function Schema: TJSONValue; override;
    function KeywordValue: TJSONValue; override;
    function Keyword: string; override;
    function Config: TJSONValue; override;
    function SchemaLocation: string; override;
    function InstanceLocation: string; override;
    function DraftName: string; override;
    function Sibling(const AName: string): TJSONValue; override;
    procedure AddError(const AMessage: string); override;
    function ValidateSubschema(ASubSchema, ASubInstance: TJSONValue;
      const ASchemaStep, AInstanceStep: string): Boolean; override;
    function TestSubschema(ASubSchema, ASubInstance: TJSONValue): Boolean; override;
    function ValidateSibling(const ASiblingName: string;
      ASubInstance: TJSONValue): Boolean; override;
    function ValidateReference(ARefNode, ASubInstance: TJSONValue): Boolean; override;
    function TypeMatches(const ATypeName: string; AValue: TJSONValue): Boolean; override;
    function RegexSearch(const APattern, AText: string): Boolean; override;
    function FormatValid(const AFormatName, AText: string): Boolean; override;
    function AssertFormats: Boolean; override;
  end;

implementation

constructor TSchemaEvaluator.Create(AStore: TSchemaStore; ATypes: TTypeRegistry;
  AFormats: TFormatRegistry; AKeywords: TKeywordRegistry; ARegex: TSchemaRegexCache;
  const AOptions: TEvalOptions);
begin
  inherited Create;
  FStore := AStore;
  FTypes := ATypes;
  FFormats := AFormats;
  FKeywords := AKeywords;
  FRegex := ARegex;
  FOptions := AOptions;
end;

function TSchemaEvaluator.KeywordLocation: string;
begin
  Result := FSchemaLoc + JsonPointerStep(FKeyword);
end;

function TSchemaEvaluator.FindDefinition(const AName: string): TKeywordDefinition;
begin
  Result := FKeywords.Find(AName);
  if Result = nil then
    Result := FOwner.Draft.Keywords.Find(AName);
end;

procedure TSchemaEvaluator.RunKeyword(const AName: string; AValue: TJSONValue);
var
  Def: TKeywordDefinition;
  Before: Integer;
  Ok: Boolean;
begin
  Def := FindDefinition(AName);
  if (Def = nil) or Def.Unsupported then
    Exit;
  FKeyword := AName;
  FKeywordValue := AValue;
  FConfig := Def.Config;
  Before := FErrors.Count;
  Ok := Def.Validate(Self);
  if (not Ok) and (FErrors.Count = Before) then
    AddError('value does not satisfy the "' + AName + '" keyword');
end;

procedure TSchemaEvaluator.RunKeywords(AMark: Integer);
var
  RefNode: TJSONValue;
  I: Integer;
  Schema: TJSONValue;
begin
  Schema := FSchema;
  RefNode := Schema.FindMember('$ref');
  if FOwner.Draft.RefOverridesSiblings and (RefNode <> nil) and (RefNode.Kind = jkString) then
  begin
    RunKeyword('$ref', RefNode);
    Exit;
  end;
  for I := 0 to Schema.Count - 1 do
  begin
    RunKeyword(Schema.Names[I], Schema[I]);
    if FOptions.StopOnFirstError and (FErrors.Count > AMark) then
      Break;
  end;
end;

function TSchemaEvaluator.Evaluate(AOwner: TCompiledSchema; ASchema, AInstance: TJSONValue;
  const ASchemaLoc, AInstLoc: string): Boolean;
var
  SOwner: TCompiledSchema;
  SSchema, SInstance, SValue, SConfig: TJSONValue;
  SKeyword, SSchemaLoc, SInstLoc: string;
  Mark: Integer;
begin
  Inc(FDepth);
  try
    if FDepth > FOptions.MaxDepth then
      RaiseSchemaError('maximum evaluation depth exceeded; the schema probably contains ' +
        'a circular $ref', '', ASchemaLoc);
    SOwner := FOwner;
    SSchema := FSchema;
    SInstance := FInstance;
    SValue := FKeywordValue;
    SConfig := FConfig;
    SKeyword := FKeyword;
    SSchemaLoc := FSchemaLoc;
    SInstLoc := FInstLoc;
    try
      FOwner := AOwner;
      FSchema := ASchema;
      FInstance := AInstance;
      FSchemaLoc := ASchemaLoc;
      FInstLoc := AInstLoc;
      FKeyword := '';
      Mark := FErrors.Count;
      if ASchema.Kind = jkBoolean then
      begin
        if not ASchema.BoolValue then
          FErrors.AddNew('no value is allowed here (the schema is false)', '',
            ASchemaLoc, AInstLoc);
      end
      else if ASchema.Kind = jkObject then
        RunKeywords(Mark);
      Result := FErrors.Count = Mark;
    finally
      FOwner := SOwner;
      FSchema := SSchema;
      FInstance := SInstance;
      FKeywordValue := SValue;
      FConfig := SConfig;
      FKeyword := SKeyword;
      FSchemaLoc := SSchemaLoc;
      FInstLoc := SInstLoc;
    end;
  finally
    Dec(FDepth);
  end;
end;

function TSchemaEvaluator.Run(ACompiled: TCompiledSchema;
  AInstance: TJSONValue): TValidationErrors;
begin
  Result := TValidationErrors.Create;
  FErrors := Result;
  FDepth := 0;
  try
    Evaluate(ACompiled, ACompiled.Root, AInstance, '', '');
  except
    FErrors := nil;
    Result.Free;
    raise;
  end;
  FErrors := nil;
end;

{ ---- TKeywordContext ---- }

function TSchemaEvaluator.Instance: TJSONValue;
begin
  Result := FInstance;
end;

function TSchemaEvaluator.Schema: TJSONValue;
begin
  Result := FSchema;
end;

function TSchemaEvaluator.KeywordValue: TJSONValue;
begin
  Result := FKeywordValue;
end;

function TSchemaEvaluator.Keyword: string;
begin
  Result := FKeyword;
end;

function TSchemaEvaluator.Config: TJSONValue;
begin
  Result := FConfig;
end;

function TSchemaEvaluator.SchemaLocation: string;
begin
  Result := KeywordLocation;
end;

function TSchemaEvaluator.InstanceLocation: string;
begin
  Result := FInstLoc;
end;

function TSchemaEvaluator.DraftName: string;
begin
  Result := FOwner.Draft.Name;
end;

function TSchemaEvaluator.Sibling(const AName: string): TJSONValue;
begin
  Result := FSchema.FindMember(AName);
end;

procedure TSchemaEvaluator.AddError(const AMessage: string);
begin
  FErrors.AddNew(AMessage, FKeyword, KeywordLocation, FInstLoc);
end;

function TSchemaEvaluator.ValidateSubschema(ASubSchema, ASubInstance: TJSONValue;
  const ASchemaStep, AInstanceStep: string): Boolean;
begin
  Result := Evaluate(FOwner, ASubSchema, ASubInstance, KeywordLocation + ASchemaStep,
    FInstLoc + AInstanceStep);
end;

function TSchemaEvaluator.TestSubschema(ASubSchema, ASubInstance: TJSONValue): Boolean;
var
  Mark: Integer;
begin
  Mark := FErrors.Count;
  Result := Evaluate(FOwner, ASubSchema, ASubInstance, KeywordLocation, FInstLoc);
  FErrors.TruncateTo(Mark);
end;

function TSchemaEvaluator.ValidateSibling(const ASiblingName: string;
  ASubInstance: TJSONValue): Boolean;
var
  Sub: TJSONValue;
begin
  Sub := FSchema.FindMember(ASiblingName);
  if Sub = nil then
    Result := True
  else
    Result := Evaluate(FOwner, Sub, ASubInstance, FSchemaLoc + JsonPointerStep(ASiblingName),
      FInstLoc);
end;

function TSchemaEvaluator.ValidateReference(ARefNode, ASubInstance: TJSONValue): Boolean;
var
  Entry: TRefEntry;
  Msg: string;
begin
  Entry := FOwner.FindRef(ARefNode);
  if Entry = nil then
    RaiseSchemaError('internal error: the $ref was not compiled', '$ref', KeywordLocation);
  if not Entry.Resolved then
    if FStore.TryResolve(FOwner, Entry, Msg) <> roOk then
      RaiseSchemaError(Msg, '$ref', KeywordLocation);
  Result := Evaluate(Entry.TargetOwner, Entry.TargetNode, ASubInstance, KeywordLocation,
    FInstLoc);
end;

function TSchemaEvaluator.TypeMatches(const ATypeName: string; AValue: TJSONValue): Boolean;
begin
  Result := FTypes.Matches(ATypeName, AValue);
end;

function TSchemaEvaluator.RegexSearch(const APattern, AText: string): Boolean;
begin
  Result := FRegex.Search(APattern, AText);
end;

function TSchemaEvaluator.FormatValid(const AFormatName, AText: string): Boolean;
begin
  Result := FFormats.Check(AFormatName, AText);
end;

function TSchemaEvaluator.AssertFormats: Boolean;
begin
  Result := FOptions.AssertFormats;
end;

end.
