{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit JSONPathJSON;

{ JSON document model, parser, writer and builder.

  LOSSLESS NUMBERS
    Every number keeps (a) its Double value, (b) the text it was written with
    and (c) when possible an exact base-10 form: an Int64 for integer literals
    (64-bit ids) and an unscaled Int64 + scale for plain decimal literals
    (money). Consequences:
      * 1 and 1.0 stay different texts but compare equal (same value);
      * 9223372036854775807 survives parsing, equality and writing exactly;
      * 19.99 is exactly 1999 / 10^2 and AsCurrency is exact;
      * literals too big for that (or written with an exponent) keep their text,
        so writing them back is still lossless.

  PARSER OPTIONS (TJSONParseOptions)
    comments (// and slash-star), trailing commas (JSON5 style), duplicate key
    policy and a configurable nesting limit. Parse errors carry offset, line and
    column.

  WRITER OPTIONS (TJSONWriteOptions)
    indentation, sorted keys, \u escaping of non-ASCII characters, original or
    normalised numbers and canonical output (RFC 8785).

  BUILDER
    TJSONBuilder assembles documents with a fluent API. }

interface

uses
  SysUtils, Classes, JSONPathCommon;

type
  { Raised for malformed JSON. Position is the 0-based offset; Line and Column
    (both 1-based, 0 when unknown) are counted in string elements, i.e. bytes
    on Free Pascal and UTF-16 units on Delphi. }
  EJSONPathJSONError = class(Exception)
  private
    FPosition: Integer;
    FLine: Integer;
    FColumn: Integer;
  public
    constructor CreateAt(const AMessage: string; APosition: Integer);
    constructor CreateAtLineColumn(const AMessage: string; APosition, ALine,
      AColumn: Integer);
    property Position: Integer read FPosition;
    property Line: Integer read FLine;
    property Column: Integer read FColumn;
  end;

  { Misuse of TJSONBuilder }
  EJSONBuilderError = class(Exception);

  TJSONKind = (jkNull, jkBoolean, jkNumber, jkString, jkArray, jkObject);

  TDuplicateKeyPolicy = (dkLastWins, dkFirstWins, dkError);

  TJSONParseOptions = record
    { accept // line comments and slash-star block comments }
    AllowComments: Boolean;
    (* accept a comma before the closing ] or } *)
    AllowTrailingCommas: Boolean;
    { what to do when an object repeats a member name }
    DuplicateKeys: TDuplicateKeyPolicy;
    { maximum nesting of arrays/objects (default 512) }
    MaxDepth: Integer;
  end;

  TJSONWriteOptions = record
    { spaces per level; 0 = compact }
    Indent: Integer;
    { order members by their UTF-16 code units }
    SortKeys: Boolean;
    { write every non-ASCII character as \uXXXX }
    EscapeNonAscii: Boolean;
    { True: write numbers exactly as they were parsed; False: normalise
      through Double (1e2 becomes 100, 1.0 becomes 1) }
    OriginalNumbers: Boolean;
    { RFC 8785 (JSON Canonicalization Scheme): compact, members sorted,
      ECMAScript number formatting; overrides the options above }
    Canonical: Boolean;
  end;

  TJSONValue = class
  private
    FKind: TJSONKind;
    FBool: Boolean;
    FNumber: Double;
    FNumText: string;
    FExactKind: Integer; { 0 = Double only, 1 = Int64, 2 = decimal }
    FInt: Int64;
    FScale: Integer;
    FText: string;
    FItems: TOwnedList;
    FNames: array of string;
    FNameCount: Integer;
    function GetCount: Integer;
    function GetItem(Index: Integer): TJSONValue;
    function GetName(Index: Integer): string;
    function IndexOfName(const AName: string): Integer;
    procedure SetNumberValue(AValue: Double);
    function GetNumberText: string;
    function GetIsExactInt64: Boolean;
    function GetIsNull: Boolean;
    function GetIsBoolean: Boolean;
    function GetIsNumber: Boolean;
    function GetIsInteger: Boolean;
    function GetIsString: Boolean;
    function GetIsArray: Boolean;
    function GetIsObject: Boolean;
    function GetAsBoolean: Boolean;
    function GetAsNumber: Double;
    function GetAsInteger: Int64;
    function GetAsCurrency: Currency;
    function GetAsString: string;
  public
    constructor Create(AKind: TJSONKind);
    destructor Destroy; override;
    { Arrays: appends. Takes ownership of AValue. }
    procedure AddItem(AValue: TJSONValue);
    { Objects: adds or replaces a member. Takes ownership of AValue. }
    procedure SetMember(const AName: string; AValue: TJSONValue);
    function FindMember(const AName: string): TJSONValue;
    property Kind: TJSONKind read FKind;
    property BoolValue: Boolean read FBool write FBool;
    { Assigning a Double discards the original text and the exact forms }
    property NumberValue: Double read FNumber write SetNumberValue;
    property StringValue: string read FText write FText;
    { Element count for arrays, member count for objects, 0 otherwise }
    property Count: Integer read GetCount;
    { Element (arrays) or member value (objects) }
    property Items[Index: Integer]: TJSONValue read GetItem; default;
    { Member name (objects only) }
    property Names[Index: Integer]: string read GetName;

    { ---- lossless numbers ---- }
    { The text the number was written with; for numbers that were not parsed
      the shortest faithful text (Int64 / decimal / Double) }
    property NumberText: string read GetNumberText;
    { True when the number is an integer literal that fits an Int64 exactly }
    property IsExactInt64: Boolean read GetIsExactInt64;
    { True and the value when the number is integral and exactly representable
      as an Int64 (also decimals such as 1.0 or 12.50 * 2) }
    function TryGetInt64(out AValue: Int64): Boolean;
    { True and the exact base-10 form (value = AUnscaled / 10^AScale) for
      integer and plain decimal literals with at most 18 fractional digits }
    function TryGetDecimal(out AUnscaled: Int64; out AScale: Integer): Boolean;

    { ---- kind tests (based on Kind) ---- }
    property IsNull: Boolean read GetIsNull;
    property IsBoolean: Boolean read GetIsBoolean;
    property IsNumber: Boolean read GetIsNumber;
    { A number without fractional part that fits into an Int64 }
    property IsInteger: Boolean read GetIsInteger;
    property IsString: Boolean read GetIsString;
    property IsArray: Boolean read GetIsArray;
    property IsObject: Boolean read GetIsObject;

    { ---- lenient conversions (never raise) ----
      A value that cannot be converted yields the default of the result
      type (False, 0, 0 and '').
      AsBoolean  null -> False; boolean -> itself; number -> <> 0;
                 string -> <> ''; array/object -> Count > 0
      AsNumber   null -> 0; boolean -> 1/0; number -> itself;
                 string -> parsed number, 0 when it is not one;
                 array/object -> 0
      AsInteger  exact for integral numbers that fit an Int64, otherwise like
                 AsNumber truncated toward zero; 0 when out of range
      AsCurrency exact for decimals with at most 4 fractional digits
      AsString   null -> ''; boolean -> 'true'/'false'; number -> NumberText;
                 string -> itself; array/object -> compact JSON text }
    property AsBoolean: Boolean read GetAsBoolean;
    property AsNumber: Double read GetAsNumber;
    property AsInteger: Int64 read GetAsInteger;
    property AsCurrency: Currency read GetAsCurrency;
    property AsString: string read GetAsString;
  end;

  { Fluent document builder.

      Doc := B.BeginObject
               .PutString('name', 'Ann')
               .PutInt('id', 9223372036854775807)
               .PutDecimal('price', 1999, 2)
               .BeginArray('tags').AddString('a').AddString('b').EndArray
               .BeginObject('address').PutString('city', 'Oslo').EndObject
             .EndObject.Build;

    Inside an object use Put* / Begin*(Name); inside an array (or at the root)
    use Add* / Begin*. Misuse raises EJSONBuilderError. The builder owns the
    document until Build hands it over; an unfinished document is freed with
    the builder. }
  TJSONBuilder = class
  private
    FRoot: TJSONValue;
    FStack: TList;
    function Top: TJSONValue;
    procedure Attach(AValue: TJSONValue);
    procedure AttachNamed(const AName: string; AValue: TJSONValue);
    procedure Push(AValue: TJSONValue);
    function GetDepth: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    { root value or array elements }
    function AddString(const AValue: string): TJSONBuilder;
    function AddInt(AValue: Int64): TJSONBuilder;
    function AddNumber(AValue: Double): TJSONBuilder;
    { a number given as JSON text; kept exactly (e.g. '12345678901234567890') }
    function AddNumberText(const AText: string): TJSONBuilder;
    { AUnscaled / 10^AScale, e.g. (1999, 2) is 19.99 }
    function AddDecimal(AUnscaled: Int64; AScale: Integer): TJSONBuilder;
    function AddBool(AValue: Boolean): TJSONBuilder;
    function AddNull: TJSONBuilder;
    { takes ownership of AValue }
    function AddValue(AValue: TJSONValue): TJSONBuilder;
    function BeginObject: TJSONBuilder; overload;
    function BeginArray: TJSONBuilder; overload;
    { object members }
    function PutString(const AName, AValue: string): TJSONBuilder;
    function PutInt(const AName: string; AValue: Int64): TJSONBuilder;
    function PutNumber(const AName: string; AValue: Double): TJSONBuilder;
    function PutNumberText(const AName, AText: string): TJSONBuilder;
    function PutDecimal(const AName: string; AUnscaled: Int64;
      AScale: Integer): TJSONBuilder;
    function PutBool(const AName: string; AValue: Boolean): TJSONBuilder;
    function PutNull(const AName: string): TJSONBuilder;
    { takes ownership of AValue }
    function PutValue(const AName: string; AValue: TJSONValue): TJSONBuilder;
    function BeginObject(const AName: string): TJSONBuilder; overload;
    function BeginArray(const AName: string): TJSONBuilder; overload;
    function EndObject: TJSONBuilder;
    function EndArray: TJSONBuilder;
    { Returns the finished document (the caller owns it). All containers must
      be closed. The builder is empty afterwards. }
    function Build: TJSONValue;
    { number of containers that are still open }
    property Depth: Integer read GetDepth;
  end;

function NewJSONNull: TJSONValue;
function NewJSONBool(AValue: Boolean): TJSONValue;
function NewJSONNumber(AValue: Double): TJSONValue;
{ An integer that is kept exactly }
function NewJSONInt64(AValue: Int64): TJSONValue;
{ AUnscaled / 10^AScale kept exactly (AScale 0..18) }
function NewJSONDecimal(AUnscaled: Int64; AScale: Integer): TJSONValue;
{ A number from JSON text; the text is kept as written. Raises
  EJSONPathJSONError when AText is not a JSON number. }
function NewJSONNumberText(const AText: string): TJSONValue;
function NewJSONString(const AValue: string): TJSONValue;
function NewJSONArray: TJSONValue;
function NewJSONObject: TJSONValue;

function DefaultJSONParseOptions: TJSONParseOptions;
{ comments and trailing commas allowed }
function LenientJSONParseOptions: TJSONParseOptions;
function DefaultJSONWriteOptions: TJSONWriteOptions;

{ Parses JSON text (strict RFC 8259 defaults). The caller owns the result.
  Raises EJSONPathJSONError. }
function ParseJSON(const AText: string): TJSONValue; overload;
function ParseJSON(const AText: string; const AOptions: TJSONParseOptions): TJSONValue; overload;

{ Compact serialization with the default write options (numbers as written) }
function JSONToText(AValue: TJSONValue): string; overload;
function JSONToText(AValue: TJSONValue; const AOptions: TJSONWriteOptions): string; overload;
{ Pretty-printed serialization. Ident is the number of spaces per nesting
  level; members and elements go on their own lines (LF line breaks), empty
  arrays and objects stay on one line. Ident <= 0 falls back to compact
  output. }
function JSONToTextPretty(AValue: TJSONValue; Ident: Integer): string;
{ RFC 8785 canonical form }
function JSONCanonicalText(AValue: TJSONValue): string;
function JSONQuoteString(const S: string): string;

{ Deep equality as defined by RFC 9535 section 2.3.5.2.2. Numbers are
  compared exactly when both have an exact form, otherwise as Doubles. }
function JSONEquals(A, B: TJSONValue): Boolean;
{ -1, 0 or 1; both values must be numbers (other kinds compare as 0) }
function JSONNumberCompare(A, B: TJSONValue): Integer;

implementation

{ ======================= errors ======================= }

constructor EJSONPathJSONError.CreateAt(const AMessage: string; APosition: Integer);
begin
  inherited Create(Format('JSON error at position %d: %s', [APosition, AMessage]));
  FPosition := APosition;
end;

constructor EJSONPathJSONError.CreateAtLineColumn(const AMessage: string;
  APosition, ALine, AColumn: Integer);
begin
  inherited Create(Format('JSON error at line %d, column %d (offset %d): %s',
    [ALine, AColumn, APosition, AMessage]));
  FPosition := APosition;
  FLine := ALine;
  FColumn := AColumn;
end;

{ ======================= number helpers ======================= }

function Pow10Int64(AScale: Integer): Int64;
var
  I: Integer;
begin
  Result := 1;
  for I := 1 to AScale do
    Result := Result * 10;
end;

function DecimalToText(AUnscaled: Int64; AScale: Integer): string;
var
  Digits: string;
  Neg: Boolean;
begin
  Digits := IntToStr(AUnscaled);
  Neg := (Digits <> '') and (Digits[1] = '-');
  if Neg then
    Delete(Digits, 1, 1);
  if AScale > 0 then
  begin
    while Length(Digits) <= AScale do
      Digits := '0' + Digits;
    Digits := Copy(Digits, 1, Length(Digits) - AScale) + '.' +
      Copy(Digits, Length(Digits) - AScale + 1, AScale);
  end;
  if Neg then
    Result := '-' + Digits
  else
    Result := Digits;
end;

{ Builds a number from validated JSON number text. Returns False when the
  value cannot be represented as a finite Double. }
function TryMakeNumber(const AText: string; out AValue: TJSONValue): Boolean;
var
  D: Double;
  I, N, Digit, FracDigits: Integer;
  C: Char;
  Neg, HasFrac, HasExp, Overflow: Boolean;
  Acc: Int64;
begin
  AValue := nil;
  Result := False;
  if not TryJSONTextToDouble(AText, D) then
    Exit;
  if (D <> D) or (D > 1.7E308) or (D < -1.7E308) then
    Exit;
  AValue := TJSONValue.Create(jkNumber);
  AValue.FNumber := D;
  AValue.FNumText := AText;
  Result := True;
  { exact forms: accumulate the digits as a negative Int64 so that the
    smallest Int64 is representable too }
  N := Length(AText);
  I := 1;
  Neg := False;
  if (I <= N) and (AText[I] = '-') then
  begin
    Neg := True;
    Inc(I);
  end;
  Acc := 0;
  Overflow := False;
  HasFrac := False;
  HasExp := False;
  FracDigits := 0;
  while I <= N do
  begin
    C := AText[I];
    if (C >= '0') and (C <= '9') then
    begin
      if not Overflow then
      begin
        Digit := Ord(C) - Ord('0');
        if Acc < (Low(Int64) + Digit) div 10 then
          Overflow := True
        else
          Acc := Acc * 10 - Digit;
      end;
      if HasFrac then
        Inc(FracDigits);
    end
    else if C = '.' then
      HasFrac := True
    else
    begin
      HasExp := True;
      Break;
    end;
    Inc(I);
  end;
  if HasExp or Overflow or (FracDigits > 18) then
    Exit;
  if not Neg then
  begin
    if Acc = Low(Int64) then
      Exit;
    Acc := -Acc;
  end;
  AValue.FInt := Acc;
  AValue.FScale := FracDigits;
  if HasFrac then
    AValue.FExactKind := 2
  else
    AValue.FExactKind := 1;
end;

{ Strict JSON number grammar }
function IsValidNumberText(const S: string): Boolean;
var
  I, N: Integer;

  function Digits: Boolean;
  var
    Start: Integer;
  begin
    Start := I;
    while (I <= N) and (S[I] >= '0') and (S[I] <= '9') do
      Inc(I);
    Result := I > Start;
  end;

begin
  Result := False;
  N := Length(S);
  I := 1;
  if (I <= N) and (S[I] = '-') then
    Inc(I);
  if I > N then
    Exit;
  if S[I] = '0' then
    Inc(I)
  else if not Digits then
    Exit;
  if (I <= N) and (S[I] = '.') then
  begin
    Inc(I);
    if not Digits then
      Exit;
  end;
  if (I <= N) and ((S[I] = 'e') or (S[I] = 'E')) then
  begin
    Inc(I);
    if (I <= N) and ((S[I] = '+') or (S[I] = '-')) then
      Inc(I);
    if not Digits then
      Exit;
  end;
  Result := I = N + 1;
end;

{ ======================= TJSONValue ======================= }

constructor TJSONValue.Create(AKind: TJSONKind);
begin
  inherited Create;
  FKind := AKind;
  if (AKind = jkArray) or (AKind = jkObject) then
    FItems := TOwnedList.Create;
end;

destructor TJSONValue.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TJSONValue.GetCount: Integer;
begin
  if FItems <> nil then
    Result := FItems.Count
  else
    Result := 0;
end;

function TJSONValue.GetItem(Index: Integer): TJSONValue;
begin
  Result := TJSONValue(FItems[Index]);
end;

function TJSONValue.GetName(Index: Integer): string;
begin
  Result := FNames[Index];
end;

function TJSONValue.IndexOfName(const AName: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to FNameCount - 1 do
    if FNames[I] = AName then
    begin
      Result := I;
      Exit;
    end;
end;

procedure TJSONValue.AddItem(AValue: TJSONValue);
begin
  if FKind <> jkArray then
  begin
    AValue.Free;
    raise EJSONPathJSONError.CreateAt('AddItem requires an array', 0);
  end;
  FItems.Add(AValue);
end;

procedure TJSONValue.SetMember(const AName: string; AValue: TJSONValue);
var
  Idx: Integer;
begin
  if FKind <> jkObject then
  begin
    AValue.Free;
    raise EJSONPathJSONError.CreateAt('SetMember requires an object', 0);
  end;
  Idx := IndexOfName(AName);
  if Idx >= 0 then
    FItems.Replace(Idx, AValue)
  else
  begin
    if FNameCount >= Length(FNames) then
      SetLength(FNames, FNameCount * 2 + 4);
    FNames[FNameCount] := AName;
    Inc(FNameCount);
    FItems.Add(AValue);
  end;
end;

function TJSONValue.FindMember(const AName: string): TJSONValue;
var
  Idx: Integer;
begin
  Result := nil;
  if FKind <> jkObject then
    Exit;
  Idx := IndexOfName(AName);
  if Idx >= 0 then
    Result := TJSONValue(FItems[Idx]);
end;

procedure TJSONValue.SetNumberValue(AValue: Double);
begin
  FNumber := AValue;
  FNumText := '';
  FExactKind := 0;
  FInt := 0;
  FScale := 0;
end;

function TJSONValue.GetNumberText: string;
begin
  if FKind <> jkNumber then
    Result := ''
  else if FNumText <> '' then
    Result := FNumText
  else if FExactKind = 1 then
    Result := IntToStr(FInt)
  else if FExactKind = 2 then
    Result := DecimalToText(FInt, FScale)
  else
    Result := DoubleToJSONText(FNumber);
end;

function TJSONValue.GetIsExactInt64: Boolean;
begin
  Result := (FKind = jkNumber) and (FExactKind = 1);
end;

function TJSONValue.TryGetInt64(out AValue: Int64): Boolean;
var
  Pow: Int64;
begin
  AValue := 0;
  Result := False;
  if FKind <> jkNumber then
    Exit;
  case FExactKind of
    1:
      begin
        AValue := FInt;
        Result := True;
      end;
    2:
      begin
        Pow := Pow10Int64(FScale);
        if FInt mod Pow = 0 then
        begin
          AValue := FInt div Pow;
          Result := True;
        end;
      end;
  else
    if (Frac(FNumber) = 0) and (Abs(FNumber) < 9.2E18) then
    begin
      AValue := Trunc(FNumber);
      Result := True;
    end;
  end;
end;

function TJSONValue.TryGetDecimal(out AUnscaled: Int64; out AScale: Integer): Boolean;
begin
  AUnscaled := 0;
  AScale := 0;
  Result := (FKind = jkNumber) and (FExactKind <> 0);
  if Result then
  begin
    AUnscaled := FInt;
    AScale := FScale;
  end;
end;

function TJSONValue.GetIsNull: Boolean;
begin
  Result := FKind = jkNull;
end;

function TJSONValue.GetIsBoolean: Boolean;
begin
  Result := FKind = jkBoolean;
end;

function TJSONValue.GetIsNumber: Boolean;
begin
  Result := FKind = jkNumber;
end;

function TJSONValue.GetIsInteger: Boolean;
var
  Dummy: Int64;
begin
  Result := TryGetInt64(Dummy);
end;

function TJSONValue.GetIsString: Boolean;
begin
  Result := FKind = jkString;
end;

function TJSONValue.GetIsArray: Boolean;
begin
  Result := FKind = jkArray;
end;

function TJSONValue.GetIsObject: Boolean;
begin
  Result := FKind = jkObject;
end;

function TJSONValue.GetAsBoolean: Boolean;
begin
  case FKind of
    jkBoolean: Result := FBool;
    jkNumber: Result := FNumber <> 0;
    jkString: Result := FText <> '';
    jkArray, jkObject: Result := Count > 0;
  else
    Result := False;
  end;
end;

function TJSONValue.GetAsNumber: Double;
var
  D: Double;
begin
  Result := 0;
  case FKind of
    jkBoolean:
      if FBool then
        Result := 1;
    jkNumber:
      Result := FNumber;
    jkString:
      if TryJSONTextToDouble(Trim(FText), D) and (D = D)
        and (D < 1.7E308) and (D > -1.7E308) then
        Result := D;
  end;
end;

function TJSONValue.GetAsInteger: Int64;
var
  D: Double;
begin
  if TryGetInt64(Result) then
    Exit;
  D := GetAsNumber;
  if Abs(D) < 9.2E18 then
    Result := Trunc(D)
  else
    Result := 0;
end;

function TJSONValue.GetAsCurrency: Currency;
var
  C: Currency;
  Bits: Int64 absolute C;
  U, Scaled: Int64;
  S, I: Integer;
  Fits: Boolean;
begin
  if (FKind = jkNumber) and TryGetDecimal(U, S) and (S <= 4) then
  begin
    Scaled := U;
    Fits := True;
    for I := S to 3 do
    begin
      if (Scaled > High(Int64) div 10) or (Scaled < Low(Int64) div 10) then
      begin
        Fits := False;
        Break;
      end;
      Scaled := Scaled * 10;
    end;
    if Fits then
    begin
      Bits := Scaled;
      Result := C;
      Exit;
    end;
  end;
  Result := GetAsNumber;
end;

function TJSONValue.GetAsString: string;
begin
  case FKind of
    jkBoolean:
      if FBool then Result := 'true' else Result := 'false';
    jkNumber: Result := GetNumberText;
    jkString: Result := FText;
    jkArray, jkObject: Result := JSONToText(Self);
  else
    Result := '';
  end;
end;

{ ======================= factories ======================= }

function NewJSONNull: TJSONValue;
begin
  Result := TJSONValue.Create(jkNull);
end;

function NewJSONBool(AValue: Boolean): TJSONValue;
begin
  Result := TJSONValue.Create(jkBoolean);
  Result.BoolValue := AValue;
end;

function NewJSONNumber(AValue: Double): TJSONValue;
begin
  Result := TJSONValue.Create(jkNumber);
  Result.FNumber := AValue;
end;

function NewJSONInt64(AValue: Int64): TJSONValue;
begin
  Result := TJSONValue.Create(jkNumber);
  Result.FNumber := AValue;
  Result.FExactKind := 1;
  Result.FInt := AValue;
end;

function NewJSONDecimal(AUnscaled: Int64; AScale: Integer): TJSONValue;
begin
  if (AScale < 0) or (AScale > 18) then
    raise EJSONPathJSONError.CreateAt('decimal scale must be between 0 and 18', 0);
  Result := TJSONValue.Create(jkNumber);
  Result.FNumber := AUnscaled / Pow10Int64(AScale);
  if AScale = 0 then
    Result.FExactKind := 1
  else
    Result.FExactKind := 2;
  Result.FInt := AUnscaled;
  Result.FScale := AScale;
end;

function NewJSONNumberText(const AText: string): TJSONValue;
begin
  if (not IsValidNumberText(AText)) or (not TryMakeNumber(AText, Result)) then
    raise EJSONPathJSONError.CreateAt('"' + AText + '" is not a valid JSON number', 0);
end;

function NewJSONString(const AValue: string): TJSONValue;
begin
  Result := TJSONValue.Create(jkString);
  Result.StringValue := AValue;
end;

function NewJSONArray: TJSONValue;
begin
  Result := TJSONValue.Create(jkArray);
end;

function NewJSONObject: TJSONValue;
begin
  Result := TJSONValue.Create(jkObject);
end;

function DefaultJSONParseOptions: TJSONParseOptions;
begin
  Result.AllowComments := False;
  Result.AllowTrailingCommas := False;
  Result.DuplicateKeys := dkLastWins;
  Result.MaxDepth := 512;
end;

function LenientJSONParseOptions: TJSONParseOptions;
begin
  Result := DefaultJSONParseOptions;
  Result.AllowComments := True;
  Result.AllowTrailingCommas := True;
end;

function DefaultJSONWriteOptions: TJSONWriteOptions;
begin
  Result.Indent := 0;
  Result.SortKeys := False;
  Result.EscapeNonAscii := False;
  Result.OriginalNumbers := True;
  Result.Canonical := False;
end;

{ ======================= parser ======================= }

type
  TJSONTextParser = class
  private
    FText: string;
    FPos: Integer;
    FLen: Integer;
    FDepth: Integer;
    FOptions: TJSONParseOptions;
    procedure FailAt(APos: Integer; const AMessage: string);
    procedure Fail(const AMessage: string);
    procedure SkipWhitespace;
    function ParseValue: TJSONValue;
    function ParseObject: TJSONValue;
    function ParseArray: TJSONValue;
    function ParseString: string;
    function ParseNumber: TJSONValue;
    function ParseHex4: Cardinal;
    function MatchWord(const AWord: string): Boolean;
    procedure EnterContainer;
  public
    constructor Create(const AText: string; const AOptions: TJSONParseOptions);
    function ParseDocument: TJSONValue;
  end;

constructor TJSONTextParser.Create(const AText: string; const AOptions: TJSONParseOptions);
begin
  inherited Create;
  FText := AText;
  FLen := Length(AText);
  FPos := 1;
  FOptions := AOptions;
end;

procedure TJSONTextParser.FailAt(APos: Integer; const AMessage: string);
var
  I, Line, LineStart: Integer;
begin
  if APos < 1 then
    APos := 1;
  if APos > FLen + 1 then
    APos := FLen + 1;
  Line := 1;
  LineStart := 1;
  for I := 1 to APos - 1 do
    if FText[I] = #10 then
    begin
      Inc(Line);
      LineStart := I + 1;
    end;
  raise EJSONPathJSONError.CreateAtLineColumn(AMessage, APos - 1, Line, APos - LineStart + 1);
end;

procedure TJSONTextParser.Fail(const AMessage: string);
begin
  FailAt(FPos, AMessage);
end;

procedure TJSONTextParser.SkipWhitespace;
var
  C: Char;
  Start: Integer;
begin
  while FPos <= FLen do
  begin
    C := FText[FPos];
    if (C = ' ') or (C = #9) or (C = #10) or (C = #13) then
      Inc(FPos)
    else if FOptions.AllowComments and (C = '/') then
    begin
      if (FPos < FLen) and (FText[FPos + 1] = '/') then
      begin
        Inc(FPos, 2);
        while (FPos <= FLen) and (FText[FPos] <> #10) and (FText[FPos] <> #13) do
          Inc(FPos);
      end
      else if (FPos < FLen) and (FText[FPos + 1] = '*') then
      begin
        Start := FPos;
        Inc(FPos, 2);
        while True do
        begin
          if FPos >= FLen then
            FailAt(Start, 'unterminated comment');
          if (FText[FPos] = '*') and (FText[FPos + 1] = '/') then
          begin
            Inc(FPos, 2);
            Break;
          end;
          Inc(FPos);
        end;
      end
      else
        Break;
    end
    else
      Break;
  end;
end;

function TJSONTextParser.MatchWord(const AWord: string): Boolean;
begin
  Result := Copy(FText, FPos, Length(AWord)) = AWord;
  if Result then
    Inc(FPos, Length(AWord));
end;

procedure TJSONTextParser.EnterContainer;
begin
  Inc(FDepth);
  if FDepth > FOptions.MaxDepth then
    Fail('maximum nesting depth of ' + IntToStr(FOptions.MaxDepth) + ' exceeded');
end;

function TJSONTextParser.ParseHex4: Cardinal;
var
  I, D: Integer;
begin
  Result := 0;
  for I := 1 to 4 do
  begin
    if FPos > FLen then
      Fail('incomplete \u escape');
    D := HexDigitValue(FText[FPos]);
    if D < 0 then
      Fail('invalid hex digit in \u escape');
    Result := (Result shl 4) or Cardinal(D);
    Inc(FPos);
  end;
end;

function TJSONTextParser.ParseString: string;
var
  Start: Integer;
  C: Char;
  CP, LowSur: Cardinal;
begin
  Inc(FPos); { opening quote }
  Result := '';
  Start := FPos;
  while True do
  begin
    if FPos > FLen then
      Fail('unterminated string');
    C := FText[FPos];
    if C = '"' then
    begin
      Result := Result + Copy(FText, Start, FPos - Start);
      Inc(FPos);
      Exit;
    end
    else if C = '\' then
    begin
      Result := Result + Copy(FText, Start, FPos - Start);
      Inc(FPos);
      if FPos > FLen then
        Fail('unterminated escape sequence');
      C := FText[FPos];
      Inc(FPos);
      case C of
        '"': Result := Result + '"';
        '\': Result := Result + '\';
        '/': Result := Result + '/';
        'b': Result := Result + #8;
        'f': Result := Result + #12;
        'n': Result := Result + #10;
        'r': Result := Result + #13;
        't': Result := Result + #9;
        'u':
          begin
            CP := ParseHex4;
            if (CP >= $D800) and (CP <= $DBFF) then
            begin
              if Copy(FText, FPos, 2) = '\u' then
              begin
                Inc(FPos, 2);
                LowSur := ParseHex4;
                if (LowSur >= $DC00) and (LowSur <= $DFFF) then
                  CP := $10000 + ((CP - $D800) shl 10) + (LowSur - $DC00)
                else
                  Fail('invalid low surrogate');
              end
              else
                Fail('lone high surrogate');
            end
            else if (CP >= $DC00) and (CP <= $DFFF) then
              Fail('lone low surrogate');
            AppendCodePoint(Result, CP);
          end;
      else
        Dec(FPos);
        Fail('invalid escape sequence');
      end;
      Start := FPos;
    end
    else
    begin
      if Ord(C) < $20 then
        Fail('unescaped control character in string');
      Inc(FPos);
    end;
  end;
end;

function TJSONTextParser.ParseNumber: TJSONValue;
var
  Start: Integer;
begin
  Start := FPos;
  if (FPos <= FLen) and (FText[FPos] = '-') then
    Inc(FPos);
  if (FPos > FLen) or not ((FText[FPos] >= '0') and (FText[FPos] <= '9')) then
    Fail('digit expected');
  if FText[FPos] = '0' then
    Inc(FPos)
  else
    while (FPos <= FLen) and (FText[FPos] >= '0') and (FText[FPos] <= '9') do
      Inc(FPos);
  if (FPos <= FLen) and (FText[FPos] = '.') then
  begin
    Inc(FPos);
    if (FPos > FLen) or not ((FText[FPos] >= '0') and (FText[FPos] <= '9')) then
      Fail('digit expected after decimal point');
    while (FPos <= FLen) and (FText[FPos] >= '0') and (FText[FPos] <= '9') do
      Inc(FPos);
  end;
  if (FPos <= FLen) and ((FText[FPos] = 'e') or (FText[FPos] = 'E')) then
  begin
    Inc(FPos);
    if (FPos <= FLen) and ((FText[FPos] = '+') or (FText[FPos] = '-')) then
      Inc(FPos);
    if (FPos > FLen) or not ((FText[FPos] >= '0') and (FText[FPos] <= '9')) then
      Fail('digit expected in exponent');
    while (FPos <= FLen) and (FText[FPos] >= '0') and (FText[FPos] <= '9') do
      Inc(FPos);
  end;
  if not TryMakeNumber(Copy(FText, Start, FPos - Start), Result) then
    FailAt(Start, 'number out of range');
end;

function TJSONTextParser.ParseArray: TJSONValue;
var
  Node: TJSONValue;
begin
  EnterContainer;
  Node := NewJSONArray;
  try
    Inc(FPos); { [ }
    SkipWhitespace;
    if (FPos <= FLen) and (FText[FPos] = ']') then
      Inc(FPos)
    else
      while True do
      begin
        Node.AddItem(ParseValue);
        SkipWhitespace;
        if FPos > FLen then
          Fail('unterminated array');
        if FText[FPos] = ',' then
        begin
          Inc(FPos);
          if FOptions.AllowTrailingCommas then
          begin
            SkipWhitespace;
            if (FPos <= FLen) and (FText[FPos] = ']') then
            begin
              Inc(FPos);
              Break;
            end;
          end;
        end
        else if FText[FPos] = ']' then
        begin
          Inc(FPos);
          Break;
        end
        else
          Fail('"," or "]" expected');
      end;
    Dec(FDepth);
    Result := Node;
    Node := nil;
  finally
    Node.Free;
  end;
end;

function TJSONTextParser.ParseObject: TJSONValue;
var
  Node, Value: TJSONValue;
  Key: string;
  KeyPos: Integer;
  Duplicate: Boolean;
begin
  EnterContainer;
  Node := NewJSONObject;
  try
    Inc(FPos); // opening brace
    SkipWhitespace;
    if (FPos <= FLen) and (FText[FPos] = '}') then
      Inc(FPos)
    else
      while True do
      begin
        SkipWhitespace;
        if (FPos > FLen) or (FText[FPos] <> '"') then
          Fail('member name expected');
        KeyPos := FPos;
        Key := ParseString;
        SkipWhitespace;
        if (FPos > FLen) or (FText[FPos] <> ':') then
          Fail('":" expected');
        Inc(FPos);
        Duplicate := Node.FindMember(Key) <> nil;
        if Duplicate and (FOptions.DuplicateKeys = dkError) then
          FailAt(KeyPos, 'duplicate member name "' + Key + '"');
        Value := ParseValue;
        if Duplicate and (FOptions.DuplicateKeys = dkFirstWins) then
          Value.Free
        else
          Node.SetMember(Key, Value);
        SkipWhitespace;
        if FPos > FLen then
          Fail('unterminated object');
        if FText[FPos] = ',' then
        begin
          Inc(FPos);
          if FOptions.AllowTrailingCommas then
          begin
            SkipWhitespace;
            if (FPos <= FLen) and (FText[FPos] = '}') then
            begin
              Inc(FPos);
              Break;
            end;
          end;
        end
        else if FText[FPos] = '}' then
        begin
          Inc(FPos);
          Break;
        end
        else
          Fail('"," or "}" expected');
      end;
    Dec(FDepth);
    Result := Node;
    Node := nil;
  finally
    Node.Free;
  end;
end;

function TJSONTextParser.ParseValue: TJSONValue;
begin
  SkipWhitespace;
  if FPos > FLen then
    Fail('value expected');
  case FText[FPos] of
    '{': Result := ParseObject;
    '[': Result := ParseArray;
    '"': Result := NewJSONString(ParseString);
    '-', '0'..'9': Result := ParseNumber;
  else
    if MatchWord('true') then
      Result := NewJSONBool(True)
    else if MatchWord('false') then
      Result := NewJSONBool(False)
    else if MatchWord('null') then
      Result := NewJSONNull
    else
    begin
      Result := nil;
      Fail('unexpected character');
    end;
  end;
end;

function TJSONTextParser.ParseDocument: TJSONValue;
var
  Node: TJSONValue;
begin
  Node := ParseValue;
  try
    SkipWhitespace;
    if FPos <= FLen then
      Fail('unexpected trailing characters');
    Result := Node;
    Node := nil;
  finally
    Node.Free;
  end;
end;

function ParseJSON(const AText: string; const AOptions: TJSONParseOptions): TJSONValue; overload;
var
  P: TJSONTextParser;
begin
  P := TJSONTextParser.Create(AText, AOptions);
  try
    Result := P.ParseDocument;
  finally
    P.Free;
  end;
end;

function ParseJSON(const AText: string): TJSONValue; overload;
begin
  Result := ParseJSON(AText, DefaultJSONParseOptions);
end;

{ ======================= writer ======================= }

type
  TIndexArray = array of Integer;
  TKeyUnitsArray = array of TCodePointArray;

{ the code point array of S as UTF-16 code units (supplementary characters
  become surrogate pairs) }
function ToUtf16Units(const S: string): TCodePointArray;
var
  CPs: TCodePointArray;
  I, N: Integer;
  CP: Cardinal;
begin
  CPs := StringToCodePoints(S);
  SetLength(Result, Length(CPs) * 2);
  N := 0;
  for I := 0 to Length(CPs) - 1 do
  begin
    CP := CPs[I];
    if CP >= $10000 then
    begin
      Dec(CP, $10000);
      Result[N] := $D800 + (CP shr 10);
      Result[N + 1] := $DC00 + (CP and $3FF);
      Inc(N, 2);
    end
    else
    begin
      Result[N] := CP;
      Inc(N);
    end;
  end;
  SetLength(Result, N);
end;

function CompareUnits(const A, B: TCodePointArray): Integer;
var
  I, N: Integer;
begin
  N := Length(A);
  if Length(B) < N then
    N := Length(B);
  for I := 0 to N - 1 do
    if A[I] <> B[I] then
    begin
      if A[I] < B[I] then
        Result := -1
      else
        Result := 1;
      Exit;
    end;
  if Length(A) < Length(B) then
    Result := -1
  else if Length(A) > Length(B) then
    Result := 1
  else
    Result := 0;
end;

function MinInt(A, B: Integer): Integer;
begin
  if A < B then Result := A else Result := B;
end;

{ stable bottom-up merge sort of the member indexes by key }
procedure SortIndexes(var AIdx: TIndexArray; const AKeys: TKeyUnitsArray);
var
  Tmp: TIndexArray;
  N, Width, I, L, M, R, A, B, K: Integer;
begin
  N := Length(AIdx);
  SetLength(Tmp, N);
  Width := 1;
  while Width < N do
  begin
    I := 0;
    while I < N do
    begin
      L := I;
      M := MinInt(I + Width, N);
      R := MinInt(I + 2 * Width, N);
      A := L;
      B := M;
      K := L;
      while (A < M) and (B < R) do
      begin
        if CompareUnits(AKeys[AIdx[B]], AKeys[AIdx[A]]) < 0 then
        begin
          Tmp[K] := AIdx[B];
          Inc(B);
        end
        else
        begin
          Tmp[K] := AIdx[A];
          Inc(A);
        end;
        Inc(K);
      end;
      while A < M do
      begin
        Tmp[K] := AIdx[A];
        Inc(A);
        Inc(K);
      end;
      while B < R do
      begin
        Tmp[K] := AIdx[B];
        Inc(B);
        Inc(K);
      end;
      I := I + 2 * Width;
    end;
    for K := 0 to N - 1 do
      AIdx[K] := Tmp[K];
    Width := Width * 2;
  end;
end;

{ ECMAScript Number::toString (RFC 8785 section 3.2.2.3) }
function CanonicalNumberText(ANumber: Double): string;
var
  D, Back: Double;
  P, E, K, N, I, EPos: Integer;
  F: Double;
  S, Mantissa, ExpPart, Digits, Body: string;
  FS: TFormatSettings;
  Neg: Boolean;
begin
  if ANumber = 0 then
  begin
    Result := '0';
    Exit;
  end;
  Neg := ANumber < 0;
  D := Abs(ANumber);
  FS := InvariantFormatSettings;
  S := '';
  for P := 1 to 17 do
  begin
    S := FloatToStrF(D, ffExponent, P, 0, FS);
    if (P = 17) or (TryJSONTextToDouble(S, Back) and (Back = D)) then
      Break;
  end;
  EPos := Pos('E', UpperCase(S));
  if EPos = 0 then
  begin
    // No exponent found, treat as E+0
    Mantissa := S;
    E := 0;
  end
  else
  begin
    Mantissa := Copy(S, 1, EPos - 1);
    ExpPart := Copy(S, EPos + 1, Length(S));
    if (ExpPart <> '') and (ExpPart[1] = '+') then
      Delete(ExpPart, 1, 1);
    E := StrToInt(ExpPart);
  end;
  Digits := '';
  for I := 1 to Length(Mantissa) do
    if (Mantissa[I] >= '0') and (Mantissa[I] <= '9') then
      Digits := Digits + Mantissa[I];
  while (Length(Digits) > 1) and (Digits[Length(Digits)] = '0') do
    Delete(Digits, Length(Digits), 1);
  K := Length(Digits);
  N := E + 1;
  if (K <= N) and (N <= 21) then
    Body := Digits + StringOfChar('0', N - K)
  else if (0 < N) and (N <= 21) then
    Body := Copy(Digits, 1, N) + '.' + Copy(Digits, N + 1, K - N)
  else if (-6 < N) and (N <= 0) then
    Body := '0.' + StringOfChar('0', -N) + Digits
  else
  begin
    if N - 1 < 0 then
      ExpPart := '-' + IntToStr(1 - N)
    else
      ExpPart := '+' + IntToStr(N - 1);
    if K = 1 then
      Body := Digits + 'e' + ExpPart
    else
      Body := Copy(Digits, 1, 1) + '.' + Copy(Digits, 2, K - 1) + 'e' + ExpPart;
  end;
  if Neg then
    Result := '-' + Body
  else
    Result := Body;
end;

type
  TJSONWriter = class
  private
    FOpts: TJSONWriteOptions;
    FBuf: string;
    FLen: Integer;
    procedure Append(const S: string);
    procedure AppendChar(C: Char);
    procedure AppendUnicode(ACodeUnit: Cardinal);
    procedure AppendEscaped(C: Char);
    procedure NewLine(ALevel: Integer);
    function Pretty: Boolean;
    function Sorted: Boolean;
    procedure WriteNumber(AValue: TJSONValue);
    procedure WriteArray(AValue: TJSONValue; ALevel: Integer);
    procedure WriteObject(AValue: TJSONValue; ALevel: Integer);
  public
    constructor Create(const AOpts: TJSONWriteOptions);
    procedure WriteString(const S: string);
    procedure WriteValue(AValue: TJSONValue; ALevel: Integer);
    function Text: string;
  end;

constructor TJSONWriter.Create(const AOpts: TJSONWriteOptions);
begin
  inherited Create;
  FOpts := AOpts;
end;

function TJSONWriter.Text: string;
begin
  Result := Copy(FBuf, 1, FLen);
end;

procedure TJSONWriter.Append(const S: string);
var
  N: Integer;
begin
  N := Length(S);
  if N = 0 then
    Exit;
  if FLen + N > Length(FBuf) then
    SetLength(FBuf, (FLen + N) * 2 + 64);
  Move(S[1], FBuf[FLen + 1], N * SizeOf(Char));
  Inc(FLen, N);
end;

procedure TJSONWriter.AppendChar(C: Char);
begin
  if FLen >= Length(FBuf) then
    SetLength(FBuf, FLen * 2 + 64);
  Inc(FLen);
  FBuf[FLen] := C;
end;

procedure TJSONWriter.AppendUnicode(ACodeUnit: Cardinal);
begin
  Append('\u' + LowerCase(IntToHex(ACodeUnit, 4)));
end;

procedure TJSONWriter.AppendEscaped(C: Char);
begin
  case C of
    '"': Append('\"');
    '\': Append('\\');
    #8: Append('\b');
    #9: Append('\t');
    #10: Append('\n');
    #12: Append('\f');
    #13: Append('\r');
  else
    if Ord(C) < $20 then
      AppendUnicode(Cardinal(Ord(C)))
    else
      AppendChar(C);
  end;
end;

procedure TJSONWriter.NewLine(ALevel: Integer);
begin
  AppendChar(#10);
  Append(StringOfChar(' ', FOpts.Indent * ALevel));
end;

function TJSONWriter.Pretty: Boolean;
begin
  Result := (FOpts.Indent > 0) and not FOpts.Canonical;
end;

function TJSONWriter.Sorted: Boolean;
begin
  Result := FOpts.SortKeys or FOpts.Canonical;
end;

procedure TJSONWriter.WriteString(const S: string);
var
  I, RunStart: Integer;
  C: Char;
  NonAscii: Boolean;
  CPs: TCodePointArray;
  CP: Cardinal;
begin
  AppendChar('"');
  NonAscii := False;
  if FOpts.EscapeNonAscii and not FOpts.Canonical then
    for I := 1 to Length(S) do
      if Ord(S[I]) >= 128 then
      begin
        NonAscii := True;
        Break;
      end;
  if not NonAscii then
  begin
    RunStart := 1;
    for I := 1 to Length(S) do
    begin
      C := S[I];
      if (C = '"') or (C = '\') or (Ord(C) < $20) then
      begin
        Append(Copy(S, RunStart, I - RunStart));
        RunStart := I + 1;
        AppendEscaped(C);
      end;
    end;
    Append(Copy(S, RunStart, Length(S) - RunStart + 1));
  end
  else
  begin
    CPs := StringToCodePoints(S);
    for I := 0 to Length(CPs) - 1 do
    begin
      CP := CPs[I];
      if CP < 128 then
        AppendEscaped(Char(CP))
      else if CP >= $10000 then
      begin
        Dec(CP, $10000);
        AppendUnicode($D800 + (CP shr 10));
        AppendUnicode($DC00 + (CP and $3FF));
      end
      else
        AppendUnicode(CP);
    end;
  end;
  AppendChar('"');
end;

procedure TJSONWriter.WriteNumber(AValue: TJSONValue);
begin
  if FOpts.Canonical then
    Append(CanonicalNumberText(AValue.NumberValue))
  else if FOpts.OriginalNumbers then
    Append(AValue.NumberText)
  else if AValue.IsExactInt64 then
    Append(IntToStr(AValue.AsInteger))
  else
    Append(DoubleToJSONText(AValue.NumberValue));
end;

procedure TJSONWriter.WriteArray(AValue: TJSONValue; ALevel: Integer);
var
  I: Integer;
begin
  if AValue.Count = 0 then
  begin
    Append('[]');
    Exit;
  end;
  AppendChar('[');
  for I := 0 to AValue.Count - 1 do
  begin
    if I > 0 then
      AppendChar(',');
    if Pretty then
      NewLine(ALevel + 1);
    WriteValue(AValue[I], ALevel + 1);
  end;
  if Pretty then
    NewLine(ALevel);
  AppendChar(']');
end;

procedure TJSONWriter.WriteObject(AValue: TJSONValue; ALevel: Integer);
var
  I, Idx: Integer;
  Order: TIndexArray;
  Keys: TKeyUnitsArray;
begin
  if AValue.Count = 0 then
  begin
    Append('{}');
    Exit;
  end;
  SetLength(Order, AValue.Count);
  for I := 0 to AValue.Count - 1 do
    Order[I] := I;
  if Sorted then
  begin
    SetLength(Keys, AValue.Count);
    for I := 0 to AValue.Count - 1 do
      Keys[I] := ToUtf16Units(AValue.Names[I]);
    SortIndexes(Order, Keys);
  end;
  AppendChar('{');
  for I := 0 to AValue.Count - 1 do
  begin
    Idx := Order[I];
    if I > 0 then
      AppendChar(',');
    if Pretty then
      NewLine(ALevel + 1);
    WriteString(AValue.Names[Idx]);
    AppendChar(':');
    if Pretty then
      AppendChar(' ');
    WriteValue(AValue[Idx], ALevel + 1);
  end;
  if Pretty then
    NewLine(ALevel);
  AppendChar('}');
end;

procedure TJSONWriter.WriteValue(AValue: TJSONValue; ALevel: Integer);
begin
  case AValue.Kind of
    jkNull: Append('null');
    jkBoolean:
      if AValue.BoolValue then Append('true') else Append('false');
    jkNumber: WriteNumber(AValue);
    jkString: WriteString(AValue.StringValue);
    jkArray: WriteArray(AValue, ALevel);
    jkObject: WriteObject(AValue, ALevel);
  end;
end;

function JSONToText(AValue: TJSONValue; const AOptions: TJSONWriteOptions): string; overload;
var
  W: TJSONWriter;
begin
  Result := '';
  if AValue = nil then
    Exit;
  W := TJSONWriter.Create(AOptions);
  try
    W.WriteValue(AValue, 0);
    Result := W.Text;
  finally
    W.Free;
  end;
end;

function JSONToText(AValue: TJSONValue): string; overload;
begin
  Result := JSONToText(AValue, DefaultJSONWriteOptions);
end;

function JSONToTextPretty(AValue: TJSONValue; Ident: Integer): string;
var
  O: TJSONWriteOptions;
begin
  O := DefaultJSONWriteOptions;
  if Ident > 0 then
    O.Indent := Ident;
  Result := JSONToText(AValue, O);
end;

function JSONCanonicalText(AValue: TJSONValue): string;
var
  O: TJSONWriteOptions;
begin
  O := DefaultJSONWriteOptions;
  O.Canonical := True;
  Result := JSONToText(AValue, O);
end;

function JSONQuoteString(const S: string): string;
var
  W: TJSONWriter;
begin
  W := TJSONWriter.Create(DefaultJSONWriteOptions);
  try
    W.WriteString(S);
    Result := W.Text;
  finally
    W.Free;
  end;
end;

{ ======================= equality ======================= }

{ Brings two decimals to the same scale; False when that overflows }
function AlignScales(var AUnscaledA: Int64; var AScaleA: Integer;
  var AUnscaledB: Int64; var AScaleB: Integer): Boolean;
begin
  Result := True;
  while AScaleA < AScaleB do
  begin
    if (AUnscaledA > High(Int64) div 10) or (AUnscaledA < Low(Int64) div 10) then
    begin
      Result := False;
      Exit;
    end;
    AUnscaledA := AUnscaledA * 10;
    Inc(AScaleA);
  end;
  while AScaleB < AScaleA do
  begin
    if (AUnscaledB > High(Int64) div 10) or (AUnscaledB < Low(Int64) div 10) then
    begin
      Result := False;
      Exit;
    end;
    AUnscaledB := AUnscaledB * 10;
    Inc(AScaleB);
  end;
end;

function JSONNumberCompare(A, B: TJSONValue): Integer;
var
  UA, UB: Int64;
  SA, SB: Integer;
begin
  if (A.Kind <> jkNumber) or (B.Kind <> jkNumber) then
  begin
    Result := 0;
    Exit;
  end;
  if A.TryGetDecimal(UA, SA) and B.TryGetDecimal(UB, SB)
    and AlignScales(UA, SA, UB, SB) then
  begin
    if UA < UB then
      Result := -1
    else if UA > UB then
      Result := 1
    else
      Result := 0;
  end
  else if A.NumberValue < B.NumberValue then
    Result := -1
  else if A.NumberValue > B.NumberValue then
    Result := 1
  else
    Result := 0;
end;

function JSONEquals(A, B: TJSONValue): Boolean;
var
  I: Integer;
  Other: TJSONValue;
begin
  Result := False;
  if (A = nil) or (B = nil) then
    Exit;
  if A.Kind <> B.Kind then
    Exit;
  case A.Kind of
    jkNull: Result := True;
    jkBoolean: Result := A.BoolValue = B.BoolValue;
    jkNumber: Result := JSONNumberCompare(A, B) = 0;
    jkString: Result := A.StringValue = B.StringValue;
    jkArray:
      begin
        if A.Count <> B.Count then
          Exit;
        for I := 0 to A.Count - 1 do
          if not JSONEquals(A[I], B[I]) then
            Exit;
        Result := True;
      end;
    jkObject:
      begin
        if A.Count <> B.Count then
          Exit;
        for I := 0 to A.Count - 1 do
        begin
          Other := B.FindMember(A.Names[I]);
          if (Other = nil) or not JSONEquals(A[I], Other) then
            Exit;
        end;
        Result := True;
      end;
  end;
end;

{ ======================= builder ======================= }

constructor TJSONBuilder.Create;
begin
  inherited Create;
  FStack := TList.Create;
end;

destructor TJSONBuilder.Destroy;
begin
  FRoot.Free;
  FStack.Free;
  inherited Destroy;
end;

function TJSONBuilder.GetDepth: Integer;
begin
  Result := FStack.Count;
end;

function TJSONBuilder.Top: TJSONValue;
begin
  if FStack.Count = 0 then
    Result := nil
  else
    Result := TJSONValue(FStack[FStack.Count - 1]);
end;

procedure TJSONBuilder.Attach(AValue: TJSONValue);
var
  T: TJSONValue;
begin
  T := Top;
  if T = nil then
  begin
    if FRoot <> nil then
    begin
      AValue.Free;
      raise EJSONBuilderError.Create('The document already has a root value');
    end;
    FRoot := AValue;
  end
  else if T.Kind = jkArray then
    T.AddItem(AValue)
  else
  begin
    AValue.Free;
    raise EJSONBuilderError.Create(
      'Inside an object use Put... / Begin...(Name) instead of Add...');
  end;
end;

procedure TJSONBuilder.AttachNamed(const AName: string; AValue: TJSONValue);
var
  T: TJSONValue;
begin
  T := Top;
  if (T = nil) or (T.Kind <> jkObject) then
  begin
    AValue.Free;
    raise EJSONBuilderError.Create(
      'Put... and Begin...(Name) can only be used inside an object');
  end;
  T.SetMember(AName, AValue);
end;

procedure TJSONBuilder.Push(AValue: TJSONValue);
begin
  FStack.Add(Pointer(AValue));
end;

function TJSONBuilder.AddString(const AValue: string): TJSONBuilder;
begin
  Attach(NewJSONString(AValue));
  Result := Self;
end;

function TJSONBuilder.AddInt(AValue: Int64): TJSONBuilder;
begin
  Attach(NewJSONInt64(AValue));
  Result := Self;
end;

function TJSONBuilder.AddNumber(AValue: Double): TJSONBuilder;
begin
  Attach(NewJSONNumber(AValue));
  Result := Self;
end;

function TJSONBuilder.AddNumberText(const AText: string): TJSONBuilder;
begin
  Attach(NewJSONNumberText(AText));
  Result := Self;
end;

function TJSONBuilder.AddDecimal(AUnscaled: Int64; AScale: Integer): TJSONBuilder;
begin
  Attach(NewJSONDecimal(AUnscaled, AScale));
  Result := Self;
end;

function TJSONBuilder.AddBool(AValue: Boolean): TJSONBuilder;
begin
  Attach(NewJSONBool(AValue));
  Result := Self;
end;

function TJSONBuilder.AddNull: TJSONBuilder;
begin
  Attach(NewJSONNull);
  Result := Self;
end;

function TJSONBuilder.AddValue(AValue: TJSONValue): TJSONBuilder;
begin
  if AValue = nil then
    raise EJSONBuilderError.Create('AddValue requires a value');
  Attach(AValue);
  Result := Self;
end;

function TJSONBuilder.BeginObject: TJSONBuilder;
var
  V: TJSONValue;
begin
  V := NewJSONObject;
  Attach(V);
  Push(V);
  Result := Self;
end;

function TJSONBuilder.BeginArray: TJSONBuilder;
var
  V: TJSONValue;
begin
  V := NewJSONArray;
  Attach(V);
  Push(V);
  Result := Self;
end;

function TJSONBuilder.PutString(const AName, AValue: string): TJSONBuilder;
begin
  AttachNamed(AName, NewJSONString(AValue));
  Result := Self;
end;

function TJSONBuilder.PutInt(const AName: string; AValue: Int64): TJSONBuilder;
begin
  AttachNamed(AName, NewJSONInt64(AValue));
  Result := Self;
end;

function TJSONBuilder.PutNumber(const AName: string; AValue: Double): TJSONBuilder;
begin
  AttachNamed(AName, NewJSONNumber(AValue));
  Result := Self;
end;

function TJSONBuilder.PutNumberText(const AName, AText: string): TJSONBuilder;
begin
  AttachNamed(AName, NewJSONNumberText(AText));
  Result := Self;
end;

function TJSONBuilder.PutDecimal(const AName: string; AUnscaled: Int64;
  AScale: Integer): TJSONBuilder;
begin
  AttachNamed(AName, NewJSONDecimal(AUnscaled, AScale));
  Result := Self;
end;

function TJSONBuilder.PutBool(const AName: string; AValue: Boolean): TJSONBuilder;
begin
  AttachNamed(AName, NewJSONBool(AValue));
  Result := Self;
end;

function TJSONBuilder.PutNull(const AName: string): TJSONBuilder;
begin
  AttachNamed(AName, NewJSONNull);
  Result := Self;
end;

function TJSONBuilder.PutValue(const AName: string; AValue: TJSONValue): TJSONBuilder;
begin
  if AValue = nil then
    raise EJSONBuilderError.Create('PutValue requires a value');
  AttachNamed(AName, AValue);
  Result := Self;
end;

function TJSONBuilder.BeginObject(const AName: string): TJSONBuilder;
var
  V: TJSONValue;
begin
  V := NewJSONObject;
  AttachNamed(AName, V);
  Push(V);
  Result := Self;
end;

function TJSONBuilder.BeginArray(const AName: string): TJSONBuilder;
var
  V: TJSONValue;
begin
  V := NewJSONArray;
  AttachNamed(AName, V);
  Push(V);
  Result := Self;
end;

function TJSONBuilder.EndObject: TJSONBuilder;
begin
  if (Top = nil) or (Top.Kind <> jkObject) then
    raise EJSONBuilderError.Create('EndObject without a matching open object');
  FStack.Delete(FStack.Count - 1);
  Result := Self;
end;

function TJSONBuilder.EndArray: TJSONBuilder;
begin
  if (Top = nil) or (Top.Kind <> jkArray) then
    raise EJSONBuilderError.Create('EndArray without a matching open array');
  FStack.Delete(FStack.Count - 1);
  Result := Self;
end;

function TJSONBuilder.Build: TJSONValue;
begin
  if FStack.Count > 0 then
    raise EJSONBuilderError.CreateFmt('Build called while %d container(s) are still open',
      [FStack.Count]);
  if FRoot = nil then
    raise EJSONBuilderError.Create('Nothing has been built');
  Result := FRoot;
  FRoot := nil;
end;

end.
