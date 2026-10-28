{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit JSONPathJSON;

{ Minimal JSON document model + strict RFC 8259 parser/serializer.
  It exists so the JSONPath units need nothing beyond SysUtils and Classes. }

interface

uses
  SysUtils, Classes, JSONPathCommon;

type
  EJSONPathJSONError = class(Exception)
  private
    FPosition: Integer;
  public
    constructor CreateAt(const AMessage: string; APosition: Integer);
    property Position: Integer read FPosition;
  end;

  TJSONKind = (jkNull, jkBoolean, jkNumber, jkString, jkArray, jkObject);

  TJSONValue = class
  private
    FKind: TJSONKind;
    FBool: Boolean;
    FNumber: Double;
    FText: string;
    FItems: TOwnedList;
    FNames: array of string;
    FNameCount: Integer;
    function GetCount: Integer;
    function GetItem(Index: Integer): TJSONValue;
    function GetName(Index: Integer): string;
    function IndexOfName(const AName: string): Integer;
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
    property NumberValue: Double read FNumber write FNumber;
    property StringValue: string read FText write FText;
    { Element count for arrays, member count for objects, 0 otherwise }
    property Count: Integer read GetCount;
    { Element (arrays) or member value (objects) }
    property Items[Index: Integer]: TJSONValue read GetItem; default;
    { Member name (objects only) }
    property Names[Index: Integer]: string read GetName;
  end;

function NewJSONNull: TJSONValue;
function NewJSONBool(AValue: Boolean): TJSONValue;
function NewJSONNumber(AValue: Double): TJSONValue;
function NewJSONString(const AValue: string): TJSONValue;
function NewJSONArray: TJSONValue;
function NewJSONObject: TJSONValue;

{ Parses JSON text. The caller owns the result. Raises EJSONPathJSONError. }
function ParseJSON(const AText: string): TJSONValue;
{ Compact serialization }
function JSONToText(AValue: TJSONValue): string;
(* Pretty-printed serialization. Ident is the number of spaces per nesting
  level; members and elements go on their own lines (LF line breaks), empty
  arrays/objects stay as [] and {}. Ident <= 0 falls back to compact output. *)
function JSONToTextPretty(AValue: TJSONValue; Ident: Integer): string;
function JSONQuoteString(const S: string): string;
{ Deep equality as defined by RFC 9535 section 2.3.5.2.2 }
function JSONEquals(A, B: TJSONValue): Boolean;

implementation

const
  MAX_JSON_DEPTH = 512;

{ EJSONPathJSONError }

constructor EJSONPathJSONError.CreateAt(const AMessage: string; APosition: Integer);
begin
  inherited Create(Format('JSON error at position %d: %s', [APosition, AMessage]));
  FPosition := APosition;
end;

{ TJSONValue }

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

{ Factories }

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
  Result.NumberValue := AValue;
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

{ Parser }

type
  TJSONTextParser = class
  private
    FText: string;
    FPos: Integer;
    FLen: Integer;
    FDepth: Integer;
    procedure Fail(const AMessage: string);
    procedure SkipWhitespace;
    function ParseValue: TJSONValue;
    function ParseObject: TJSONValue;
    function ParseArray: TJSONValue;
    function ParseString: string;
    function ParseNumber: TJSONValue;
    function ParseHex4: Cardinal;
    function MatchWord(const AWord: string): Boolean;
  public
    constructor Create(const AText: string);
    function ParseDocument: TJSONValue;
  end;

constructor TJSONTextParser.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FLen := Length(AText);
  FPos := 1;
end;

procedure TJSONTextParser.Fail(const AMessage: string);
begin
  raise EJSONPathJSONError.CreateAt(AMessage, FPos - 1);
end;

procedure TJSONTextParser.SkipWhitespace;
begin
  while (FPos <= FLen) and
    ((FText[FPos] = ' ') or (FText[FPos] = #9) or (FText[FPos] = #10) or (FText[FPos] = #13)) do
    Inc(FPos);
end;

function TJSONTextParser.MatchWord(const AWord: string): Boolean;
begin
  Result := Copy(FText, FPos, Length(AWord)) = AWord;
  if Result then
    Inc(FPos, Length(AWord));
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
  D: Double;
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
  if not TryJSONTextToDouble(Copy(FText, Start, FPos - Start), D) then
  begin
    FPos := Start;
    Fail('invalid number');
  end;
  Result := NewJSONNumber(D);
end;

function TJSONTextParser.ParseArray: TJSONValue;
var
  Node: TJSONValue;
begin
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
          Inc(FPos)
        else if FText[FPos] = ']' then
        begin
          Inc(FPos);
          Break;
        end
        else
          Fail('"," or "]" expected');
      end;
    Result := Node;
    Node := nil;
  finally
    Node.Free;
  end;
end;

function TJSONTextParser.ParseObject: TJSONValue;
var
  Node: TJSONValue;
  Key: string;
begin
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
        Key := ParseString;
        SkipWhitespace;
        if (FPos > FLen) or (FText[FPos] <> ':') then
          Fail('":" expected');
        Inc(FPos);
        Node.SetMember(Key, ParseValue);
        SkipWhitespace;
        if FPos > FLen then
          Fail('unterminated object');
        if FText[FPos] = ',' then
          Inc(FPos)
        else if FText[FPos] = '}' then
        begin
          Inc(FPos);
          Break;
        end
        else
          Fail('"," or "}" expected');
      end;
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
  Inc(FDepth);
  try
    if FDepth > MAX_JSON_DEPTH then
      Fail('maximum nesting depth exceeded');
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
  finally
    Dec(FDepth);
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

function ParseJSON(const AText: string): TJSONValue;
var
  P: TJSONTextParser;
begin
  P := TJSONTextParser.Create(AText);
  try
    Result := P.ParseDocument;
  finally
    P.Free;
  end;
end;

{ Serializer }

function JSONQuoteString(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '"';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if Ord(C) < $20 then
        Result := Result + '\u' + LowerCase(IntToHex(Ord(C), 4))
      else
        Result := Result + C;
    end;
  end;
  Result := Result + '"';
end;

function JSONToText(AValue: TJSONValue): string;
var
  I: Integer;
begin
  if AValue = nil then
  begin
    Result := '';
    Exit;
  end;
  case AValue.Kind of
    jkNull: Result := 'null';
    jkBoolean:
      if AValue.BoolValue then Result := 'true' else Result := 'false';
    jkNumber: Result := DoubleToJSONText(AValue.NumberValue);
    jkString: Result := JSONQuoteString(AValue.StringValue);
    jkArray:
      begin
        Result := '[';
        for I := 0 to AValue.Count - 1 do
        begin
          if I > 0 then
            Result := Result + ',';
          Result := Result + JSONToText(AValue[I]);
        end;
        Result := Result + ']';
      end;
    jkObject:
      begin
        Result := '{';
        for I := 0 to AValue.Count - 1 do
        begin
          if I > 0 then
            Result := Result + ',';
          Result := Result + JSONQuoteString(AValue.Names[I]) + ':' + JSONToText(AValue[I]);
        end;
        Result := Result + '}';
      end;
  else
    Result := '';
  end;
end;

procedure PrettyAppend(AValue: TJSONValue; Ident, Level: Integer; var Dest: string);
var
  I: Integer;
  Pad, PadInner: string;
begin
  case AValue.Kind of
    jkArray:
      if AValue.Count = 0 then
        Dest := Dest + '[]'
      else
      begin
        Pad := StringOfChar(' ', Ident * Level);
        PadInner := StringOfChar(' ', Ident * (Level + 1));
        Dest := Dest + '[' + #10;
        for I := 0 to AValue.Count - 1 do
        begin
          Dest := Dest + PadInner;
          PrettyAppend(AValue[I], Ident, Level + 1, Dest);
          if I < AValue.Count - 1 then
            Dest := Dest + ',';
          Dest := Dest + #10;
        end;
        Dest := Dest + Pad + ']';
      end;
    jkObject:
      if AValue.Count = 0 then
        Dest := Dest + '{}'
      else
      begin
        Pad := StringOfChar(' ', Ident * Level);
        PadInner := StringOfChar(' ', Ident * (Level + 1));
        Dest := Dest + '{' + #10;
        for I := 0 to AValue.Count - 1 do
        begin
          Dest := Dest + PadInner + JSONQuoteString(AValue.Names[I]) + ': ';
          PrettyAppend(AValue[I], Ident, Level + 1, Dest);
          if I < AValue.Count - 1 then
            Dest := Dest + ',';
          Dest := Dest + #10;
        end;
        Dest := Dest + Pad + '}';
      end;
  else
    Dest := Dest + JSONToText(AValue);
  end;
end;

function JSONToTextPretty(AValue: TJSONValue; Ident: Integer): string;
begin
  Result := '';
  if AValue = nil then
    Exit;
  if Ident <= 0 then
    Result := JSONToText(AValue)
  else
    PrettyAppend(AValue, Ident, 0, Result);
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
    jkNumber: Result := A.NumberValue = B.NumberValue;
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

end.
