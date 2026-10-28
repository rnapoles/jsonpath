{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit JSONPathCommon;

{ Shared, dependency-free helpers for the JSONPath units.

  String model: on Free Pascal (Delphi mode) `string` holds UTF-8 bytes, on
  Delphi it holds UTF-16 code units. All code point helpers below hide that
  difference so the rest of the code never has to care. }

interface

uses
  SysUtils, Classes;

const
  { RFC 9535: integers must stay within the I-JSON exact range +-(2^53)-1 }
  JSONPATH_MAX_INT: Int64 = 9007199254740991;

type
  TCodePointArray = array of Cardinal;

  { Owns the objects added to it. Deliberately not derived from TList so that
    behaviour does not depend on TList.Notify differences between compilers. }
  TOwnedList = class
  private
    FItems: TList;
    function GetCount: Integer;
    function GetItem(Index: Integer): TObject;
  public
    constructor Create;
    destructor Destroy; override;
    function Add(AObject: TObject): Integer;
    procedure Replace(Index: Integer; AObject: TObject);
    procedure Clear;
    property Count: Integer read GetCount;
    property Items[Index: Integer]: TObject read GetItem; default;
  end;

procedure AppendCodePoint(var S: string; CodePoint: Cardinal);
function StringToCodePoints(const S: string): TCodePointArray;
function CodePointLength(const S: string): Integer;
function HexDigitValue(C: Char): Integer;
function InvariantFormatSettings: TFormatSettings;
function DoubleToJSONText(Value: Double): string;
function TryJSONTextToDouble(const S: string; out Value: Double): Boolean;
function MinInt64(A, B: Int64): Int64;
function MaxInt64(A, B: Int64): Int64;

implementation

{ TOwnedList }

constructor TOwnedList.Create;
begin
  inherited Create;
  FItems := TList.Create;
end;

destructor TOwnedList.Destroy;
begin
  try
    Clear;
  finally
    FItems.Free;
    inherited Destroy;
  end;
end;

function TOwnedList.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TOwnedList.GetItem(Index: Integer): TObject;
begin
  Result := TObject(FItems[Index]);
end;

function TOwnedList.Add(AObject: TObject): Integer;
begin
  Result := FItems.Add(Pointer(AObject));
end;

procedure TOwnedList.Replace(Index: Integer; AObject: TObject);
var
  Old: TObject;
begin
  Old := TObject(FItems[Index]);
  FItems[Index] := Pointer(AObject);
  Old.Free;
end;

procedure TOwnedList.Clear;
var
  I: Integer;
begin
  for I := FItems.Count - 1 downto 0 do
    TObject(FItems[I]).Free;
  FItems.Clear;
end;

{ Code point helpers }

procedure AppendCodePoint(var S: string; CodePoint: Cardinal);
begin
{$IFDEF FPC}
  if CodePoint < $80 then
    S := S + Chr(Byte(CodePoint))
  else if CodePoint < $800 then
    S := S + Chr(Byte($C0 or (CodePoint shr 6)))
           + Chr(Byte($80 or (CodePoint and $3F)))
  else if CodePoint < $10000 then
    S := S + Chr(Byte($E0 or (CodePoint shr 12)))
           + Chr(Byte($80 or ((CodePoint shr 6) and $3F)))
           + Chr(Byte($80 or (CodePoint and $3F)))
  else
    S := S + Chr(Byte($F0 or (CodePoint shr 18)))
           + Chr(Byte($80 or ((CodePoint shr 12) and $3F)))
           + Chr(Byte($80 or ((CodePoint shr 6) and $3F)))
           + Chr(Byte($80 or (CodePoint and $3F)));
{$ELSE}
  if CodePoint < $10000 then
    S := S + Char(Word(CodePoint))
  else
  begin
    Dec(CodePoint, $10000);
    S := S + Char(Word($D800 + (CodePoint shr 10)))
           + Char(Word($DC00 + (CodePoint and $3FF)));
  end;
{$ENDIF}
end;

function StringToCodePoints(const S: string): TCodePointArray;
var
  I, N, Cnt: Integer;
  C: Cardinal;
begin
  N := Length(S);
  SetLength(Result, N);
  Cnt := 0;
  I := 1;
  while I <= N do
  begin
    C := Cardinal(Ord(S[I]));
{$IFDEF FPC}
    if (C >= $F0) and (I + 3 <= N) then
    begin
      C := ((C and $07) shl 18)
        or ((Cardinal(Ord(S[I + 1])) and $3F) shl 12)
        or ((Cardinal(Ord(S[I + 2])) and $3F) shl 6)
        or (Cardinal(Ord(S[I + 3])) and $3F);
      Inc(I, 4);
    end
    else if (C >= $E0) and (C < $F0) and (I + 2 <= N) then
    begin
      C := ((C and $0F) shl 12)
        or ((Cardinal(Ord(S[I + 1])) and $3F) shl 6)
        or (Cardinal(Ord(S[I + 2])) and $3F);
      Inc(I, 3);
    end
    else if (C >= $C0) and (C < $E0) and (I + 1 <= N) then
    begin
      C := ((C and $1F) shl 6) or (Cardinal(Ord(S[I + 1])) and $3F);
      Inc(I, 2);
    end
    else
      Inc(I);
{$ELSE}
    if (C >= $D800) and (C <= $DBFF) and (I < N)
      and (Cardinal(Ord(S[I + 1])) >= $DC00)
      and (Cardinal(Ord(S[I + 1])) <= $DFFF) then
    begin
      C := $10000 + ((C - $D800) shl 10) + (Cardinal(Ord(S[I + 1])) - $DC00);
      Inc(I, 2);
    end
    else
      Inc(I);
{$ENDIF}
    Result[Cnt] := C;
    Inc(Cnt);
  end;
  SetLength(Result, Cnt);
end;

function CodePointLength(const S: string): Integer;
begin
  Result := Length(StringToCodePoints(S));
end;

function HexDigitValue(C: Char): Integer;
begin
  if (C >= '0') and (C <= '9') then
    Result := Ord(C) - Ord('0')
  else if (C >= 'a') and (C <= 'f') then
    Result := Ord(C) - Ord('a') + 10
  else if (C >= 'A') and (C <= 'F') then
    Result := Ord(C) - Ord('A') + 10
  else
    Result := -1;
end;

function InvariantFormatSettings: TFormatSettings;
begin
{$IFDEF FPC}
  Result := DefaultFormatSettings;
{$ELSE}
  Result := TFormatSettings.Create;
{$ENDIF}
  Result.DecimalSeparator := '.';
  Result.ThousandSeparator := ',';
end;

function DoubleToJSONText(Value: Double): string;
var
  FS: TFormatSettings;
begin
  if (Frac(Value) = 0) and (Abs(Value) < 1E15) then
    Result := IntToStr(Trunc(Value))
  else
  begin
    FS := InvariantFormatSettings;
    Result := FloatToStrF(Value, ffGeneral, 15, 0, FS);
  end;
end;

function TryJSONTextToDouble(const S: string; out Value: Double): Boolean;
var
  FS: TFormatSettings;
begin
  FS := InvariantFormatSettings;
  Result := TryStrToFloat(S, Value, FS);
end;

function MinInt64(A, B: Int64): Int64;
begin
  if A < B then Result := A else Result := B;
end;

function MaxInt64(A, B: Int64): Int64;
begin
  if A > B then Result := A else Result := B;
end;

end.
