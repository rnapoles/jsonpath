{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit JsonSchemaValidator;

{ Public facade of the JSON Schema framework.

    V := TJsonSchemaValidator.Create;
    try
      V.RegisterSchema('person', PersonSchemaText);      // compiled once
      R := V.ValidateText(InstanceText, 'person');       // return mode
      try
        if not R.IsValid then WriteLn(R.ErrorText);
      finally
        R.Free;
      end;
    finally
      V.Free;
    end;

  LIFECYCLE AND OWNERSHIP
    * The validator owns its registries, the compiled schemas and every
      schema document registered with it. Free the validator last.
    * RegisterSchema(Id, TJSONValue) TRANSFERS ownership of the value to the
      validator, also when compilation fails (the value is freed then).
      The text overload parses for you.
    * Schemas are compiled when they are registered. Invalid schemas raise
      ESchemaError right there and are not registered.
    * Validate* return a TValidationResult that the CALLER frees. In
      emRaise mode an invalid instance raises EValidationError instead
      (valid instances still return a result).
    * The instance is only borrowed during the call.
    * Schemas are immutable after registration; replacing or unregistering one
      keeps the old compiled schema alive until the validator is freed.
    * A validator is not thread-safe; use one per thread.

  ERROR POLICIES
    ErrorMode          emReturn (default): invalid instances are reported in the
                       result. emRaise: they raise EValidationError.
    DuplicatePolicy    dpRaise (default) raises ESchemaRegistrationError for an
                       id that is already registered, dpReplace replaces it,
                       dpSkip keeps the existing schema.
    LoadErrorPolicy    applies to LoadSchemaDirectory only: lpRaise (default)
                       stops at the first bad file (files loaded before stay
                       registered), lpCollect skips bad files and records them
                       in LoadErrors. LoadSchemaFile always raises.
    Always raised      invalid schemas and unsupported drafts (ESchemaError),
                       missing/unreadable/malformed files (ESchemaLoadError),
                       unknown schema ids (ESchemaRegistrationError). }

interface

uses
  SysUtils, Classes, JSONPathJSON, JsonSchemaErrors, JsonSchemaCore, JsonSchemaKeywords,
  JsonSchemaDrafts, JsonSchemaRegex, JsonSchemaStore, JsonSchemaEvaluator,
  JsonSchemaLoader;

type
  TErrorMode = (emReturn, emRaise);
  TLoadErrorPolicy = (lpRaise, lpCollect);

  TJsonSchemaValidator = class
  private
    FDrafts: TDraftRegistry;
    FTypes: TTypeRegistry;
    FFormats: TFormatRegistry;
    FKeywords: TKeywordRegistry;
    FRegex: TSchemaRegexCache;
    FStore: TSchemaStore;
    FCompiler: TSchemaCompiler;
    FLoader: TSchemaFileLoader;
    FLoadErrors: TValidationErrors;
    FErrorMode: TErrorMode;
    FDuplicatePolicy: TDuplicatePolicy;
    FLoadErrorPolicy: TLoadErrorPolicy;
    FStopOnFirstError: Boolean;
    FAssertFormats: Boolean;
    FMaxDepth: Integer;
    function GetDefaultDraftName: string;
    procedure SetDefaultDraftName(const AValue: string);
    function GetIgnoreUnsupported: Boolean;
    procedure SetIgnoreUnsupported(AValue: Boolean);
    function GetExtensions: string;
    procedure SetExtensions(const AValue: string);
    function DetectId(ASchema: TJSONValue): string;
    function DraftDefinesKeyword(const AName: string): Boolean;
    function Execute(ACompiled: TCompiledSchema; AInstance: TJSONValue): TValidationResult;
  public
    constructor Create;
    destructor Destroy; override;

    { ---- drafts ---- }
    { Draft used by schemas that declare no "$schema" (default: '2020-12') }
    procedure UseDraft(const ADraftName: string);
    property DefaultDraftName: string read GetDefaultDraftName write SetDefaultDraftName;

    { ---- extensions (see JsonSchemaCore for the registration policy) ---- }
    procedure RegisterType(const AName: string; AChecker: TTypeCheckerFunc;
      AllowOverride: Boolean = False); overload;
    procedure RegisterType(const AName: string; AChecker: TTypeCheckerMethod;
      AllowOverride: Boolean = False); overload;
    procedure RegisterFormat(const AName: string; AChecker: TFormatCheckerFunc;
      AllowOverride: Boolean = False); overload;
    procedure RegisterFormat(const AName: string; AChecker: TFormatCheckerMethod;
      AllowOverride: Boolean = False); overload;
    { A custom keyword usable by every draft. AConfigJson is optional JSON
      handed to the validator as Ctx.Config; AChecker optionally validates the
      keyword's value when schemas are compiled. }
    procedure RegisterKeyword(const AName: string; AValidator: TKeywordValidatorFunc;
      const AConfigJson: string = ''; AChecker: TKeywordCheckerProc = nil;
      AllowOverride: Boolean = False); overload;
    procedure RegisterKeyword(const AName: string; AValidator: TKeywordValidatorMethod;
      const AConfigJson: string = ''; AChecker: TKeywordCheckerProc = nil;
      AllowOverride: Boolean = False); overload;

    { ---- schemas ---- }
    { Registers a schema under AId (empty: use its "$id"/"id"). Returns the id. }
    function RegisterSchema(const AId, AJsonText: string): string; overload;
    function RegisterSchema(const AId: string; ASchema: TJSONValue): string; overload;
    function HasSchema(const AId: string): Boolean;
    { The registered schema document (owned by the validator) }
    function GetSchema(const AId: string): TJSONValue;
    function UnregisterSchema(const AId: string): Boolean;
    function SchemaCount: Integer;
    function SchemaIdAt(AIndex: Integer): string;
    { Loads one file. AId empty: the schema's own id, else the file name without
      extension. Returns the id used. }
    function LoadSchemaFile(const AFileName: string; const AId: string = ''): string;
    { Loads every file with a configured extension; returns the number loaded }
    function LoadSchemaDirectory(const ADirectory: string;
      ARecursive: Boolean = True): Integer;

    { ---- validation ---- }
    function Validate(AInstance: TJSONValue; const ASchemaId: string): TValidationResult;
    function ValidateText(const AInstanceJson, ASchemaId: string): TValidationResult;
    { Validates against a schema that is not registered (compiled for this
      call only). The caller keeps ownership of ASchema. }
    function ValidateWithSchema(AInstance, ASchema: TJSONValue): TValidationResult;
    function IsValid(AInstance: TJSONValue; const ASchemaId: string): Boolean;

    { ---- configuration ---- }
    property ErrorMode: TErrorMode read FErrorMode write FErrorMode;
    property StopOnFirstError: Boolean read FStopOnFirstError write FStopOnFirstError;
    { "format" is asserted when True (default); unknown formats always pass }
    property AssertFormats: Boolean read FAssertFormats write FAssertFormats;
    { When True, keywords the implementation cannot evaluate are ignored
      instead of rejecting the schema }
    property IgnoreUnsupportedKeywords: Boolean read GetIgnoreUnsupported
      write SetIgnoreUnsupported;
    property DuplicatePolicy: TDuplicatePolicy read FDuplicatePolicy write FDuplicatePolicy;
    property LoadErrorPolicy: TLoadErrorPolicy read FLoadErrorPolicy write FLoadErrorPolicy;
    property SchemaFileExtensions: string read GetExtensions write SetExtensions;
    property MaxDepth: Integer read FMaxDepth write FMaxDepth;
    { Problems recorded by the last LoadSchemaDirectory (lpCollect) }
    property LoadErrors: TValidationErrors read FLoadErrors;

    { ---- advanced access ---- }
    property Drafts: TDraftRegistry read FDrafts;
    property Types: TTypeRegistry read FTypes;
    property Formats: TFormatRegistry read FFormats;
    property Keywords: TKeywordRegistry read FKeywords;
  end;

implementation

constructor TJsonSchemaValidator.Create;
begin
  inherited Create;
  FDrafts := TDraftRegistry.Create;
  RegisterBuiltinDrafts(FDrafts);
  FTypes := TTypeRegistry.Create;
  RegisterBuiltinTypes(FTypes);
  FFormats := TFormatRegistry.Create;
  RegisterBuiltinFormats(FFormats);
  FKeywords := TKeywordRegistry.Create;
  FRegex := TSchemaRegexCache.Create;
  FStore := TSchemaStore.Create;
  FCompiler := TSchemaCompiler.Create(FDrafts, FTypes, FKeywords, FRegex, FStore);
  FLoader := TSchemaFileLoader.Create;
  FLoadErrors := TValidationErrors.Create;
  FErrorMode := emReturn;
  FDuplicatePolicy := dpRaise;
  FLoadErrorPolicy := lpRaise;
  FAssertFormats := True;
  FMaxDepth := 200;
end;

destructor TJsonSchemaValidator.Destroy;
begin
  FLoadErrors.Free;
  FLoader.Free;
  FCompiler.Free;
  FStore.Free;
  FRegex.Free;
  FKeywords.Free;
  FFormats.Free;
  FTypes.Free;
  FDrafts.Free;
  inherited Destroy;
end;

function TJsonSchemaValidator.GetDefaultDraftName: string;
begin
  Result := FDrafts.DefaultDraftName;
end;

procedure TJsonSchemaValidator.SetDefaultDraftName(const AValue: string);
begin
  FDrafts.DefaultDraftName := AValue;
end;

procedure TJsonSchemaValidator.UseDraft(const ADraftName: string);
begin
  FDrafts.DefaultDraftName := ADraftName;
end;

function TJsonSchemaValidator.GetIgnoreUnsupported: Boolean;
begin
  Result := FCompiler.IgnoreUnsupportedKeywords;
end;

procedure TJsonSchemaValidator.SetIgnoreUnsupported(AValue: Boolean);
begin
  FCompiler.IgnoreUnsupportedKeywords := AValue;
end;

function TJsonSchemaValidator.GetExtensions: string;
begin
  Result := FLoader.Extensions;
end;

procedure TJsonSchemaValidator.SetExtensions(const AValue: string);
begin
  FLoader.Extensions := AValue;
end;

{ ---- extensions ---- }

procedure TJsonSchemaValidator.RegisterType(const AName: string;
  AChecker: TTypeCheckerFunc; AllowOverride: Boolean);
begin
  FTypes.RegisterType(AName, AChecker, AllowOverride);
end;

procedure TJsonSchemaValidator.RegisterType(const AName: string;
  AChecker: TTypeCheckerMethod; AllowOverride: Boolean);
begin
  FTypes.RegisterType(AName, AChecker, AllowOverride);
end;

procedure TJsonSchemaValidator.RegisterFormat(const AName: string;
  AChecker: TFormatCheckerFunc; AllowOverride: Boolean);
begin
  FFormats.RegisterFormat(AName, AChecker, AllowOverride);
end;

procedure TJsonSchemaValidator.RegisterFormat(const AName: string;
  AChecker: TFormatCheckerMethod; AllowOverride: Boolean);
begin
  FFormats.RegisterFormat(AName, AChecker, AllowOverride);
end;

function TJsonSchemaValidator.DraftDefinesKeyword(const AName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to FDrafts.Count - 1 do
    if FDrafts.Items(I).Keywords.IsRegistered(AName) then
    begin
      Result := True;
      Exit;
    end;
end;

procedure TJsonSchemaValidator.RegisterKeyword(const AName: string;
  AValidator: TKeywordValidatorFunc; const AConfigJson: string;
  AChecker: TKeywordCheckerProc; AllowOverride: Boolean);
begin
  if (not AllowOverride) and DraftDefinesKeyword(AName) then
    raise ESchemaRegistrationError.CreateFmt(
      'Keyword "%s" is defined by a JSON Schema draft; pass AllowOverride=True to replace it',
      [AName]);
  FKeywords.RegisterKeyword(AName, AValidator, AConfigJson, AChecker, AllowOverride);
end;

procedure TJsonSchemaValidator.RegisterKeyword(const AName: string;
  AValidator: TKeywordValidatorMethod; const AConfigJson: string;
  AChecker: TKeywordCheckerProc; AllowOverride: Boolean);
begin
  if (not AllowOverride) and DraftDefinesKeyword(AName) then
    raise ESchemaRegistrationError.CreateFmt(
      'Keyword "%s" is defined by a JSON Schema draft; pass AllowOverride=True to replace it',
      [AName]);
  FKeywords.RegisterKeyword(AName, AValidator, AConfigJson, AChecker, AllowOverride);
end;

{ ---- schemas ---- }

function TJsonSchemaValidator.DetectId(ASchema: TJSONValue): string;
var
  V: TJSONValue;
begin
  Result := '';
  if (ASchema = nil) or (ASchema.Kind <> jkObject) then
    Exit;
  V := ASchema.FindMember('$id');
  if V = nil then
    V := ASchema.FindMember('id');
  if (V <> nil) and (V.Kind = jkString) then
    Result := V.StringValue;
end;

function TJsonSchemaValidator.RegisterSchema(const AId: string;
  ASchema: TJSONValue): string;
var
  Name: string;
  Compiled: TCompiledSchema;
begin
  if ASchema = nil then
    raise ESchemaRegistrationError.Create('A schema document is required');
  Name := AId;
  if Name = '' then
    Name := DetectId(ASchema);
  if Name = '' then
  begin
    ASchema.Free;
    raise ESchemaRegistrationError.Create(
      'A schema id is required: pass one or give the schema an "$id"');
  end;
  if FStore.Find(Name) <> nil then
    case FDuplicatePolicy of
      dpRaise:
        begin
          ASchema.Free;
          raise ESchemaRegistrationError.CreateFmt(
            'A schema with id "%s" is already registered', [Name]);
        end;
      dpSkip:
        begin
          ASchema.Free;
          Result := Name;
          Exit;
        end;
    end;
  Compiled := FCompiler.Compile(Name, ASchema, True);
  FStore.Add(Compiled);
  Result := Name;
end;

function TJsonSchemaValidator.RegisterSchema(const AId, AJsonText: string): string;
var
  Doc: TJSONValue;
begin
  try
    Doc := ParseJSON(AJsonText);
  except
    on E: EJSONPathJSONError do
      RaiseSchemaError('The schema is not valid JSON: ' + E.Message, '', '');
  end;
  Result := RegisterSchema(AId, Doc);
end;

function TJsonSchemaValidator.HasSchema(const AId: string): Boolean;
begin
  Result := FStore.Find(AId) <> nil;
end;

function TJsonSchemaValidator.GetSchema(const AId: string): TJSONValue;
var
  C: TCompiledSchema;
begin
  C := FStore.Find(AId);
  if C = nil then
    raise ESchemaRegistrationError.CreateFmt('Schema "%s" is not registered', [AId]);
  Result := C.Root;
end;

function TJsonSchemaValidator.UnregisterSchema(const AId: string): Boolean;
begin
  Result := FStore.Remove(AId);
end;

function TJsonSchemaValidator.SchemaCount: Integer;
begin
  Result := FStore.Count;
end;

function TJsonSchemaValidator.SchemaIdAt(AIndex: Integer): string;
begin
  Result := FStore.IdAt(AIndex);
end;

function TJsonSchemaValidator.LoadSchemaFile(const AFileName, AId: string): string;
var
  Doc: TJSONValue;
  Name: string;
begin
  Doc := FLoader.ReadJson(AFileName);
  Name := AId;
  if Name = '' then
    Name := DetectId(Doc);
  if Name = '' then
    Name := ChangeFileExt(ExtractFileName(AFileName), '');
  Result := RegisterSchema(Name, Doc);
end;

function TJsonSchemaValidator.LoadSchemaDirectory(const ADirectory: string;
  ARecursive: Boolean): Integer;
var
  Files: TStringList;
  I: Integer;
begin
  Result := 0;
  FLoadErrors.Clear;
  Files := FLoader.ListFiles(ADirectory, ARecursive);
  try
    for I := 0 to Files.Count - 1 do
      try
        LoadSchemaFile(Files[I]);
        Inc(Result);
      except
        on E: EJsonSchemaError do
        begin
          if FLoadErrorPolicy = lpRaise then
            raise;
          FLoadErrors.AddNew(E.Message, '', Files[I], '');
        end;
      end;
  finally
    Files.Free;
  end;
end;

{ ---- validation ---- }

function TJsonSchemaValidator.Execute(ACompiled: TCompiledSchema;
  AInstance: TJSONValue): TValidationResult;
var
  Eval: TSchemaEvaluator;
  Options: TEvalOptions;
  Errs: TValidationErrors;
  Msg: string;
begin
  if AInstance = nil then
    raise EJsonSchemaError.Create('The instance to validate must not be nil');
  Options.AssertFormats := FAssertFormats;
  Options.StopOnFirstError := FStopOnFirstError;
  Options.MaxDepth := FMaxDepth;
  Eval := TSchemaEvaluator.Create(FStore, FTypes, FFormats, FKeywords, FRegex, Options);
  try
    Errs := Eval.Run(ACompiled, AInstance);
  finally
    Eval.Free;
  end;
  if (FErrorMode = emRaise) and (Errs.Count > 0) then
  begin
    Msg := Format('Validation against "%s" failed: %s (%d error(s))',
      [ACompiled.Id, Errs[0].Message, Errs.Count]);
    raise EValidationError.CreateWithErrors(Msg, Errs);
  end;
  Result := TValidationResult.Create(Errs);
end;

function TJsonSchemaValidator.Validate(AInstance: TJSONValue;
  const ASchemaId: string): TValidationResult;
var
  C: TCompiledSchema;
begin
  C := FStore.Find(ASchemaId);
  if C = nil then
    raise ESchemaRegistrationError.CreateFmt('Schema "%s" is not registered', [ASchemaId]);
  Result := Execute(C, AInstance);
end;

function TJsonSchemaValidator.ValidateText(const AInstanceJson,
  ASchemaId: string): TValidationResult;
var
  Doc: TJSONValue;
begin
  try
    Doc := ParseJSON(AInstanceJson);
  except
    on E: EJSONPathJSONError do
      raise EJsonSchemaError.Create('The instance is not valid JSON: ' + E.Message);
  end;
  try
    Result := Validate(Doc, ASchemaId);
  finally
    Doc.Free;
  end;
end;

function TJsonSchemaValidator.ValidateWithSchema(AInstance,
  ASchema: TJSONValue): TValidationResult;
var
  C: TCompiledSchema;
begin
  C := FCompiler.Compile('(inline schema)', ASchema, False);
  try
    Result := Execute(C, AInstance);
  finally
    C.Free;
  end;
end;

function TJsonSchemaValidator.IsValid(AInstance: TJSONValue; const ASchemaId: string): Boolean;
var
  R: TValidationResult;
begin
  R := Validate(AInstance, ASchemaId);
  try
    Result := R.IsValid;
  finally
    R.Free;
  end;
end;

end.
