{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit JsonSchemaErrors;

{ Error model of the JSON Schema framework.

  Two families of problems are kept apart on purpose:
    * ESchemaError ......... the SCHEMA is invalid (malformed keyword value,
                             unsupported draft or keyword, unresolvable $ref).
    * EValidationError ..... the INSTANCE does not satisfy a valid schema
                             (only raised when ErrorMode = emRaise).
  Registration and file problems have their own exception types.

  Individual problems are TValidationError objects collected in a
  TValidationErrors list. Locations are JSON Pointers (RFC 6901); the empty
  string denotes the document root. }

interface

uses
  SysUtils, Classes, JSONPathCommon;

type
  TStringArray = array of string;

  { One problem found while compiling a schema or validating an instance }
  TValidationError = class
  private
    FMessage: string;
    FKeyword: string;
    FSchemaLocation: string;
    FInstanceLocation: string;
  public
    constructor Create(const AMessage, AKeyword, ASchemaLocation,
      AInstanceLocation: string);
    { One-line human readable description }
    function Describe: string;
    property Message: string read FMessage;
    { The violated keyword ('' when not applicable, e.g. a false schema) }
    property Keyword: string read FKeyword;
    { Pointer to the failing keyword inside the schema, following $ref steps }
    property SchemaLocation: string read FSchemaLocation;
    { Pointer to the offending value inside the instance }
    property InstanceLocation: string read FInstanceLocation;
  end;

  { Owning list of errors }
  TValidationErrors = class
  private
    FItems: TOwnedList;
    function GetCount: Integer;
    function GetItem(Index: Integer): TValidationError;
  public
    constructor Create;
    destructor Destroy; override;
    { Takes ownership of AError }
    procedure Add(AError: TValidationError);
    procedure AddNew(const AMessage, AKeyword, ASchemaLocation,
      AInstanceLocation: string);
    { Appends copies of all errors of ASource }
    procedure AppendCopies(ASource: TValidationErrors);
    procedure Clear;
    { Drops every error added after the list had ACount entries }
    procedure TruncateTo(ACount: Integer);
    { One Describe line per error }
    function ToText: string;
    property Count: Integer read GetCount;
    property Items[Index: Integer]: TValidationError read GetItem; default;
  end;

  { Outcome of a validation run. The owner frees it. }
  TValidationResult = class
  private
    FErrors: TValidationErrors;
  public
    { takes ownership of AErrors }
    constructor Create(AErrors: TValidationErrors);
    destructor Destroy; override;
    function IsValid: Boolean;
    { Hands the error list to the caller; the result becomes empty/valid }
    function DetachErrors: TValidationErrors;
    function ErrorText: string;
    property Errors: TValidationErrors read FErrors;
  end;

  EJsonSchemaError = class(Exception);

  { Base of the exceptions that carry a list of errors }
  EJsonSchemaDetailError = class(EJsonSchemaError)
  private
    FErrors: TValidationErrors;
  public
    { takes ownership of AErrors }
    constructor CreateWithErrors(const AMessage: string; AErrors: TValidationErrors);
    destructor Destroy; override;
    property Errors: TValidationErrors read FErrors;
  end;

  { The schema itself is invalid or unsupported }
  ESchemaError = class(EJsonSchemaDetailError);
  { The instance failed validation (raised only in emRaise mode) }
  EValidationError = class(EJsonSchemaDetailError);
  { Duplicate/unknown identifiers and registration-policy violations }
  ESchemaRegistrationError = class(EJsonSchemaError);
  { A schema file or directory could not be read or parsed }
  ESchemaLoadError = class(EJsonSchemaError)
  private
    FFileName: string;
  public
    constructor CreateForFile(const AFileName, AMessage: string);
    property FileName: string read FFileName;
  end;

{ JSON Pointer helpers. A "step" is "/" followed by one escaped token; steps
  are concatenated to build a location. }
function JsonPointerEscape(const AToken: string): string;
function JsonPointerUnescape(const AToken: string): string;
function JsonPointerStep(const AToken: string): string;
function JsonPointerIndexStep(AIndex: Integer): string;

{ Raises an ESchemaError carrying a single error }
procedure RaiseSchemaError(const AMessage, AKeyword, ASchemaLocation: string);

implementation

{ TValidationError }

constructor TValidationError.Create(const AMessage, AKeyword, ASchemaLocation,
  AInstanceLocation: string);
begin
  inherited Create;
  FMessage := AMessage;
  FKeyword := AKeyword;
  FSchemaLocation := ASchemaLocation;
  FInstanceLocation := AInstanceLocation;
end;

function TValidationError.Describe: string;
var
  Inst, Sch: string;
begin
  Inst := FInstanceLocation;
  if Inst = '' then
    Inst := '(root)';
  Sch := FSchemaLocation;
  if Sch = '' then
    Sch := '(root)';
  if FKeyword <> '' then
    Result := Format('%s [keyword: %s, instance: %s, schema: %s]',
      [FMessage, FKeyword, Inst, Sch])
  else
    Result := Format('%s [instance: %s, schema: %s]', [FMessage, Inst, Sch]);
end;

{ TValidationErrors }

constructor TValidationErrors.Create;
begin
  inherited Create;
  FItems := TOwnedList.Create;
end;

destructor TValidationErrors.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TValidationErrors.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TValidationErrors.GetItem(Index: Integer): TValidationError;
begin
  Result := TValidationError(FItems[Index]);
end;

procedure TValidationErrors.Add(AError: TValidationError);
begin
  FItems.Add(AError);
end;

procedure TValidationErrors.AddNew(const AMessage, AKeyword, ASchemaLocation,
  AInstanceLocation: string);
begin
  FItems.Add(TValidationError.Create(AMessage, AKeyword, ASchemaLocation,
    AInstanceLocation));
end;

procedure TValidationErrors.AppendCopies(ASource: TValidationErrors);
var
  I: Integer;
begin
  for I := 0 to ASource.Count - 1 do
    AddNew(ASource[I].Message, ASource[I].Keyword, ASource[I].SchemaLocation,
      ASource[I].InstanceLocation);
end;

procedure TValidationErrors.Clear;
begin
  FItems.Clear;
end;

procedure TValidationErrors.TruncateTo(ACount: Integer);
begin
  FItems.TruncateTo(ACount);
end;

function TValidationErrors.ToText: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Count - 1 do
  begin
    if I > 0 then
      Result := Result + #10;
    Result := Result + Items[I].Describe;
  end;
end;

{ TValidationResult }

constructor TValidationResult.Create(AErrors: TValidationErrors);
begin
  inherited Create;
  if AErrors = nil then
    FErrors := TValidationErrors.Create
  else
    FErrors := AErrors;
end;

destructor TValidationResult.Destroy;
begin
  FErrors.Free;
  inherited Destroy;
end;

function TValidationResult.IsValid: Boolean;
begin
  Result := FErrors.Count = 0;
end;

function TValidationResult.DetachErrors: TValidationErrors;
begin
  Result := FErrors;
  FErrors := TValidationErrors.Create;
end;

function TValidationResult.ErrorText: string;
begin
  Result := FErrors.ToText;
end;

{ exceptions }

constructor EJsonSchemaDetailError.CreateWithErrors(const AMessage: string;
  AErrors: TValidationErrors);
begin
  inherited Create(AMessage);
  if AErrors = nil then
    FErrors := TValidationErrors.Create
  else
    FErrors := AErrors;
end;

destructor EJsonSchemaDetailError.Destroy;
begin
  FErrors.Free;
  inherited Destroy;
end;

constructor ESchemaLoadError.CreateForFile(const AFileName, AMessage: string);
begin
  inherited Create(AFileName + ': ' + AMessage);
  FFileName := AFileName;
end;

{ JSON Pointer }

function JsonPointerEscape(const AToken: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(AToken) do
    case AToken[I] of
      '~': Result := Result + '~0';
      '/': Result := Result + '~1';
    else
      Result := Result + AToken[I];
    end;
end;

function JsonPointerUnescape(const AToken: string): string;
var
  I: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(AToken) do
  begin
    if (AToken[I] = '~') and (I < Length(AToken)) and (AToken[I + 1] = '1') then
    begin
      Result := Result + '/';
      Inc(I, 2);
    end
    else if (AToken[I] = '~') and (I < Length(AToken)) and (AToken[I + 1] = '0') then
    begin
      Result := Result + '~';
      Inc(I, 2);
    end
    else
    begin
      Result := Result + AToken[I];
      Inc(I);
    end;
  end;
end;

function JsonPointerStep(const AToken: string): string;
begin
  Result := '/' + JsonPointerEscape(AToken);
end;

function JsonPointerIndexStep(AIndex: Integer): string;
begin
  Result := '/' + IntToStr(AIndex);
end;

procedure RaiseSchemaError(const AMessage, AKeyword, ASchemaLocation: string);
var
  Errs: TValidationErrors;
begin
  Errs := TValidationErrors.Create;
  Errs.AddNew(AMessage, AKeyword, ASchemaLocation, '');
  raise ESchemaError.CreateWithErrors(AMessage, Errs);
end;

end.
