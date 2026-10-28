{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit JsonSchemaStore;

{ Schema compilation and storage.

    TSchemaCompiler   walks a schema ONCE, applies the keyword checkers of its
                      draft (shape of every keyword value), indexes embedded
                      resources / anchors and records every $ref. Invalid
                      schemas raise ESchemaError.
    TCompiledSchema   the result: the schema document plus its draft and the
                      indexes needed at validation time.
    TSchemaStore      the registry of compiled schemas (by id) and the $ref
                      resolver.

  $REF RESOLUTION
    A reference is resolved against the base URI in effect where it appears
    (the nearest enclosing "$id"/"id", otherwise ""). The target is looked up
      1. among the resources (root and embedded $id) of the same schema,
      2. among the resources of all registered schemas,
      3. as a registered schema id,
    followed by the fragment: empty (the resource), a JSON Pointer ("/a/b")
    or a plain-name anchor ("$anchor" / "#name" ids).
    References to schemas that are registered later are resolved lazily on
    first use, so schemas may be registered in any order. Remote (http) schemas
    are never fetched; register them under their URI instead.

  LIFETIME
    Replacing or removing a schema keeps the old compiled schema alive until
    the store is destroyed, because other schemas may already point into it. }

interface

uses
  SysUtils, Classes, JSONPathCommon, JSONPathJSON, JsonSchemaErrors, JsonSchemaCore,
  JsonSchemaRegex;

type
  TUriParts = record
    Scheme: string;
    Authority: string;
    HasAuthority: Boolean;
    Path: string;
    Query: string;
    HasQuery: Boolean;
    Fragment: string;
    HasFragment: Boolean;
  end;

  TSchemaResource = class
  public
    Uri: string;
    Node: TJSONValue;
  end;

  TSchemaAnchor = class
  public
    Uri: string;
    Name: string;
    Node: TJSONValue;
  end;

  TCompiledSchema = class;

  { One $ref occurrence }
  TRefEntry = class
  public
    Node: TJSONValue;
    Base: string;
    Location: string;
    Resolved: Boolean;
    TargetNode: TJSONValue;
    TargetOwner: TCompiledSchema;
  end;

  TCompiledSchema = class
  private
    FId: string;
    FRoot: TJSONValue;
    FOwnsRoot: Boolean;
    FDraft: TJsonSchemaDraft;
    FResources: TOwnedList;
    FAnchors: TOwnedList;
    FRefs: TOwnedList;
    function GetRefCount: Integer;
    function GetRef(Index: Integer): TRefEntry;
  public
    constructor Create(const AId: string; ARoot: TJSONValue; AOwnsRoot: Boolean;
      ADraft: TJsonSchemaDraft);
    destructor Destroy; override;
    procedure AddResource(const AUri: string; ANode: TJSONValue);
    procedure AddAnchor(const AUri, AName: string; ANode: TJSONValue);
    function AddRef(ANode: TJSONValue; const ABase, ALocation: string): TRefEntry;
    function FindResource(const AUri: string): TJSONValue;
    function FindAnchor(const AUri, AName: string): TJSONValue;
    function FindRef(ANode: TJSONValue): TRefEntry;
    property Id: string read FId;
    property Root: TJSONValue read FRoot;
    property Draft: TJsonSchemaDraft read FDraft;
    property RefCount: Integer read GetRefCount;
    property Refs[Index: Integer]: TRefEntry read GetRef;
  end;

  TResolveOutcome = (roOk, roNoResource, roBadFragment);

  TSchemaStore = class
  private
    FIds: TStringArray;
    FIndexed: TList;
    FCount: Integer;
    FAll: TOwnedList;
    function IndexOf(const AId: string): Integer;
    function GetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    { Takes ownership; replaces (and retires) a schema with the same id }
    procedure Add(ACompiled: TCompiledSchema);
    function Find(const AId: string): TCompiledSchema;
    function Remove(const AId: string): Boolean;
    function IdAt(AIndex: Integer): string;
    function SchemaAt(AIndex: Integer): TCompiledSchema;
    { See "$REF RESOLUTION" above }
    function TryResolve(AOwner: TCompiledSchema; AEntry: TRefEntry;
      out AMessage: string): TResolveOutcome;
    property Count: Integer read GetCount;
  end;

  TSchemaCompiler = class
  private
    FDrafts: TDraftRegistry;
    FTypes: TTypeRegistry;
    FKeywords: TKeywordRegistry;
    FRegex: TSchemaRegexCache;
    FStore: TSchemaStore;
    FIgnoreUnsupported: Boolean;
  public
    constructor Create(ADrafts: TDraftRegistry; ATypes: TTypeRegistry;
      AKeywords: TKeywordRegistry; ARegex: TSchemaRegexCache; AStore: TSchemaStore);
    { Compiles ARoot. The draft comes from "$schema" or the registry default.
      Raises ESchemaError when the schema is invalid or uses an unsupported
      draft/keyword. AOwnsRoot = True transfers ownership of ARoot to the
      result; on failure ARoot is freed in that case. }
    function Compile(const AId: string; ARoot: TJSONValue;
      AOwnsRoot: Boolean): TCompiledSchema;
    property IgnoreUnsupportedKeywords: Boolean read FIgnoreUnsupported
      write FIgnoreUnsupported;
    property Drafts: TDraftRegistry read FDrafts;
    property Types: TTypeRegistry read FTypes;
    property CustomKeywords: TKeywordRegistry read FKeywords;
    property Regex: TSchemaRegexCache read FRegex;
  end;

{ RFC 3986 helpers (reference resolution for $ref / $id) }
function UriParse(const AUri: string): TUriParts;
function UriToString(const AParts: TUriParts): string;
function UriResolve(const ABase, ARef: string): string;
function UriWithoutFragment(const AUri: string): string;
function UriFragment(const AUri: string): string;
function PercentDecode(const AText: string): string;

implementation

{ ================= URI helpers ================= }

function IsSchemeChar(C: Char): Boolean;
begin
  Result := ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z'))
    or ((C >= '0') and (C <= '9')) or (C = '+') or (C = '-') or (C = '.');
end;

function UriParse(const AUri: string): TUriParts;
var
  S: string;
  P, I: Integer;
  SchemeOk: Boolean;
begin
  Result.Scheme := '';
  Result.Authority := '';
  Result.HasAuthority := False;
  Result.Path := '';
  Result.Query := '';
  Result.HasQuery := False;
  Result.Fragment := '';
  Result.HasFragment := False;
  S := AUri;
  P := Pos('#', S);
  if P > 0 then
  begin
    Result.HasFragment := True;
    Result.Fragment := Copy(S, P + 1, Length(S));
    S := Copy(S, 1, P - 1);
  end;
  P := Pos('?', S);
  if P > 0 then
  begin
    Result.HasQuery := True;
    Result.Query := Copy(S, P + 1, Length(S));
    S := Copy(S, 1, P - 1);
  end;
  P := Pos(':', S);
  if P > 1 then
  begin
    SchemeOk := ((S[1] >= 'a') and (S[1] <= 'z')) or ((S[1] >= 'A') and (S[1] <= 'Z'));
    for I := 2 to P - 1 do
      if not IsSchemeChar(S[I]) then
        SchemeOk := False;
    if SchemeOk then
    begin
      Result.Scheme := Copy(S, 1, P - 1);
      S := Copy(S, P + 1, Length(S));
    end;
  end;
  if Copy(S, 1, 2) = '//' then
  begin
    Result.HasAuthority := True;
    S := Copy(S, 3, Length(S));
    P := Pos('/', S);
    if P = 0 then
    begin
      Result.Authority := S;
      S := '';
    end
    else
    begin
      Result.Authority := Copy(S, 1, P - 1);
      S := Copy(S, P, Length(S));
    end;
  end;
  Result.Path := S;
end;

function UriToString(const AParts: TUriParts): string;
begin
  Result := '';
  if AParts.Scheme <> '' then
    Result := AParts.Scheme + ':';
  if AParts.HasAuthority then
    Result := Result + '//' + AParts.Authority;
  Result := Result + AParts.Path;
  if AParts.HasQuery then
    Result := Result + '?' + AParts.Query;
  if AParts.HasFragment then
    Result := Result + '#' + AParts.Fragment;
end;

function RemoveDotSegments(const APath: string): string;
var
  Tokens: TStringArray;
  Count, I, J, StartAt: Integer;
  Token: string;
  Absolute, Trailing: Boolean;
begin
  Absolute := (APath <> '') and (APath[1] = '/');
  Trailing := False;
  Count := 0;
  SetLength(Tokens, Length(APath) + 1);
  if Absolute then
    StartAt := 2
  else
    StartAt := 1;
  I := StartAt;
  while I <= Length(APath) + 1 do
  begin
    J := I;
    while (J <= Length(APath)) and (APath[J] <> '/') do
      Inc(J);
    Token := Copy(APath, I, J - I);
    if Token = '.' then
      Trailing := J > Length(APath)
    else if Token = '..' then
    begin
      if Count > 0 then
        Dec(Count);
      Trailing := J > Length(APath);
    end
    else
    begin
      Tokens[Count] := Token;
      Inc(Count);
      Trailing := False;
    end;
    I := J + 1;
  end;
  Result := '';
  for I := 0 to Count - 1 do
  begin
    if I > 0 then
      Result := Result + '/';
    Result := Result + Tokens[I];
  end;
  if Absolute then
    Result := '/' + Result;
  if Trailing and (Count > 0) then
    Result := Result + '/';
end;

function UriResolve(const ABase, ARef: string): string;
var
  B, R, T: TUriParts;
  Merged: string;
  P: Integer;
begin
  B := UriParse(ABase);
  R := UriParse(ARef);
  T := R;
  T.Fragment := R.Fragment;
  T.HasFragment := R.HasFragment;
  if R.Scheme <> '' then
    T.Path := RemoveDotSegments(R.Path)
  else
  begin
    T.Scheme := B.Scheme;
    if R.HasAuthority then
      T.Path := RemoveDotSegments(R.Path)
    else
    begin
      T.Authority := B.Authority;
      T.HasAuthority := B.HasAuthority;
      if R.Path = '' then
      begin
        T.Path := B.Path;
        if not R.HasQuery then
        begin
          T.Query := B.Query;
          T.HasQuery := B.HasQuery;
        end;
      end
      else if R.Path[1] = '/' then
        T.Path := RemoveDotSegments(R.Path)
      else
      begin
        if B.HasAuthority and (B.Path = '') then
          Merged := '/' + R.Path
        else
        begin
          P := Length(B.Path);
          while (P > 0) and (B.Path[P] <> '/') do
            Dec(P);
          Merged := Copy(B.Path, 1, P) + R.Path;
        end;
        T.Path := RemoveDotSegments(Merged);
      end;
    end;
  end;
  Result := UriToString(T);
end;

function UriWithoutFragment(const AUri: string): string;
var
  P: Integer;
begin
  P := Pos('#', AUri);
  if P > 0 then
    Result := Copy(AUri, 1, P - 1)
  else
    Result := AUri;
end;

function UriFragment(const AUri: string): string;
var
  P: Integer;
begin
  P := Pos('#', AUri);
  if P > 0 then
    Result := Copy(AUri, P + 1, Length(AUri))
  else
    Result := '';
end;

function PercentDecode(const AText: string): string;
var
  I: Integer;
  H1, H2: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(AText) do
  begin
    if (AText[I] = '%') and (I + 2 <= Length(AText)) then
    begin
      H1 := HexDigitValue(AText[I + 1]);
      H2 := HexDigitValue(AText[I + 2]);
      if (H1 >= 0) and (H2 >= 0) then
      begin
        Result := Result + Char(H1 * 16 + H2);
        Inc(I, 3);
        Continue;
      end;
    end;
    Result := Result + AText[I];
    Inc(I);
  end;
end;

{ ================= JSON Pointer lookup ================= }

function WalkPointer(ANode: TJSONValue; const APointer: string): TJSONValue;
var
  I, J, Idx, K: Integer;
  Token: string;
  Cur: TJSONValue;
  Digits: Boolean;
begin
  Result := nil;
  Cur := ANode;
  I := 2; { after the leading '/' }
  while True do
  begin
    J := I;
    while (J <= Length(APointer)) and (APointer[J] <> '/') do
      Inc(J);
    Token := JsonPointerUnescape(Copy(APointer, I, J - I));
    if Cur.Kind = jkObject then
      Cur := Cur.FindMember(Token)
    else if Cur.Kind = jkArray then
    begin
      Digits := (Token <> '') and (Length(Token) <= 9);
      for K := 1 to Length(Token) do
        if (Token[K] < '0') or (Token[K] > '9') then
          Digits := False;
      if not Digits then
        Exit;
      Idx := StrToInt(Token);
      if Idx >= Cur.Count then
        Exit;
      Cur := Cur[Idx];
    end
    else
      Exit;
    if Cur = nil then
      Exit;
    if J > Length(APointer) then
      Break;
    I := J + 1;
  end;
  Result := Cur;
end;

{ ================= TCompiledSchema ================= }

constructor TCompiledSchema.Create(const AId: string; ARoot: TJSONValue;
  AOwnsRoot: Boolean; ADraft: TJsonSchemaDraft);
begin
  inherited Create;
  FId := AId;
  FRoot := ARoot;
  FOwnsRoot := AOwnsRoot;
  FDraft := ADraft;
  FResources := TOwnedList.Create;
  FAnchors := TOwnedList.Create;
  FRefs := TOwnedList.Create;
end;

destructor TCompiledSchema.Destroy;
begin
  FRefs.Free;
  FAnchors.Free;
  FResources.Free;
  if FOwnsRoot then
    FRoot.Free;
  inherited Destroy;
end;

function TCompiledSchema.GetRefCount: Integer;
begin
  Result := FRefs.Count;
end;

function TCompiledSchema.GetRef(Index: Integer): TRefEntry;
begin
  Result := TRefEntry(FRefs[Index]);
end;

procedure TCompiledSchema.AddResource(const AUri: string; ANode: TJSONValue);
var
  R: TSchemaResource;
begin
  R := TSchemaResource.Create;
  R.Uri := AUri;
  R.Node := ANode;
  FResources.Add(R);
end;

procedure TCompiledSchema.AddAnchor(const AUri, AName: string; ANode: TJSONValue);
var
  A: TSchemaAnchor;
begin
  A := TSchemaAnchor.Create;
  A.Uri := AUri;
  A.Name := AName;
  A.Node := ANode;
  FAnchors.Add(A);
end;

function TCompiledSchema.AddRef(ANode: TJSONValue; const ABase,
  ALocation: string): TRefEntry;
begin
  Result := TRefEntry.Create;
  Result.Node := ANode;
  Result.Base := ABase;
  Result.Location := ALocation;
  FRefs.Add(Result);
end;

function TCompiledSchema.FindResource(const AUri: string): TJSONValue;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to FResources.Count - 1 do
    if TSchemaResource(FResources[I]).Uri = AUri then
    begin
      Result := TSchemaResource(FResources[I]).Node;
      Exit;
    end;
end;

function TCompiledSchema.FindAnchor(const AUri, AName: string): TJSONValue;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to FAnchors.Count - 1 do
    if (TSchemaAnchor(FAnchors[I]).Uri = AUri) and (TSchemaAnchor(FAnchors[I]).Name = AName) then
    begin
      Result := TSchemaAnchor(FAnchors[I]).Node;
      Exit;
    end;
end;

function TCompiledSchema.FindRef(ANode: TJSONValue): TRefEntry;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to FRefs.Count - 1 do
    if TRefEntry(FRefs[I]).Node = ANode then
    begin
      Result := TRefEntry(FRefs[I]);
      Exit;
    end;
end;

{ ================= TSchemaStore ================= }

constructor TSchemaStore.Create;
begin
  inherited Create;
  FIndexed := TList.Create;
  FAll := TOwnedList.Create;
end;

destructor TSchemaStore.Destroy;
begin
  FIndexed.Free;
  FAll.Free;
  inherited Destroy;
end;

function TSchemaStore.GetCount: Integer;
begin
  Result := FCount;
end;

function TSchemaStore.IndexOf(const AId: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to FCount - 1 do
    if FIds[I] = AId then
    begin
      Result := I;
      Exit;
    end;
end;

procedure TSchemaStore.Add(ACompiled: TCompiledSchema);
var
  Idx: Integer;
begin
  FAll.Add(ACompiled);
  Idx := IndexOf(ACompiled.Id);
  if Idx >= 0 then
    FIndexed[Idx] := Pointer(ACompiled)
  else
  begin
    if FCount >= Length(FIds) then
      SetLength(FIds, FCount * 2 + 8);
    FIds[FCount] := ACompiled.Id;
    Inc(FCount);
    FIndexed.Add(Pointer(ACompiled));
  end;
end;

function TSchemaStore.Find(const AId: string): TCompiledSchema;
var
  Idx: Integer;
begin
  Idx := IndexOf(AId);
  if Idx >= 0 then
    Result := TCompiledSchema(FIndexed[Idx])
  else
    Result := nil;
end;

function TSchemaStore.Remove(const AId: string): Boolean;
var
  Idx, I: Integer;
begin
  Idx := IndexOf(AId);
  Result := Idx >= 0;
  if not Result then
    Exit;
  FIndexed.Delete(Idx); { the object stays alive in FAll }
  for I := Idx to FCount - 2 do
    FIds[I] := FIds[I + 1];
  Dec(FCount);
end;

function TSchemaStore.IdAt(AIndex: Integer): string;
begin
  Result := FIds[AIndex];
end;

function TSchemaStore.SchemaAt(AIndex: Integer): TCompiledSchema;
begin
  Result := TCompiledSchema(FIndexed[AIndex]);
end;

function TSchemaStore.TryResolve(AOwner: TCompiledSchema; AEntry: TRefEntry;
  out AMessage: string): TResolveOutcome;
var
  Abs, Doc, Frag: string;
  Node, Target: TJSONValue;
  Holder, Other: TCompiledSchema;
  I: Integer;
begin
  AMessage := '';
  Abs := UriResolve(AEntry.Base, AEntry.Node.StringValue);
  Doc := UriWithoutFragment(Abs);
  Frag := PercentDecode(UriFragment(Abs));
  Holder := nil;
  Node := AOwner.FindResource(Doc);
  if Node <> nil then
    Holder := AOwner
  else if Doc <> '' then
  begin
    for I := 0 to FCount - 1 do
    begin
      Other := SchemaAt(I);
      Node := Other.FindResource(Doc);
      if Node <> nil then
      begin
        Holder := Other;
        Break;
      end;
    end;
    if Holder = nil then
    begin
      Other := Find(Doc);
      if Other <> nil then
      begin
        Holder := Other;
        Node := Other.Root;
      end;
    end;
  end;
  if Holder = nil then
  begin
    AMessage := 'cannot resolve reference "' + AEntry.Node.StringValue +
      '": no schema is registered for "' + Doc + '"';
    Result := roNoResource;
    Exit;
  end;
  if Frag = '' then
    Target := Node
  else if Frag[1] = '/' then
    Target := WalkPointer(Node, Frag)
  else
    Target := Holder.FindAnchor(Doc, Frag);
  if Target = nil then
  begin
    AMessage := 'cannot resolve reference "' + AEntry.Node.StringValue +
      '": the fragment "#' + Frag + '" does not exist in "' + Doc + '"';
    Result := roBadFragment;
    Exit;
  end;
  AEntry.TargetNode := Target;
  AEntry.TargetOwner := Holder;
  AEntry.Resolved := True;
  Result := roOk;
end;

{ ================= compilation ================= }

type
  TCompileSession = class(TCompileContext)
  private
    FCompiler: TSchemaCompiler;
    FCompiled: TCompiledSchema;
    FDraft: TJsonSchemaDraft;
    FErrors: TValidationErrors;
    FSchema: TJSONValue;
    FValue: TJSONValue;
    FConfig: TJSONValue;
    FKeyword: string;
    FLocation: string;
    FBase: string;
    FDepth: Integer;
    function KeywordLocation: string;
    function FindDefinition(const AName: string): TKeywordDefinition;
    procedure ErrorAt(const ALocation, AKeyword, AMessage: string);
    procedure HandleId(const AId: string; ANode: TJSONValue);
    procedure CompileNode(ANode: TJSONValue; const ALocation: string);
    procedure CompileObject(ANode: TJSONValue; const ALocation: string);
    procedure ResolveRefs;
  public
    constructor Create(ACompiler: TSchemaCompiler; ACompiled: TCompiledSchema;
      ADraft: TJsonSchemaDraft);
    destructor Destroy; override;
    procedure Run;
    { TCompileContext }
    function Schema: TJSONValue; override;
    function KeywordValue: TJSONValue; override;
    function Keyword: string; override;
    function Config: TJSONValue; override;
    function SchemaLocation: string; override;
    function DraftName: string; override;
    function Sibling(const AName: string): TJSONValue; override;
    procedure Error(const AMessage: string); override;
    procedure CompileSubschema(ASubSchema: TJSONValue); override;
    procedure CompileChild(ASubSchema: TJSONValue; const AToken: string); override;
    function IsKnownType(const ATypeName: string): Boolean; override;
    procedure CheckPattern(const APattern: string); override;
    procedure RegisterRef(ARefNode: TJSONValue); override;
    procedure DeclareAnchor(const AName: string); override;
  end;

const
  MAX_COMPILE_DEPTH = 200;

constructor TCompileSession.Create(ACompiler: TSchemaCompiler; ACompiled: TCompiledSchema;
  ADraft: TJsonSchemaDraft);
begin
  inherited Create;
  FCompiler := ACompiler;
  FCompiled := ACompiled;
  FDraft := ADraft;
  FErrors := TValidationErrors.Create;
end;

destructor TCompileSession.Destroy;
begin
  FErrors.Free;
  inherited Destroy;
end;

function TCompileSession.KeywordLocation: string;
begin
  Result := FLocation + JsonPointerStep(FKeyword);
end;

function TCompileSession.FindDefinition(const AName: string): TKeywordDefinition;
begin
  Result := FCompiler.CustomKeywords.Find(AName);
  if Result = nil then
    Result := FDraft.Keywords.Find(AName);
end;

procedure TCompileSession.ErrorAt(const ALocation, AKeyword, AMessage: string);
begin
  FErrors.AddNew(AMessage, AKeyword, ALocation, '');
end;

procedure TCompileSession.HandleId(const AId: string; ANode: TJSONValue);
var
  Abs: string;
begin
  if (AId <> '') and (AId[1] = '#') then
  begin
    if Length(AId) > 1 then
      FCompiled.AddAnchor(FBase, Copy(AId, 2, Length(AId)), ANode);
  end
  else
  begin
    Abs := UriResolve(FBase, AId);
    FBase := UriWithoutFragment(Abs);
    FCompiled.AddResource(FBase, ANode);
  end;
end;

procedure TCompileSession.CompileNode(ANode: TJSONValue; const ALocation: string);
begin
  Inc(FDepth);
  try
    if FDepth > MAX_COMPILE_DEPTH then
    begin
      ErrorAt(ALocation, FKeyword, 'schema is nested too deeply');
      Exit;
    end;
    case ANode.Kind of
      jkObject:
        CompileObject(ANode, ALocation);
      jkBoolean:
        if not FDraft.SupportsBooleanSchemas then
          ErrorAt(ALocation, FKeyword, 'boolean schemas are not allowed in ' + FDraft.Name);
    else
      if FDraft.SupportsBooleanSchemas then
        ErrorAt(ALocation, FKeyword, 'a schema must be an object or a boolean')
      else
        ErrorAt(ALocation, FKeyword, 'a schema must be an object');
    end;
  finally
    Dec(FDepth);
  end;
end;

procedure TCompileSession.CompileObject(ANode: TJSONValue; const ALocation: string);
var
  SSchema, SValue, SConfig: TJSONValue;
  SKeyword, SLocation, SBase, Name: string;
  IdValue: TJSONValue;
  Def: TKeywordDefinition;
  Checker: TKeywordCheckerProc;
  I: Integer;
begin
  SSchema := FSchema;
  SValue := FValue;
  SConfig := FConfig;
  SKeyword := FKeyword;
  SLocation := FLocation;
  SBase := FBase;
  try
    FSchema := ANode;
    FLocation := ALocation;
    IdValue := ANode.FindMember(FDraft.IdKeyword);
    if (IdValue <> nil) and (IdValue.Kind = jkString) then
      HandleId(IdValue.StringValue, ANode);
    for I := 0 to ANode.Count - 1 do
    begin
      Name := ANode.Names[I];
      Def := FindDefinition(Name);
      if Def = nil then
        Continue;
      FKeyword := Name;
      FValue := ANode[I];
      FConfig := Def.Config;
      if Def.Unsupported then
      begin
        if not FCompiler.IgnoreUnsupportedKeywords then
          Error('keyword "' + Name + '" is not supported by this implementation');
      end
      else
      begin
        Checker := Def.Checker;
        if Assigned(Checker) then
          Checker(Self);
      end;
    end;
  finally
    FSchema := SSchema;
    FValue := SValue;
    FConfig := SConfig;
    FKeyword := SKeyword;
    FLocation := SLocation;
    FBase := SBase;
  end;
end;

procedure TCompileSession.ResolveRefs;
var
  I: Integer;
  Msg: string;
  Entry: TRefEntry;
begin
  for I := 0 to FCompiled.RefCount - 1 do
  begin
    Entry := FCompiled.Refs[I];
    if FCompiler.FStore.TryResolve(FCompiled, Entry, Msg) = roBadFragment then
      ErrorAt(Entry.Location, '$ref', Msg);
    { roNoResource: the target may be registered later; resolved lazily }
  end;
end;

procedure TCompileSession.Run;
var
  Errs: TValidationErrors;
  Msg: string;
begin
  FCompiled.AddResource('', FCompiled.Root);
  CompileNode(FCompiled.Root, '');
  ResolveRefs;
  if FErrors.Count > 0 then
  begin
    Msg := Format('Invalid schema "%s": %s (%d error(s))',
      [FCompiled.Id, FErrors[0].Message, FErrors.Count]);
    Errs := TValidationErrors.Create;
    Errs.AppendCopies(FErrors);
    raise ESchemaError.CreateWithErrors(Msg, Errs);
  end;
end;

function TCompileSession.Schema: TJSONValue;
begin
  Result := FSchema;
end;

function TCompileSession.KeywordValue: TJSONValue;
begin
  Result := FValue;
end;

function TCompileSession.Keyword: string;
begin
  Result := FKeyword;
end;

function TCompileSession.Config: TJSONValue;
begin
  Result := FConfig;
end;

function TCompileSession.SchemaLocation: string;
begin
  Result := KeywordLocation;
end;

function TCompileSession.DraftName: string;
begin
  Result := FDraft.Name;
end;

function TCompileSession.Sibling(const AName: string): TJSONValue;
begin
  Result := FSchema.FindMember(AName);
end;

procedure TCompileSession.Error(const AMessage: string);
begin
  ErrorAt(KeywordLocation, FKeyword, AMessage);
end;

procedure TCompileSession.CompileSubschema(ASubSchema: TJSONValue);
begin
  CompileNode(ASubSchema, KeywordLocation);
end;

procedure TCompileSession.CompileChild(ASubSchema: TJSONValue; const AToken: string);
begin
  CompileNode(ASubSchema, KeywordLocation + JsonPointerStep(AToken));
end;

function TCompileSession.IsKnownType(const ATypeName: string): Boolean;
begin
  Result := FCompiler.Types.IsRegistered(ATypeName);
end;

procedure TCompileSession.CheckPattern(const APattern: string);
var
  Msg: string;
begin
  if FCompiler.Regex.Get(APattern, Msg) = nil then
    Error('unsupported or invalid regular expression "' + APattern + '": ' + Msg);
end;

procedure TCompileSession.RegisterRef(ARefNode: TJSONValue);
begin
  FCompiled.AddRef(ARefNode, FBase, KeywordLocation);
end;

procedure TCompileSession.DeclareAnchor(const AName: string);
begin
  FCompiled.AddAnchor(FBase, AName, FSchema);
end;

{ ================= TSchemaCompiler ================= }

constructor TSchemaCompiler.Create(ADrafts: TDraftRegistry; ATypes: TTypeRegistry;
  AKeywords: TKeywordRegistry; ARegex: TSchemaRegexCache; AStore: TSchemaStore);
begin
  inherited Create;
  FDrafts := ADrafts;
  FTypes := ATypes;
  FKeywords := AKeywords;
  FRegex := ARegex;
  FStore := AStore;
end;

function TSchemaCompiler.Compile(const AId: string; ARoot: TJSONValue;
  AOwnsRoot: Boolean): TCompiledSchema;
var
  Draft: TJsonSchemaDraft;
  Compiled: TCompiledSchema;
  Session: TCompileSession;
begin
  try
    Draft := FDrafts.DraftForSchema(ARoot);
  except
    if AOwnsRoot then
      ARoot.Free;
    raise;
  end;
  Compiled := TCompiledSchema.Create(AId, ARoot, AOwnsRoot, Draft);
  try
    Session := TCompileSession.Create(Self, Compiled, Draft);
    try
      Session.Run;
    finally
      Session.Free;
    end;
    Result := Compiled;
    Compiled := nil;
  finally
    Compiled.Free;
  end;
end;

end.
