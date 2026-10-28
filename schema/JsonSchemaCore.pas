{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit JsonSchemaCore;

{ Abstractions and registries of the JSON Schema framework.

  Dependency direction (low to high):
    JsonSchemaErrors -> JsonSchemaCore -> Keywords / Drafts -> Store ->
    Evaluator -> Validator
  Keyword implementations only see the abstract TKeywordContext /
  TCompileContext classes declared here, never the concrete engines.

  REGISTRATION POLICY (applies to types, formats and keywords)
    * Registering a NEW name always succeeds.
    * Registering a name that already exists in the same registry raises
      ESchemaRegistrationError, unless AllowOverride is True, in which case the
      new definition replaces the old one.
    * Validator-level registries (types, formats, keywords) are shared by all
      drafts; a validator-level keyword takes precedence over a draft's own
      definition of the same name.
    * Draft-level keyword tables (TJsonSchemaDraft.Keywords) are private to
      that draft; use them for draft-specific extensions. }

interface

uses
  SysUtils, Classes, JSONPathCommon, JSONPathJSON, JsonSchemaErrors;

type
  TDuplicatePolicy = (dpRaise, dpReplace, dpSkip);

  { ---- what keyword code is allowed to see ---- }

  { Passed to a keyword validator while an instance is being validated }
  TKeywordContext = class
  public
    { the value being validated }
    function Instance: TJSONValue; virtual; abstract;
    { the schema object that contains the keyword }
    function Schema: TJSONValue; virtual; abstract;
    { the keyword's value in the schema: its parameter }
    function KeywordValue: TJSONValue; virtual; abstract;
    function Keyword: string; virtual; abstract;
    { registration-time configuration (nil when none was given) }
    function Config: TJSONValue; virtual; abstract;
    function SchemaLocation: string; virtual; abstract;
    function InstanceLocation: string; virtual; abstract;
    function DraftName: string; virtual; abstract;
    { another keyword of the same schema object (nil when absent) }
    function Sibling(const AName: string): TJSONValue; virtual; abstract;
    { Reports a failure of the current keyword at the current instance }
    procedure AddError(const AMessage: string); virtual; abstract;
    { Validates ASubInstance against ASubSchema and reports its errors.
      The steps extend the schema/instance locations, e.g. JsonPointerStep. }
    function ValidateSubschema(ASubSchema, ASubInstance: TJSONValue;
      const ASchemaStep, AInstanceStep: string): Boolean; virtual; abstract;
    { Same check without reporting any error }
    function TestSubschema(ASubSchema, ASubInstance: TJSONValue): Boolean;
      virtual; abstract;
    { Validates the value of the sibling keyword ASiblingName (a schema) }
    function ValidateSibling(const ASiblingName: string;
      ASubInstance: TJSONValue): Boolean; virtual; abstract;
    { Follows a $ref value node (as given by KeywordValue) }
    function ValidateReference(ARefNode, ASubInstance: TJSONValue): Boolean;
      virtual; abstract;
    function TypeMatches(const ATypeName: string; AValue: TJSONValue): Boolean;
      virtual; abstract;
    function RegexSearch(const APattern, AText: string): Boolean; virtual; abstract;
    { True for unknown formats }
    function FormatValid(const AFormatName, AText: string): Boolean; virtual; abstract;
    function AssertFormats: Boolean; virtual; abstract;
  end;

  { Passed to a keyword checker while a schema is being compiled }
  TCompileContext = class
  public
    function Schema: TJSONValue; virtual; abstract;
    function KeywordValue: TJSONValue; virtual; abstract;
    function Keyword: string; virtual; abstract;
    function Config: TJSONValue; virtual; abstract;
    function SchemaLocation: string; virtual; abstract;
    function DraftName: string; virtual; abstract;
    function Sibling(const AName: string): TJSONValue; virtual; abstract;
    { Reports that the keyword's value is invalid }
    procedure Error(const AMessage: string); virtual; abstract;
    { The keyword value itself is a (sub)schema }
    procedure CompileSubschema(ASubSchema: TJSONValue); virtual; abstract;
    { A member or element of the keyword value is a (sub)schema }
    procedure CompileChild(ASubSchema: TJSONValue; const AToken: string);
      virtual; abstract;
    function IsKnownType(const ATypeName: string): Boolean; virtual; abstract;
    { Reports an error when the pattern cannot be used }
    procedure CheckPattern(const APattern: string); virtual; abstract;
    { Records a $ref value node so that it is resolved against the store }
    procedure RegisterRef(ARefNode: TJSONValue); virtual; abstract;
    procedure DeclareAnchor(const AName: string); virtual; abstract;
  end;

  { ---- callback types ---- }

  { Return True when the instance satisfies the keyword. When returning False
    without calling Ctx.AddError a generic message is reported. }
  TKeywordValidatorFunc = function(Ctx: TKeywordContext): Boolean;
  TKeywordValidatorMethod = function(Ctx: TKeywordContext): Boolean of object;
  { Checks the shape of the keyword value in the schema; report problems with
    Ctx.Error and recurse into subschemas with Ctx.CompileSubschema/Child }
  TKeywordCheckerProc = procedure(Ctx: TCompileContext);
  TTypeCheckerFunc = function(AValue: TJSONValue): Boolean;
  TTypeCheckerMethod = function(AValue: TJSONValue): Boolean of object;
  TFormatCheckerFunc = function(const AText: string): Boolean;
  TFormatCheckerMethod = function(const AText: string): Boolean of object;

  { ---- name -> definition table shared by the registries ---- }

  TNamedTable = class
  private
    FNames: TStringArray;
    FCount: Integer;
    FItems: TOwnedList;
    function GetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function IndexOf(const AName: string): Integer;
    function Find(const AName: string): TObject;
    { Takes ownership of AItem (also when raising) }
    procedure Put(const AName: string; AItem: TObject; AllowOverride: Boolean;
      const AWhat: string);
    function Remove(const AName: string): Boolean;
    function NameAt(AIndex: Integer): string;
    property Count: Integer read GetCount;
  end;

  { ---- types ---- }

  TTypeDefinition = class
  private
    FName: string;
    FFunc: TTypeCheckerFunc;
    FMethod: TTypeCheckerMethod;
  public
    constructor Create(const AName: string; AFunc: TTypeCheckerFunc;
      AMethod: TTypeCheckerMethod);
    function Matches(AValue: TJSONValue): Boolean;
    property Name: string read FName;
  end;

  TTypeRegistry = class
  private
    FTable: TNamedTable;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterType(const AName: string; AChecker: TTypeCheckerFunc;
      AllowOverride: Boolean = False); overload;
    procedure RegisterType(const AName: string; AChecker: TTypeCheckerMethod;
      AllowOverride: Boolean = False); overload;
    function Unregister(const AName: string): Boolean;
    function IsRegistered(const AName: string): Boolean;
    { False for unregistered names }
    function Matches(const AName: string; AValue: TJSONValue): Boolean;
    function Count: Integer;
    function NameAt(AIndex: Integer): string;
  end;

  { ---- formats ---- }

  TFormatDefinition = class
  private
    FName: string;
    FFunc: TFormatCheckerFunc;
    FMethod: TFormatCheckerMethod;
  public
    constructor Create(const AName: string; AFunc: TFormatCheckerFunc;
      AMethod: TFormatCheckerMethod);
    function Check(const AText: string): Boolean;
    property Name: string read FName;
  end;

  TFormatRegistry = class
  private
    FTable: TNamedTable;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterFormat(const AName: string; AChecker: TFormatCheckerFunc;
      AllowOverride: Boolean = False); overload;
    procedure RegisterFormat(const AName: string; AChecker: TFormatCheckerMethod;
      AllowOverride: Boolean = False); overload;
    function Unregister(const AName: string): Boolean;
    function IsRegistered(const AName: string): Boolean;
    { True for formats that are not registered (they are annotations only) }
    function Check(const AName, AText: string): Boolean;
    function Count: Integer;
  end;

  { ---- keywords ---- }

  TKeywordDefinition = class
  private
    FName: string;
    FFunc: TKeywordValidatorFunc;
    FMethod: TKeywordValidatorMethod;
    FChecker: TKeywordCheckerProc;
    FConfig: TJSONValue;
    FUnsupported: Boolean;
  public
    constructor Create(const AName: string; AFunc: TKeywordValidatorFunc;
      AMethod: TKeywordValidatorMethod; AChecker: TKeywordCheckerProc;
      AConfig: TJSONValue; AUnsupported: Boolean);
    destructor Destroy; override;
    function Validate(Ctx: TKeywordContext): Boolean;
    property Name: string read FName;
    property Checker: TKeywordCheckerProc read FChecker;
    property Config: TJSONValue read FConfig;
    { Known keyword that this implementation cannot evaluate }
    property Unsupported: Boolean read FUnsupported;
  end;

  TKeywordRegistry = class
  private
    FTable: TNamedTable;
    procedure Put(const AName: string; ADef: TKeywordDefinition;
      AllowOverride: Boolean);
    function ParseConfig(const AName, AConfigJson: string): TJSONValue;
  public
    constructor Create;
    destructor Destroy; override;
    { A validating keyword. AConfigJson is optional JSON text handed to the
      validator as Ctx.Config; AChecker optionally validates the keyword's
      value when a schema is compiled. }
    procedure RegisterKeyword(const AName: string; AValidator: TKeywordValidatorFunc;
      const AConfigJson: string = ''; AChecker: TKeywordCheckerProc = nil;
      AllowOverride: Boolean = False); overload;
    procedure RegisterKeyword(const AName: string; AValidator: TKeywordValidatorMethod;
      const AConfigJson: string = ''; AChecker: TKeywordCheckerProc = nil;
      AllowOverride: Boolean = False); overload;
    { A keyword that is only checked/compiled (e.g. "definitions", "then") }
    procedure RegisterStructural(const AName: string; AChecker: TKeywordCheckerProc;
      AllowOverride: Boolean = False);
    { A keyword of the draft that this implementation does not evaluate; any
      schema using it is rejected unless unsupported keywords are ignored }
    procedure RegisterUnsupported(const AName: string);
    function Unregister(const AName: string): Boolean;
    function Find(const AName: string): TKeywordDefinition;
    function IsRegistered(const AName: string): Boolean;
    function Count: Integer;
    function NameAt(AIndex: Integer): string;
  end;

  { ---- drafts ---- }

  { Base class of every supported JSON Schema draft. A draft owns its keyword
    table and describes the few structural rules that differ between drafts.
    To add a draft: derive a class, override the abstract members and
    RegisterKeywords (call inherited to reuse a previous draft), then pass an
    instance to TDraftRegistry.RegisterDraft. }
  TJsonSchemaDraft = class
  private
    FKeywords: TKeywordRegistry;
  protected
    procedure RegisterKeywords; virtual; abstract;
  public
    constructor Create;
    destructor Destroy; override;
    { short unique name, e.g. 'draft-07' }
    function Name: string; virtual; abstract;
    { the value of "$schema" without a trailing '#' }
    function MetaSchemaUri: string; virtual; abstract;
    { keyword that identifies a schema resource: 'id' or '$id' }
    function IdKeyword: string; virtual;
    { True when siblings of $ref are ignored (drafts up to 07) }
    function RefOverridesSiblings: Boolean; virtual;
    function SupportsBooleanSchemas: Boolean; virtual;
    property Keywords: TKeywordRegistry read FKeywords;
  end;

  TDraftRegistry = class
  private
    FDrafts: TOwnedList;
    FDefaultName: string;
    procedure SetDefaultName(const AValue: string);
  public
    constructor Create;
    destructor Destroy; override;
    { Takes ownership of ADraft; names and URIs must be unique }
    procedure RegisterDraft(ADraft: TJsonSchemaDraft);
    function FindByName(const AName: string): TJsonSchemaDraft;
    function FindByUri(const AUri: string): TJsonSchemaDraft;
    { Draft declared by "$schema" of ASchema, or the default draft when the
      schema declares none. Raises ESchemaError for unknown drafts. }
    function DraftForSchema(ASchema: TJSONValue): TJsonSchemaDraft;
    function DefaultDraft: TJsonSchemaDraft;
    function SupportedNames: string;
    function Count: Integer;
    function Items(AIndex: Integer): TJsonSchemaDraft;
    property DefaultDraftName: string read FDefaultName write SetDefaultName;
  end;

function NormalizeSchemaUri(const AUri: string): string;

implementation

{ ---- TNamedTable ---- }

constructor TNamedTable.Create;
begin
  inherited Create;
  FItems := TOwnedList.Create;
end;

destructor TNamedTable.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TNamedTable.GetCount: Integer;
begin
  Result := FCount;
end;

function TNamedTable.IndexOf(const AName: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to FCount - 1 do
    if FNames[I] = AName then
    begin
      Result := I;
      Exit;
    end;
end;

function TNamedTable.Find(const AName: string): TObject;
var
  Idx: Integer;
begin
  Idx := IndexOf(AName);
  if Idx >= 0 then
    Result := FItems[Idx]
  else
    Result := nil;
end;

procedure TNamedTable.Put(const AName: string; AItem: TObject;
  AllowOverride: Boolean; const AWhat: string);
var
  Idx: Integer;
begin
  if AName = '' then
  begin
    AItem.Free;
    raise ESchemaRegistrationError.Create(AWhat + ' names must not be empty');
  end;
  Idx := IndexOf(AName);
  if Idx >= 0 then
  begin
    if not AllowOverride then
    begin
      AItem.Free;
      raise ESchemaRegistrationError.CreateFmt(
        '%s "%s" is already registered; pass AllowOverride=True to replace it',
        [AWhat, AName]);
    end;
    FItems.Replace(Idx, AItem);
  end
  else
  begin
    if FCount >= Length(FNames) then
      SetLength(FNames, FCount * 2 + 8);
    FNames[FCount] := AName;
    Inc(FCount);
    FItems.Add(AItem);
  end;
end;

function TNamedTable.Remove(const AName: string): Boolean;
var
  Idx, I: Integer;
begin
  Idx := IndexOf(AName);
  Result := Idx >= 0;
  if not Result then
    Exit;
  FItems.Delete(Idx);
  for I := Idx to FCount - 2 do
    FNames[I] := FNames[I + 1];
  Dec(FCount);
end;

function TNamedTable.NameAt(AIndex: Integer): string;
begin
  Result := FNames[AIndex];
end;

{ ---- types ---- }

constructor TTypeDefinition.Create(const AName: string; AFunc: TTypeCheckerFunc;
  AMethod: TTypeCheckerMethod);
begin
  inherited Create;
  FName := AName;
  FFunc := AFunc;
  FMethod := AMethod;
end;

function TTypeDefinition.Matches(AValue: TJSONValue): Boolean;
begin
  if Assigned(FFunc) then
    Result := FFunc(AValue)
  else
    Result := FMethod(AValue);
end;

constructor TTypeRegistry.Create;
begin
  inherited Create;
  FTable := TNamedTable.Create;
end;

destructor TTypeRegistry.Destroy;
begin
  FTable.Free;
  inherited Destroy;
end;

procedure TTypeRegistry.RegisterType(const AName: string; AChecker: TTypeCheckerFunc;
  AllowOverride: Boolean);
begin
  if not Assigned(AChecker) then
    raise ESchemaRegistrationError.Create('A checker is required for type "' + AName + '"');
  FTable.Put(AName, TTypeDefinition.Create(AName, AChecker, nil), AllowOverride, 'Type');
end;

procedure TTypeRegistry.RegisterType(const AName: string; AChecker: TTypeCheckerMethod;
  AllowOverride: Boolean);
begin
  if not Assigned(AChecker) then
    raise ESchemaRegistrationError.Create('A checker is required for type "' + AName + '"');
  FTable.Put(AName, TTypeDefinition.Create(AName, nil, AChecker), AllowOverride, 'Type');
end;

function TTypeRegistry.Unregister(const AName: string): Boolean;
begin
  Result := FTable.Remove(AName);
end;

function TTypeRegistry.IsRegistered(const AName: string): Boolean;
begin
  Result := FTable.IndexOf(AName) >= 0;
end;

function TTypeRegistry.Matches(const AName: string; AValue: TJSONValue): Boolean;
var
  Def: TObject;
begin
  Def := FTable.Find(AName);
  Result := (Def <> nil) and TTypeDefinition(Def).Matches(AValue);
end;

function TTypeRegistry.Count: Integer;
begin
  Result := FTable.Count;
end;

function TTypeRegistry.NameAt(AIndex: Integer): string;
begin
  Result := FTable.NameAt(AIndex);
end;

{ ---- formats ---- }

constructor TFormatDefinition.Create(const AName: string; AFunc: TFormatCheckerFunc;
  AMethod: TFormatCheckerMethod);
begin
  inherited Create;
  FName := AName;
  FFunc := AFunc;
  FMethod := AMethod;
end;

function TFormatDefinition.Check(const AText: string): Boolean;
begin
  if Assigned(FFunc) then
    Result := FFunc(AText)
  else
    Result := FMethod(AText);
end;

constructor TFormatRegistry.Create;
begin
  inherited Create;
  FTable := TNamedTable.Create;
end;

destructor TFormatRegistry.Destroy;
begin
  FTable.Free;
  inherited Destroy;
end;

procedure TFormatRegistry.RegisterFormat(const AName: string;
  AChecker: TFormatCheckerFunc; AllowOverride: Boolean);
begin
  if not Assigned(AChecker) then
    raise ESchemaRegistrationError.Create('A checker is required for format "' + AName + '"');
  FTable.Put(AName, TFormatDefinition.Create(AName, AChecker, nil), AllowOverride, 'Format');
end;

procedure TFormatRegistry.RegisterFormat(const AName: string;
  AChecker: TFormatCheckerMethod; AllowOverride: Boolean);
begin
  if not Assigned(AChecker) then
    raise ESchemaRegistrationError.Create('A checker is required for format "' + AName + '"');
  FTable.Put(AName, TFormatDefinition.Create(AName, nil, AChecker), AllowOverride, 'Format');
end;

function TFormatRegistry.Unregister(const AName: string): Boolean;
begin
  Result := FTable.Remove(AName);
end;

function TFormatRegistry.IsRegistered(const AName: string): Boolean;
begin
  Result := FTable.IndexOf(AName) >= 0;
end;

function TFormatRegistry.Check(const AName, AText: string): Boolean;
var
  Def: TObject;
begin
  Def := FTable.Find(AName);
  Result := (Def = nil) or TFormatDefinition(Def).Check(AText);
end;

function TFormatRegistry.Count: Integer;
begin
  Result := FTable.Count;
end;

{ ---- keywords ---- }

constructor TKeywordDefinition.Create(const AName: string; AFunc: TKeywordValidatorFunc;
  AMethod: TKeywordValidatorMethod; AChecker: TKeywordCheckerProc;
  AConfig: TJSONValue; AUnsupported: Boolean);
begin
  inherited Create;
  FName := AName;
  FFunc := AFunc;
  FMethod := AMethod;
  FChecker := AChecker;
  FConfig := AConfig;
  FUnsupported := AUnsupported;
end;

destructor TKeywordDefinition.Destroy;
begin
  FConfig.Free;
  inherited Destroy;
end;

function TKeywordDefinition.Validate(Ctx: TKeywordContext): Boolean;
begin
  if Assigned(FFunc) then
    Result := FFunc(Ctx)
  else if Assigned(FMethod) then
    Result := FMethod(Ctx)
  else
    Result := True;
end;

constructor TKeywordRegistry.Create;
begin
  inherited Create;
  FTable := TNamedTable.Create;
end;

destructor TKeywordRegistry.Destroy;
begin
  FTable.Free;
  inherited Destroy;
end;

procedure TKeywordRegistry.Put(const AName: string; ADef: TKeywordDefinition;
  AllowOverride: Boolean);
begin
  FTable.Put(AName, ADef, AllowOverride, 'Keyword');
end;

function TKeywordRegistry.ParseConfig(const AName, AConfigJson: string): TJSONValue;
begin
  Result := nil;
  if AConfigJson = '' then
    Exit;
  try
    Result := ParseJSON(AConfigJson);
  except
    on E: EJSONPathJSONError do
      raise ESchemaRegistrationError.CreateFmt(
        'Configuration of keyword "%s" is not valid JSON: %s', [AName, E.Message]);
  end;
end;

procedure TKeywordRegistry.RegisterKeyword(const AName: string;
  AValidator: TKeywordValidatorFunc; const AConfigJson: string;
  AChecker: TKeywordCheckerProc; AllowOverride: Boolean);
begin
  if not Assigned(AValidator) then
    raise ESchemaRegistrationError.Create('A validator is required for keyword "' + AName + '"');
  Put(AName, TKeywordDefinition.Create(AName, AValidator, nil, AChecker,
    ParseConfig(AName, AConfigJson), False), AllowOverride);
end;

procedure TKeywordRegistry.RegisterKeyword(const AName: string;
  AValidator: TKeywordValidatorMethod; const AConfigJson: string;
  AChecker: TKeywordCheckerProc; AllowOverride: Boolean);
begin
  if not Assigned(AValidator) then
    raise ESchemaRegistrationError.Create('A validator is required for keyword "' + AName + '"');
  Put(AName, TKeywordDefinition.Create(AName, nil, AValidator, AChecker,
    ParseConfig(AName, AConfigJson), False), AllowOverride);
end;

procedure TKeywordRegistry.RegisterStructural(const AName: string;
  AChecker: TKeywordCheckerProc; AllowOverride: Boolean);
begin
  Put(AName, TKeywordDefinition.Create(AName, nil, nil, AChecker, nil, False),
    AllowOverride);
end;

procedure TKeywordRegistry.RegisterUnsupported(const AName: string);
begin
  Put(AName, TKeywordDefinition.Create(AName, nil, nil, nil, nil, True), True);
end;

function TKeywordRegistry.Unregister(const AName: string): Boolean;
begin
  Result := FTable.Remove(AName);
end;

function TKeywordRegistry.Find(const AName: string): TKeywordDefinition;
begin
  Result := TKeywordDefinition(FTable.Find(AName));
end;

function TKeywordRegistry.IsRegistered(const AName: string): Boolean;
begin
  Result := FTable.IndexOf(AName) >= 0;
end;

function TKeywordRegistry.Count: Integer;
begin
  Result := FTable.Count;
end;

function TKeywordRegistry.NameAt(AIndex: Integer): string;
begin
  Result := FTable.NameAt(AIndex);
end;

{ ---- drafts ---- }

function NormalizeSchemaUri(const AUri: string): string;
begin
  Result := Trim(AUri);
  if (Result <> '') and (Result[Length(Result)] = '#') then
    Delete(Result, Length(Result), 1);
end;

constructor TJsonSchemaDraft.Create;
begin
  inherited Create;
  FKeywords := TKeywordRegistry.Create;
  RegisterKeywords;
end;

destructor TJsonSchemaDraft.Destroy;
begin
  FKeywords.Free;
  inherited Destroy;
end;

function TJsonSchemaDraft.IdKeyword: string;
begin
  Result := '$id';
end;

function TJsonSchemaDraft.RefOverridesSiblings: Boolean;
begin
  Result := False;
end;

function TJsonSchemaDraft.SupportsBooleanSchemas: Boolean;
begin
  Result := True;
end;

constructor TDraftRegistry.Create;
begin
  inherited Create;
  FDrafts := TOwnedList.Create;
end;

destructor TDraftRegistry.Destroy;
begin
  FDrafts.Free;
  inherited Destroy;
end;

function TDraftRegistry.Count: Integer;
begin
  Result := FDrafts.Count;
end;

function TDraftRegistry.Items(AIndex: Integer): TJsonSchemaDraft;
begin
  Result := TJsonSchemaDraft(FDrafts[AIndex]);
end;

function TDraftRegistry.SupportedNames: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Count - 1 do
  begin
    if I > 0 then
      Result := Result + ', ';
    Result := Result + Items(I).Name;
  end;
end;

procedure TDraftRegistry.RegisterDraft(ADraft: TJsonSchemaDraft);
begin
  if (FindByName(ADraft.Name) <> nil) or (FindByUri(ADraft.MetaSchemaUri) <> nil) then
  begin
    ADraft.Free;
    raise ESchemaRegistrationError.Create(
      'A draft with the same name or meta-schema URI is already registered');
  end;
  FDrafts.Add(ADraft);
  if FDefaultName = '' then
    FDefaultName := ADraft.Name;
end;

function TDraftRegistry.FindByName(const AName: string): TJsonSchemaDraft;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to Count - 1 do
    if Items(I).Name = AName then
    begin
      Result := Items(I);
      Exit;
    end;
end;

function TDraftRegistry.FindByUri(const AUri: string): TJsonSchemaDraft;
var
  I: Integer;
  U: string;
begin
  Result := nil;
  U := NormalizeSchemaUri(AUri);
  for I := 0 to Count - 1 do
    if NormalizeSchemaUri(Items(I).MetaSchemaUri) = U then
    begin
      Result := Items(I);
      Exit;
    end;
end;

procedure TDraftRegistry.SetDefaultName(const AValue: string);
begin
  if FindByName(AValue) = nil then
    RaiseSchemaError('Unsupported JSON Schema draft "' + AValue +
      '"; supported drafts: ' + SupportedNames, '', '');
  FDefaultName := AValue;
end;

function TDraftRegistry.DefaultDraft: TJsonSchemaDraft;
begin
  Result := FindByName(FDefaultName);
  if Result = nil then
    RaiseSchemaError('No default JSON Schema draft is configured', '', '');
end;

function TDraftRegistry.DraftForSchema(ASchema: TJSONValue): TJsonSchemaDraft;
var
  Decl: TJSONValue;
begin
  Result := nil;
  if (ASchema <> nil) and (ASchema.Kind = jkObject) then
  begin
    Decl := ASchema.FindMember('$schema');
    if Decl <> nil then
    begin
      if Decl.Kind <> jkString then
        RaiseSchemaError('"$schema" must be a string', '$schema', '/$schema');
      Result := FindByUri(Decl.StringValue);
      if Result = nil then
        RaiseSchemaError('Unsupported JSON Schema draft "' + Decl.StringValue +
          '"; supported drafts: ' + SupportedNames, '$schema', '/$schema');
      Exit;
    end;
  end;
  Result := DefaultDraft;
end;

end.
