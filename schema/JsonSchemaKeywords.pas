{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit JsonSchemaKeywords;

{ Built-in building blocks shared by the draft classes:
    * type checkers      (TypeNull ... TypeInteger)
    * format checkers    (IsDateString ... )
    * keyword validators (Kw...)   function(Ctx: TKeywordContext): Boolean
    * keyword checkers   (Check...) procedure(Ctx: TCompileContext)
  They are plain functions so that drafts, validator-level registrations and
  user code can all reuse them freely. }

interface

uses
  SysUtils, Classes, JSONPathCommon, JSONPathJSON, JsonSchemaErrors, JsonSchemaCore;

{ ---- types ---- }
function TypeNull(AValue: TJSONValue): Boolean;
function TypeBoolean(AValue: TJSONValue): Boolean;
function TypeObject(AValue: TJSONValue): Boolean;
function TypeArray(AValue: TJSONValue): Boolean;
function TypeNumber(AValue: TJSONValue): Boolean;
function TypeString(AValue: TJSONValue): Boolean;
{ A number without fractional part. The JSON model stores numbers as Double,
  so 1.0 and 1 cannot be told apart and both count as integers in every
  draft. }
function TypeInteger(AValue: TJSONValue): Boolean;
procedure RegisterBuiltinTypes(ARegistry: TTypeRegistry);

{ ---- formats ---- }
function IsDateString(const AText: string): Boolean;
function IsTimeString(const AText: string): Boolean;
function IsDateTimeString(const AText: string): Boolean;
function IsEmailString(const AText: string): Boolean;
function IsHostnameString(const AText: string): Boolean;
function IsIPv4String(const AText: string): Boolean;
function IsIPv6String(const AText: string): Boolean;
function IsUuidString(const AText: string): Boolean;
function IsUriString(const AText: string): Boolean;
function IsJsonPointerString(const AText: string): Boolean;
procedure RegisterBuiltinFormats(ARegistry: TFormatRegistry);

{ ---- keyword validators ---- }
function KwType(Ctx: TKeywordContext): Boolean;
function KwEnum(Ctx: TKeywordContext): Boolean;
function KwConst(Ctx: TKeywordContext): Boolean;
function KwMinimumD4(Ctx: TKeywordContext): Boolean;
function KwMaximumD4(Ctx: TKeywordContext): Boolean;
function KwMinimum(Ctx: TKeywordContext): Boolean;
function KwMaximum(Ctx: TKeywordContext): Boolean;
function KwExclusiveMinimum(Ctx: TKeywordContext): Boolean;
function KwExclusiveMaximum(Ctx: TKeywordContext): Boolean;
function KwMultipleOf(Ctx: TKeywordContext): Boolean;
function KwMinLength(Ctx: TKeywordContext): Boolean;
function KwMaxLength(Ctx: TKeywordContext): Boolean;
function KwPattern(Ctx: TKeywordContext): Boolean;
function KwFormat(Ctx: TKeywordContext): Boolean;
function KwMinItems(Ctx: TKeywordContext): Boolean;
function KwMaxItems(Ctx: TKeywordContext): Boolean;
function KwUniqueItems(Ctx: TKeywordContext): Boolean;
function KwItems(Ctx: TKeywordContext): Boolean;
function KwAdditionalItems(Ctx: TKeywordContext): Boolean;
function KwPrefixItems(Ctx: TKeywordContext): Boolean;
function KwItems2020(Ctx: TKeywordContext): Boolean;
function KwContains(Ctx: TKeywordContext): Boolean;
function KwContainsCounting(Ctx: TKeywordContext): Boolean;
function KwRequired(Ctx: TKeywordContext): Boolean;
function KwProperties(Ctx: TKeywordContext): Boolean;
function KwPatternProperties(Ctx: TKeywordContext): Boolean;
function KwAdditionalProperties(Ctx: TKeywordContext): Boolean;
function KwPropertyNames(Ctx: TKeywordContext): Boolean;
function KwMinProperties(Ctx: TKeywordContext): Boolean;
function KwMaxProperties(Ctx: TKeywordContext): Boolean;
function KwDependencies(Ctx: TKeywordContext): Boolean;
function KwDependentRequired(Ctx: TKeywordContext): Boolean;
function KwDependentSchemas(Ctx: TKeywordContext): Boolean;
function KwAllOf(Ctx: TKeywordContext): Boolean;
function KwAnyOf(Ctx: TKeywordContext): Boolean;
function KwOneOf(Ctx: TKeywordContext): Boolean;
function KwNot(Ctx: TKeywordContext): Boolean;
function KwIf(Ctx: TKeywordContext): Boolean;
function KwRef(Ctx: TKeywordContext): Boolean;

{ ---- keyword checkers (schema compilation) ---- }
procedure CheckType(Ctx: TCompileContext);
procedure CheckString(Ctx: TCompileContext);
procedure CheckBoolean(Ctx: TCompileContext);
procedure CheckNumber(Ctx: TCompileContext);
procedure CheckPositiveNumber(Ctx: TCompileContext);
procedure CheckNonNegativeInteger(Ctx: TCompileContext);
procedure CheckArray(Ctx: TCompileContext);
procedure CheckEnumLegacy(Ctx: TCompileContext);
procedure CheckPatternValue(Ctx: TCompileContext);
procedure CheckRequiredLegacy(Ctx: TCompileContext);
procedure CheckRequired(Ctx: TCompileContext);
procedure CheckSchema(Ctx: TCompileContext);
procedure CheckSchemaArray(Ctx: TCompileContext);
procedure CheckSchemaMap(Ctx: TCompileContext);
procedure CheckPatternMap(Ctx: TCompileContext);
procedure CheckItems(Ctx: TCompileContext);
procedure CheckDependencies(Ctx: TCompileContext);
procedure CheckDependentRequired(Ctx: TCompileContext);
procedure CheckExclusiveMinimumD4(Ctx: TCompileContext);
procedure CheckExclusiveMaximumD4(Ctx: TCompileContext);
procedure CheckRef(Ctx: TCompileContext);
procedure CheckAnchor(Ctx: TCompileContext);

implementation

{ ================= types ================= }

function TypeNull(AValue: TJSONValue): Boolean;
begin
  Result := AValue.Kind = jkNull;
end;

function TypeBoolean(AValue: TJSONValue): Boolean;
begin
  Result := AValue.Kind = jkBoolean;
end;

function TypeObject(AValue: TJSONValue): Boolean;
begin
  Result := AValue.Kind = jkObject;
end;

function TypeArray(AValue: TJSONValue): Boolean;
begin
  Result := AValue.Kind = jkArray;
end;

function TypeNumber(AValue: TJSONValue): Boolean;
begin
  Result := AValue.Kind = jkNumber;
end;

function TypeString(AValue: TJSONValue): Boolean;
begin
  Result := AValue.Kind = jkString;
end;

function TypeInteger(AValue: TJSONValue): Boolean;
begin
  Result := (AValue.Kind = jkNumber) and (Frac(AValue.NumberValue) = 0);
end;

procedure RegisterBuiltinTypes(ARegistry: TTypeRegistry);
begin
  ARegistry.RegisterType('null', TypeNull);
  ARegistry.RegisterType('boolean', TypeBoolean);
  ARegistry.RegisterType('object', TypeObject);
  ARegistry.RegisterType('array', TypeArray);
  ARegistry.RegisterType('number', TypeNumber);
  ARegistry.RegisterType('string', TypeString);
  ARegistry.RegisterType('integer', TypeInteger);
end;

{ ================= formats ================= }

function IsDigitChar(C: Char): Boolean;
begin
  Result := (C >= '0') and (C <= '9');
end;

function IsHexChar(C: Char): Boolean;
begin
  Result := IsDigitChar(C) or ((C >= 'a') and (C <= 'f')) or ((C >= 'A') and (C <= 'F'));
end;

function IsLetterChar(C: Char): Boolean;
begin
  Result := ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z'));
end;

function DigitsAt(const S: string; AFrom, ACount: Integer): Boolean;
var
  I: Integer;
begin
  Result := AFrom + ACount - 1 <= Length(S);
  if not Result then
    Exit;
  for I := AFrom to AFrom + ACount - 1 do
    if not IsDigitChar(S[I]) then
    begin
      Result := False;
      Exit;
    end;
end;

function NumberAt(const S: string; AFrom, ACount: Integer): Integer;
begin
  Result := StrToInt(Copy(S, AFrom, ACount));
end;

function IsDateString(const AText: string): Boolean;
var
  Y, M, D, MaxDay: Integer;
begin
  Result := False;
  if (Length(AText) <> 10) or (AText[5] <> '-') or (AText[8] <> '-') then
    Exit;
  if not (DigitsAt(AText, 1, 4) and DigitsAt(AText, 6, 2) and DigitsAt(AText, 9, 2)) then
    Exit;
  Y := NumberAt(AText, 1, 4);
  M := NumberAt(AText, 6, 2);
  D := NumberAt(AText, 9, 2);
  if (M < 1) or (M > 12) or (D < 1) then
    Exit;
  case M of
    4, 6, 9, 11: MaxDay := 30;
    2:
      if ((Y mod 4 = 0) and (Y mod 100 <> 0)) or (Y mod 400 = 0) then
        MaxDay := 29
      else
        MaxDay := 28;
  else
    MaxDay := 31;
  end;
  Result := D <= MaxDay;
end;

function IsTimeString(const AText: string): Boolean;
var
  I, Len: Integer;
begin
  Result := False;
  Len := Length(AText);
  if (Len < 9) or (AText[3] <> ':') or (AText[6] <> ':') then
    Exit;
  if not (DigitsAt(AText, 1, 2) and DigitsAt(AText, 4, 2) and DigitsAt(AText, 7, 2)) then
    Exit;
  if (NumberAt(AText, 1, 2) > 23) or (NumberAt(AText, 4, 2) > 59)
    or (NumberAt(AText, 7, 2) > 60) then
    Exit;
  I := 9;
  if AText[I] = '.' then
  begin
    Inc(I);
    if (I > Len) or not IsDigitChar(AText[I]) then
      Exit;
    while (I <= Len) and IsDigitChar(AText[I]) do
      Inc(I);
  end;
  if I > Len then
    Exit;
  if (AText[I] = 'Z') or (AText[I] = 'z') then
    Result := I = Len
  else if (AText[I] = '+') or (AText[I] = '-') then
    Result := (Len - I = 5) and (AText[I + 3] = ':') and DigitsAt(AText, I + 1, 2)
      and DigitsAt(AText, I + 4, 2) and (NumberAt(AText, I + 1, 2) <= 23)
      and (NumberAt(AText, I + 4, 2) <= 59);
end;

function IsDateTimeString(const AText: string): Boolean;
begin
  Result := (Length(AText) >= 20) and ((AText[11] = 'T') or (AText[11] = 't'))
    and IsDateString(Copy(AText, 1, 10)) and IsTimeString(Copy(AText, 12, Length(AText)));
end;

function IsHostnameString(const AText: string): Boolean;
var
  I, LabelLen: Integer;
  C: Char;
  LabelStart: Integer;
begin
  Result := False;
  if (AText = '') or (Length(AText) > 253) then
    Exit;
  LabelLen := 0;
  LabelStart := 1;
  for I := 1 to Length(AText) + 1 do
  begin
    if I <= Length(AText) then
      C := AText[I]
    else
      C := '.';
    if C = '.' then
    begin
      if (LabelLen = 0) or (LabelLen > 63) then
        Exit;
      if (AText[LabelStart] = '-') or (AText[I - 1] = '-') then
        Exit;
      LabelLen := 0;
      LabelStart := I + 1;
    end
    else if IsLetterChar(C) or IsDigitChar(C) or (C = '-') then
      Inc(LabelLen)
    else
      Exit;
  end;
  Result := True;
end;

function IsIPv4String(const AText: string): Boolean;
var
  I, Parts, PartLen, Value: Integer;
  C: Char;
begin
  Result := False;
  Parts := 0;
  PartLen := 0;
  Value := 0;
  for I := 1 to Length(AText) + 1 do
  begin
    if I <= Length(AText) then
      C := AText[I]
    else
      C := '.';
    if C = '.' then
    begin
      if (PartLen = 0) or (Value > 255) then
        Exit;
      Inc(Parts);
      PartLen := 0;
      Value := 0;
    end
    else if IsDigitChar(C) then
    begin
      if (PartLen > 0) and (Value = 0) then
        Exit; { leading zero }
      Value := Value * 10 + (Ord(C) - Ord('0'));
      Inc(PartLen);
      if PartLen > 3 then
        Exit;
    end
    else
      Exit;
  end;
  Result := Parts = 4;
end;

function CountHexGroups(const APart: string; out ACount: Integer): Boolean;
var
  I, GroupLen: Integer;
  C: Char;
begin
  ACount := 0;
  Result := True;
  if APart = '' then
    Exit;
  ACount := 1;
  GroupLen := 0;
  for I := 1 to Length(APart) do
  begin
    C := APart[I];
    if C = ':' then
    begin
      if GroupLen = 0 then
        Result := False;
      GroupLen := 0;
      Inc(ACount);
    end
    else if IsHexChar(C) then
    begin
      Inc(GroupLen);
      if GroupLen > 4 then
        Result := False;
    end
    else
      Result := False;
  end;
  if GroupLen = 0 then
    Result := False;
end;

function IsIPv6String(const AText: string): Boolean;
var
  P, LeftCount, RightCount: Integer;
  Rest: string;
begin
  Result := False;
  if AText = '' then
    Exit;
  P := Pos('::', AText);
  if P = 0 then
  begin
    Result := CountHexGroups(AText, LeftCount) and (LeftCount = 8);
    Exit;
  end;
  Rest := Copy(AText, P + 1, Length(AText));
  if Pos('::', Rest) > 0 then
    Exit;
  if CountHexGroups(Copy(AText, 1, P - 1), LeftCount)
    and CountHexGroups(Copy(AText, P + 2, Length(AText)), RightCount) then
    Result := LeftCount + RightCount <= 7;
end;

function IsEmailString(const AText: string): Boolean;
var
  At, I: Integer;
  Local, Domain: string;
begin
  Result := False;
  At := Pos('@', AText);
  if At < 2 then
    Exit;
  Local := Copy(AText, 1, At - 1);
  Domain := Copy(AText, At + 1, Length(AText));
  if (Pos('@', Domain) > 0) or (Length(Local) > 64) or (Local[1] = '.')
    or (Local[Length(Local)] = '.') or (Pos('..', Local) > 0) then
    Exit;
  for I := 1 to Length(Local) do
    if (Ord(Local[I]) <= 32) or (Local[I] = ',') or (Local[I] = ';') or (Local[I] = '(')
      or (Local[I] = ')') then
      Exit;
  Result := IsHostnameString(Domain);
end;

function IsUuidString(const AText: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if Length(AText) <> 36 then
    Exit;
  for I := 1 to 36 do
    if (I = 9) or (I = 14) or (I = 19) or (I = 24) then
    begin
      if AText[I] <> '-' then
        Exit;
    end
    else if not IsHexChar(AText[I]) then
      Exit;
  Result := True;
end;

function IsUriString(const AText: string): Boolean;
var
  Colon, I: Integer;
  C: Char;
begin
  Result := False;
  Colon := Pos(':', AText);
  if (Colon < 2) or (Colon = Length(AText)) or not IsLetterChar(AText[1]) then
    Exit;
  for I := 2 to Colon - 1 do
  begin
    C := AText[I];
    if not (IsLetterChar(C) or IsDigitChar(C) or (C = '+') or (C = '-') or (C = '.')) then
      Exit;
  end;
  for I := Colon + 1 to Length(AText) do
    if (Ord(AText[I]) <= 32) or (AText[I] = '"') or (AText[I] = '<') or (AText[I] = '>')
      or (AText[I] = '\') then
      Exit;
  Result := True;
end;

function IsJsonPointerString(const AText: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if AText = '' then
  begin
    Result := True;
    Exit;
  end;
  if AText[1] <> '/' then
    Exit;
  for I := 1 to Length(AText) do
    if AText[I] = '~' then
      if (I = Length(AText)) or ((AText[I + 1] <> '0') and (AText[I + 1] <> '1')) then
        Exit;
  Result := True;
end;

procedure RegisterBuiltinFormats(ARegistry: TFormatRegistry);
begin
  ARegistry.RegisterFormat('date', IsDateString);
  ARegistry.RegisterFormat('time', IsTimeString);
  ARegistry.RegisterFormat('date-time', IsDateTimeString);
  ARegistry.RegisterFormat('email', IsEmailString);
  ARegistry.RegisterFormat('hostname', IsHostnameString);
  ARegistry.RegisterFormat('ipv4', IsIPv4String);
  ARegistry.RegisterFormat('ipv6', IsIPv6String);
  ARegistry.RegisterFormat('uuid', IsUuidString);
  ARegistry.RegisterFormat('uri', IsUriString);
  ARegistry.RegisterFormat('json-pointer', IsJsonPointerString);
end;

{ ================= validators ================= }

function TypeListText(AValue: TJSONValue): string;
var
  I: Integer;
begin
  if AValue.Kind = jkString then
    Result := AValue.StringValue
  else
  begin
    Result := '';
    for I := 0 to AValue.Count - 1 do
    begin
      if I > 0 then
        Result := Result + ' or ';
      Result := Result + AValue[I].StringValue;
    end;
  end;
end;

function KwType(Ctx: TKeywordContext): Boolean;
var
  V: TJSONValue;
  I: Integer;
begin
  V := Ctx.KeywordValue;
  Result := False;
  if V.Kind = jkString then
    Result := Ctx.TypeMatches(V.StringValue, Ctx.Instance)
  else
    for I := 0 to V.Count - 1 do
      if Ctx.TypeMatches(V[I].StringValue, Ctx.Instance) then
      begin
        Result := True;
        Break;
      end;
  if not Result then
    Ctx.AddError('value is not of type ' + TypeListText(V));
end;

function KwEnum(Ctx: TKeywordContext): Boolean;
var
  V: TJSONValue;
  I: Integer;
begin
  V := Ctx.KeywordValue;
  Result := False;
  for I := 0 to V.Count - 1 do
    if JSONEquals(V[I], Ctx.Instance) then
    begin
      Result := True;
      Break;
    end;
  if not Result then
    Ctx.AddError('value is not one of the allowed enum values');
end;

function KwConst(Ctx: TKeywordContext): Boolean;
begin
  Result := JSONEquals(Ctx.KeywordValue, Ctx.Instance);
  if not Result then
    Ctx.AddError('value does not equal the required constant ' + JSONToText(Ctx.KeywordValue));
end;

function KwMinimumD4(Ctx: TKeywordContext): Boolean;
var
  Excl: TJSONValue;
begin
  Result := True;
  if Ctx.Instance.Kind <> jkNumber then
    Exit;
  Excl := Ctx.Sibling('exclusiveMinimum');
  if (Excl <> nil) and (Excl.Kind = jkBoolean) and Excl.BoolValue then
  begin
    Result := Ctx.Instance.NumberValue > Ctx.KeywordValue.NumberValue;
    if not Result then
      Ctx.AddError('value must be greater than ' + JSONToText(Ctx.KeywordValue));
  end
  else
  begin
    Result := Ctx.Instance.NumberValue >= Ctx.KeywordValue.NumberValue;
    if not Result then
      Ctx.AddError('value must be greater than or equal to ' + JSONToText(Ctx.KeywordValue));
  end;
end;

function KwMaximumD4(Ctx: TKeywordContext): Boolean;
var
  Excl: TJSONValue;
begin
  Result := True;
  if Ctx.Instance.Kind <> jkNumber then
    Exit;
  Excl := Ctx.Sibling('exclusiveMaximum');
  if (Excl <> nil) and (Excl.Kind = jkBoolean) and Excl.BoolValue then
  begin
    Result := Ctx.Instance.NumberValue < Ctx.KeywordValue.NumberValue;
    if not Result then
      Ctx.AddError('value must be less than ' + JSONToText(Ctx.KeywordValue));
  end
  else
  begin
    Result := Ctx.Instance.NumberValue <= Ctx.KeywordValue.NumberValue;
    if not Result then
      Ctx.AddError('value must be less than or equal to ' + JSONToText(Ctx.KeywordValue));
  end;
end;

function KwMinimum(Ctx: TKeywordContext): Boolean;
begin
  Result := (Ctx.Instance.Kind <> jkNumber)
    or (Ctx.Instance.NumberValue >= Ctx.KeywordValue.NumberValue);
  if not Result then
    Ctx.AddError('value must be greater than or equal to ' + JSONToText(Ctx.KeywordValue));
end;

function KwMaximum(Ctx: TKeywordContext): Boolean;
begin
  Result := (Ctx.Instance.Kind <> jkNumber)
    or (Ctx.Instance.NumberValue <= Ctx.KeywordValue.NumberValue);
  if not Result then
    Ctx.AddError('value must be less than or equal to ' + JSONToText(Ctx.KeywordValue));
end;

function KwExclusiveMinimum(Ctx: TKeywordContext): Boolean;
begin
  Result := (Ctx.Instance.Kind <> jkNumber)
    or (Ctx.Instance.NumberValue > Ctx.KeywordValue.NumberValue);
  if not Result then
    Ctx.AddError('value must be greater than ' + JSONToText(Ctx.KeywordValue));
end;

function KwExclusiveMaximum(Ctx: TKeywordContext): Boolean;
begin
  Result := (Ctx.Instance.Kind <> jkNumber)
    or (Ctx.Instance.NumberValue < Ctx.KeywordValue.NumberValue);
  if not Result then
    Ctx.AddError('value must be less than ' + JSONToText(Ctx.KeywordValue));
end;

function KwMultipleOf(Ctx: TKeywordContext): Boolean;
var
  Q, F: Double;
begin
  Result := True;
  if Ctx.Instance.Kind <> jkNumber then
    Exit;
  Q := Ctx.Instance.NumberValue / Ctx.KeywordValue.NumberValue;
  F := Abs(Frac(Q));
  Result := (F < 1E-9) or (1 - F < 1E-9);
  if not Result then
    Ctx.AddError('value is not a multiple of ' + JSONToText(Ctx.KeywordValue));
end;

function KwMinLength(Ctx: TKeywordContext): Boolean;
begin
  Result := (Ctx.Instance.Kind <> jkString)
    or (CodePointLength(Ctx.Instance.StringValue) >= Ctx.KeywordValue.NumberValue);
  if not Result then
    Ctx.AddError('string is shorter than ' + JSONToText(Ctx.KeywordValue) + ' characters');
end;

function KwMaxLength(Ctx: TKeywordContext): Boolean;
begin
  Result := (Ctx.Instance.Kind <> jkString)
    or (CodePointLength(Ctx.Instance.StringValue) <= Ctx.KeywordValue.NumberValue);
  if not Result then
    Ctx.AddError('string is longer than ' + JSONToText(Ctx.KeywordValue) + ' characters');
end;

function KwPattern(Ctx: TKeywordContext): Boolean;
begin
  Result := (Ctx.Instance.Kind <> jkString)
    or Ctx.RegexSearch(Ctx.KeywordValue.StringValue, Ctx.Instance.StringValue);
  if not Result then
    Ctx.AddError('string does not match the pattern "' + Ctx.KeywordValue.StringValue + '"');
end;

function KwFormat(Ctx: TKeywordContext): Boolean;
begin
  Result := True;
  if (not Ctx.AssertFormats) or (Ctx.Instance.Kind <> jkString) then
    Exit;
  Result := Ctx.FormatValid(Ctx.KeywordValue.StringValue, Ctx.Instance.StringValue);
  if not Result then
    Ctx.AddError('string is not a valid "' + Ctx.KeywordValue.StringValue + '"');
end;

function KwMinItems(Ctx: TKeywordContext): Boolean;
begin
  Result := (Ctx.Instance.Kind <> jkArray)
    or (Ctx.Instance.Count >= Ctx.KeywordValue.NumberValue);
  if not Result then
    Ctx.AddError('array has fewer than ' + JSONToText(Ctx.KeywordValue) + ' items');
end;

function KwMaxItems(Ctx: TKeywordContext): Boolean;
begin
  Result := (Ctx.Instance.Kind <> jkArray)
    or (Ctx.Instance.Count <= Ctx.KeywordValue.NumberValue);
  if not Result then
    Ctx.AddError('array has more than ' + JSONToText(Ctx.KeywordValue) + ' items');
end;

function KwUniqueItems(Ctx: TKeywordContext): Boolean;
var
  Arr: TJSONValue;
  I, J: Integer;
begin
  Result := True;
  Arr := Ctx.Instance;
  if (Arr.Kind <> jkArray) or not Ctx.KeywordValue.BoolValue then
    Exit;
  for I := 0 to Arr.Count - 2 do
    for J := I + 1 to Arr.Count - 1 do
      if JSONEquals(Arr[I], Arr[J]) then
      begin
        Ctx.AddError(Format('items %d and %d are equal; items must be unique', [I, J]));
        Result := False;
        Exit;
      end;
end;

function KwItems(Ctx: TKeywordContext): Boolean;
var
  V, Arr: TJSONValue;
  I, Limit: Integer;
begin
  Result := True;
  Arr := Ctx.Instance;
  if Arr.Kind <> jkArray then
    Exit;
  V := Ctx.KeywordValue;
  if V.Kind = jkArray then
  begin
    Limit := V.Count;
    if Arr.Count < Limit then
      Limit := Arr.Count;
    for I := 0 to Limit - 1 do
      if not Ctx.ValidateSubschema(V[I], Arr[I], JsonPointerIndexStep(I),
        JsonPointerIndexStep(I)) then
        Result := False;
  end
  else
    for I := 0 to Arr.Count - 1 do
      if not Ctx.ValidateSubschema(V, Arr[I], '', JsonPointerIndexStep(I)) then
        Result := False;
end;

function KwAdditionalItems(Ctx: TKeywordContext): Boolean;
var
  Items, Arr: TJSONValue;
  I: Integer;
begin
  Result := True;
  Arr := Ctx.Instance;
  Items := Ctx.Sibling('items');
  if (Arr.Kind <> jkArray) or (Items = nil) or (Items.Kind <> jkArray) then
    Exit;
  for I := Items.Count to Arr.Count - 1 do
    if not Ctx.ValidateSubschema(Ctx.KeywordValue, Arr[I], '', JsonPointerIndexStep(I)) then
      Result := False;
end;

function KwPrefixItems(Ctx: TKeywordContext): Boolean;
var
  V, Arr: TJSONValue;
  I, Limit: Integer;
begin
  Result := True;
  Arr := Ctx.Instance;
  if Arr.Kind <> jkArray then
    Exit;
  V := Ctx.KeywordValue;
  Limit := V.Count;
  if Arr.Count < Limit then
    Limit := Arr.Count;
  for I := 0 to Limit - 1 do
    if not Ctx.ValidateSubschema(V[I], Arr[I], JsonPointerIndexStep(I),
      JsonPointerIndexStep(I)) then
      Result := False;
end;

function KwItems2020(Ctx: TKeywordContext): Boolean;
var
  Prefix, Arr: TJSONValue;
  I, StartAt: Integer;
begin
  Result := True;
  Arr := Ctx.Instance;
  if Arr.Kind <> jkArray then
    Exit;
  Prefix := Ctx.Sibling('prefixItems');
  if (Prefix <> nil) and (Prefix.Kind = jkArray) then
    StartAt := Prefix.Count
  else
    StartAt := 0;
  for I := StartAt to Arr.Count - 1 do
    if not Ctx.ValidateSubschema(Ctx.KeywordValue, Arr[I], '', JsonPointerIndexStep(I)) then
      Result := False;
end;

function KwContains(Ctx: TKeywordContext): Boolean;
var
  Arr: TJSONValue;
  I: Integer;
begin
  Result := True;
  Arr := Ctx.Instance;
  if Arr.Kind <> jkArray then
    Exit;
  Result := False;
  for I := 0 to Arr.Count - 1 do
    if Ctx.TestSubschema(Ctx.KeywordValue, Arr[I]) then
    begin
      Result := True;
      Break;
    end;
  if not Result then
    Ctx.AddError('no item matches the "contains" subschema');
end;

function KwContainsCounting(Ctx: TKeywordContext): Boolean;
var
  Arr, V: TJSONValue;
  I, Matches, MinC, MaxC: Integer;
begin
  Result := True;
  Arr := Ctx.Instance;
  if Arr.Kind <> jkArray then
    Exit;
  MinC := 1;
  MaxC := -1;
  V := Ctx.Sibling('minContains');
  if (V <> nil) and (V.Kind = jkNumber) then
    MinC := Trunc(V.NumberValue);
  V := Ctx.Sibling('maxContains');
  if (V <> nil) and (V.Kind = jkNumber) then
    MaxC := Trunc(V.NumberValue);
  Matches := 0;
  for I := 0 to Arr.Count - 1 do
    if Ctx.TestSubschema(Ctx.KeywordValue, Arr[I]) then
      Inc(Matches);
  if Matches < MinC then
  begin
    Ctx.AddError(Format('%d item(s) match the "contains" subschema; at least %d required',
      [Matches, MinC]));
    Result := False;
  end
  else if (MaxC >= 0) and (Matches > MaxC) then
  begin
    Ctx.AddError(Format('%d item(s) match the "contains" subschema; at most %d allowed',
      [Matches, MaxC]));
    Result := False;
  end;
end;

function KwRequired(Ctx: TKeywordContext): Boolean;
var
  V, Obj: TJSONValue;
  I: Integer;
begin
  Result := True;
  Obj := Ctx.Instance;
  if Obj.Kind <> jkObject then
    Exit;
  V := Ctx.KeywordValue;
  for I := 0 to V.Count - 1 do
    if Obj.FindMember(V[I].StringValue) = nil then
    begin
      Ctx.AddError('missing required property "' + V[I].StringValue + '"');
      Result := False;
    end;
end;

function KwProperties(Ctx: TKeywordContext): Boolean;
var
  Obj, Props, Child: TJSONValue;
  I: Integer;
begin
  Result := True;
  Obj := Ctx.Instance;
  if Obj.Kind <> jkObject then
    Exit;
  Props := Ctx.KeywordValue;
  for I := 0 to Props.Count - 1 do
  begin
    Child := Obj.FindMember(Props.Names[I]);
    if Child <> nil then
      if not Ctx.ValidateSubschema(Props[I], Child, JsonPointerStep(Props.Names[I]),
        JsonPointerStep(Props.Names[I])) then
        Result := False;
  end;
end;

function KwPatternProperties(Ctx: TKeywordContext): Boolean;
var
  Obj, Pats: TJSONValue;
  I, J: Integer;
begin
  Result := True;
  Obj := Ctx.Instance;
  if Obj.Kind <> jkObject then
    Exit;
  Pats := Ctx.KeywordValue;
  for I := 0 to Pats.Count - 1 do
    for J := 0 to Obj.Count - 1 do
      if Ctx.RegexSearch(Pats.Names[I], Obj.Names[J]) then
        if not Ctx.ValidateSubschema(Pats[I], Obj[J], JsonPointerStep(Pats.Names[I]),
          JsonPointerStep(Obj.Names[J])) then
          Result := False;
end;

function KwAdditionalProperties(Ctx: TKeywordContext): Boolean;
var
  Obj, Props, Pats: TJSONValue;
  J, I: Integer;
  Known: Boolean;
begin
  Result := True;
  Obj := Ctx.Instance;
  if Obj.Kind <> jkObject then
    Exit;
  Props := Ctx.Sibling('properties');
  Pats := Ctx.Sibling('patternProperties');
  for J := 0 to Obj.Count - 1 do
  begin
    Known := (Props <> nil) and (Props.Kind = jkObject)
      and (Props.FindMember(Obj.Names[J]) <> nil);
    if (not Known) and (Pats <> nil) and (Pats.Kind = jkObject) then
      for I := 0 to Pats.Count - 1 do
        if Ctx.RegexSearch(Pats.Names[I], Obj.Names[J]) then
        begin
          Known := True;
          Break;
        end;
    if not Known then
      if not Ctx.ValidateSubschema(Ctx.KeywordValue, Obj[J], '',
        JsonPointerStep(Obj.Names[J])) then
        Result := False;
  end;
end;

function KwPropertyNames(Ctx: TKeywordContext): Boolean;
var
  Obj, NameValue: TJSONValue;
  I: Integer;
begin
  Result := True;
  Obj := Ctx.Instance;
  if Obj.Kind <> jkObject then
    Exit;
  for I := 0 to Obj.Count - 1 do
  begin
    NameValue := NewJSONString(Obj.Names[I]);
    try
      if not Ctx.ValidateSubschema(Ctx.KeywordValue, NameValue, '',
        JsonPointerStep(Obj.Names[I])) then
        Result := False;
    finally
      NameValue.Free;
    end;
  end;
end;

function KwMinProperties(Ctx: TKeywordContext): Boolean;
begin
  Result := (Ctx.Instance.Kind <> jkObject)
    or (Ctx.Instance.Count >= Ctx.KeywordValue.NumberValue);
  if not Result then
    Ctx.AddError('object has fewer than ' + JSONToText(Ctx.KeywordValue) + ' properties');
end;

function KwMaxProperties(Ctx: TKeywordContext): Boolean;
begin
  Result := (Ctx.Instance.Kind <> jkObject)
    or (Ctx.Instance.Count <= Ctx.KeywordValue.NumberValue);
  if not Result then
    Ctx.AddError('object has more than ' + JSONToText(Ctx.KeywordValue) + ' properties');
end;

function CheckDependencyEntries(Ctx: TKeywordContext; ASchemaForms: Boolean): Boolean;
var
  Obj, Deps, Dep: TJSONValue;
  I, K: Integer;
begin
  Result := True;
  Obj := Ctx.Instance;
  if Obj.Kind <> jkObject then
    Exit;
  Deps := Ctx.KeywordValue;
  for I := 0 to Deps.Count - 1 do
  begin
    if Obj.FindMember(Deps.Names[I]) = nil then
      Continue;
    Dep := Deps[I];
    if Dep.Kind = jkArray then
    begin
      for K := 0 to Dep.Count - 1 do
        if Obj.FindMember(Dep[K].StringValue) = nil then
        begin
          Ctx.AddError('property "' + Deps.Names[I] + '" requires property "' +
            Dep[K].StringValue + '"');
          Result := False;
        end;
    end
    else if ASchemaForms then
      if not Ctx.ValidateSubschema(Dep, Obj, JsonPointerStep(Deps.Names[I]), '') then
        Result := False;
  end;
end;

function KwDependencies(Ctx: TKeywordContext): Boolean;
begin
  Result := CheckDependencyEntries(Ctx, True);
end;

function KwDependentRequired(Ctx: TKeywordContext): Boolean;
begin
  Result := CheckDependencyEntries(Ctx, False);
end;

function KwDependentSchemas(Ctx: TKeywordContext): Boolean;
var
  Obj, Deps: TJSONValue;
  I: Integer;
begin
  Result := True;
  Obj := Ctx.Instance;
  if Obj.Kind <> jkObject then
    Exit;
  Deps := Ctx.KeywordValue;
  for I := 0 to Deps.Count - 1 do
    if Obj.FindMember(Deps.Names[I]) <> nil then
      if not Ctx.ValidateSubschema(Deps[I], Obj, JsonPointerStep(Deps.Names[I]), '') then
        Result := False;
end;

function KwAllOf(Ctx: TKeywordContext): Boolean;
var
  V: TJSONValue;
  I: Integer;
begin
  Result := True;
  V := Ctx.KeywordValue;
  for I := 0 to V.Count - 1 do
    if not Ctx.ValidateSubschema(V[I], Ctx.Instance, JsonPointerIndexStep(I), '') then
      Result := False;
end;

function KwAnyOf(Ctx: TKeywordContext): Boolean;
var
  V: TJSONValue;
  I: Integer;
begin
  V := Ctx.KeywordValue;
  Result := False;
  for I := 0 to V.Count - 1 do
    if Ctx.TestSubschema(V[I], Ctx.Instance) then
    begin
      Result := True;
      Break;
    end;
  if not Result then
    Ctx.AddError('value does not match any of the ' + IntToStr(V.Count) + ' subschemas');
end;

function KwOneOf(Ctx: TKeywordContext): Boolean;
var
  V: TJSONValue;
  I, Matches: Integer;
begin
  V := Ctx.KeywordValue;
  Matches := 0;
  for I := 0 to V.Count - 1 do
    if Ctx.TestSubschema(V[I], Ctx.Instance) then
      Inc(Matches);
  Result := Matches = 1;
  if not Result then
    Ctx.AddError(Format('value matches %d of %d subschemas; exactly one is required',
      [Matches, V.Count]));
end;

function KwNot(Ctx: TKeywordContext): Boolean;
begin
  Result := not Ctx.TestSubschema(Ctx.KeywordValue, Ctx.Instance);
  if not Result then
    Ctx.AddError('value must not match the "not" subschema');
end;

function KwIf(Ctx: TKeywordContext): Boolean;
begin
  if Ctx.TestSubschema(Ctx.KeywordValue, Ctx.Instance) then
  begin
    if Ctx.Sibling('then') <> nil then
      Result := Ctx.ValidateSibling('then', Ctx.Instance)
    else
      Result := True;
  end
  else
  begin
    if Ctx.Sibling('else') <> nil then
      Result := Ctx.ValidateSibling('else', Ctx.Instance)
    else
      Result := True;
  end;
end;

function KwRef(Ctx: TKeywordContext): Boolean;
begin
  Result := Ctx.ValidateReference(Ctx.KeywordValue, Ctx.Instance);
end;

{ ================= checkers ================= }

function IsNonNegInt(V: TJSONValue): Boolean;
begin
  Result := (V.Kind = jkNumber) and (Frac(V.NumberValue) = 0) and (V.NumberValue >= 0);
end;

function HasDuplicateStrings(V: TJSONValue): Boolean;
var
  I, J: Integer;
begin
  Result := False;
  for I := 0 to V.Count - 2 do
    for J := I + 1 to V.Count - 1 do
      if V[I].StringValue = V[J].StringValue then
      begin
        Result := True;
        Exit;
      end;
end;

function AllStrings(V: TJSONValue): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to V.Count - 1 do
    if V[I].Kind <> jkString then
    begin
      Result := False;
      Exit;
    end;
end;

procedure CheckType(Ctx: TCompileContext);
var
  V: TJSONValue;
  I: Integer;
begin
  V := Ctx.KeywordValue;
  if V.Kind = jkString then
  begin
    if not Ctx.IsKnownType(V.StringValue) then
      Ctx.Error('unknown type "' + V.StringValue + '"');
  end
  else if V.Kind = jkArray then
  begin
    if V.Count = 0 then
      Ctx.Error('"type" must not be an empty array');
    if not AllStrings(V) then
      Ctx.Error('every entry of "type" must be a string')
    else
    begin
      for I := 0 to V.Count - 1 do
        if not Ctx.IsKnownType(V[I].StringValue) then
          Ctx.Error('unknown type "' + V[I].StringValue + '"');
      if HasDuplicateStrings(V) then
        Ctx.Error('"type" must not contain duplicates');
    end;
  end
  else
    Ctx.Error('"type" must be a string or an array of strings');
end;

procedure CheckString(Ctx: TCompileContext);
begin
  if Ctx.KeywordValue.Kind <> jkString then
    Ctx.Error('"' + Ctx.Keyword + '" must be a string');
end;

procedure CheckBoolean(Ctx: TCompileContext);
begin
  if Ctx.KeywordValue.Kind <> jkBoolean then
    Ctx.Error('"' + Ctx.Keyword + '" must be a boolean');
end;

procedure CheckNumber(Ctx: TCompileContext);
begin
  if Ctx.KeywordValue.Kind <> jkNumber then
    Ctx.Error('"' + Ctx.Keyword + '" must be a number');
end;

procedure CheckPositiveNumber(Ctx: TCompileContext);
begin
  if (Ctx.KeywordValue.Kind <> jkNumber) or (Ctx.KeywordValue.NumberValue <= 0) then
    Ctx.Error('"' + Ctx.Keyword + '" must be a number greater than 0');
end;

procedure CheckNonNegativeInteger(Ctx: TCompileContext);
begin
  if not IsNonNegInt(Ctx.KeywordValue) then
    Ctx.Error('"' + Ctx.Keyword + '" must be a non-negative integer');
end;

procedure CheckArray(Ctx: TCompileContext);
begin
  if Ctx.KeywordValue.Kind <> jkArray then
    Ctx.Error('"' + Ctx.Keyword + '" must be an array');
end;

procedure CheckEnumLegacy(Ctx: TCompileContext);
begin
  if Ctx.KeywordValue.Kind <> jkArray then
    Ctx.Error('"enum" must be an array')
  else if Ctx.KeywordValue.Count = 0 then
    Ctx.Error('"enum" must contain at least one value');
end;

procedure CheckPatternValue(Ctx: TCompileContext);
begin
  if Ctx.KeywordValue.Kind <> jkString then
    Ctx.Error('"pattern" must be a string')
  else
    Ctx.CheckPattern(Ctx.KeywordValue.StringValue);
end;

procedure CheckRequired(Ctx: TCompileContext);
begin
  if Ctx.KeywordValue.Kind <> jkArray then
    Ctx.Error('"required" must be an array of strings')
  else if not AllStrings(Ctx.KeywordValue) then
    Ctx.Error('every entry of "required" must be a string')
  else if HasDuplicateStrings(Ctx.KeywordValue) then
    Ctx.Error('"required" must not contain duplicates');
end;

procedure CheckRequiredLegacy(Ctx: TCompileContext);
begin
  CheckRequired(Ctx);
  if (Ctx.KeywordValue.Kind = jkArray) and (Ctx.KeywordValue.Count = 0) then
    Ctx.Error('"required" must contain at least one property name in this draft');
end;

procedure CheckSchema(Ctx: TCompileContext);
begin
  Ctx.CompileSubschema(Ctx.KeywordValue);
end;

procedure CheckSchemaArray(Ctx: TCompileContext);
var
  V: TJSONValue;
  I: Integer;
begin
  V := Ctx.KeywordValue;
  if V.Kind <> jkArray then
  begin
    Ctx.Error('"' + Ctx.Keyword + '" must be an array of schemas');
    Exit;
  end;
  if V.Count = 0 then
    Ctx.Error('"' + Ctx.Keyword + '" must contain at least one schema');
  for I := 0 to V.Count - 1 do
    Ctx.CompileChild(V[I], IntToStr(I));
end;

procedure CheckSchemaMap(Ctx: TCompileContext);
var
  V: TJSONValue;
  I: Integer;
begin
  V := Ctx.KeywordValue;
  if V.Kind <> jkObject then
  begin
    Ctx.Error('"' + Ctx.Keyword + '" must be an object whose values are schemas');
    Exit;
  end;
  for I := 0 to V.Count - 1 do
    Ctx.CompileChild(V[I], V.Names[I]);
end;

procedure CheckPatternMap(Ctx: TCompileContext);
var
  V: TJSONValue;
  I: Integer;
begin
  V := Ctx.KeywordValue;
  if V.Kind <> jkObject then
  begin
    Ctx.Error('"' + Ctx.Keyword + '" must be an object whose values are schemas');
    Exit;
  end;
  for I := 0 to V.Count - 1 do
  begin
    Ctx.CheckPattern(V.Names[I]);
    Ctx.CompileChild(V[I], V.Names[I]);
  end;
end;

procedure CheckItems(Ctx: TCompileContext);
var
  V: TJSONValue;
  I: Integer;
begin
  V := Ctx.KeywordValue;
  if V.Kind = jkArray then
    for I := 0 to V.Count - 1 do
      Ctx.CompileChild(V[I], IntToStr(I))
  else
    Ctx.CompileSubschema(V);
end;

procedure CheckDependencies(Ctx: TCompileContext);
var
  V: TJSONValue;
  I: Integer;
begin
  V := Ctx.KeywordValue;
  if V.Kind <> jkObject then
  begin
    Ctx.Error('"' + Ctx.Keyword + '" must be an object');
    Exit;
  end;
  for I := 0 to V.Count - 1 do
    if V[I].Kind = jkArray then
    begin
      if not AllStrings(V[I]) then
        Ctx.Error('dependency "' + V.Names[I] + '" must list property names (strings)');
    end
    else
      Ctx.CompileChild(V[I], V.Names[I]);
end;

procedure CheckDependentRequired(Ctx: TCompileContext);
var
  V: TJSONValue;
  I: Integer;
begin
  V := Ctx.KeywordValue;
  if V.Kind <> jkObject then
  begin
    Ctx.Error('"dependentRequired" must be an object');
    Exit;
  end;
  for I := 0 to V.Count - 1 do
    if (V[I].Kind <> jkArray) or not AllStrings(V[I]) then
      Ctx.Error('"dependentRequired" entry "' + V.Names[I] + '" must be an array of strings');
end;

procedure CheckExclusiveMinimumD4(Ctx: TCompileContext);
begin
  if Ctx.KeywordValue.Kind <> jkBoolean then
    Ctx.Error('"exclusiveMinimum" must be a boolean in this draft')
  else if Ctx.Sibling('minimum') = nil then
    Ctx.Error('"exclusiveMinimum" requires "minimum"');
end;

procedure CheckExclusiveMaximumD4(Ctx: TCompileContext);
begin
  if Ctx.KeywordValue.Kind <> jkBoolean then
    Ctx.Error('"exclusiveMaximum" must be a boolean in this draft')
  else if Ctx.Sibling('maximum') = nil then
    Ctx.Error('"exclusiveMaximum" requires "maximum"');
end;

procedure CheckRef(Ctx: TCompileContext);
begin
  if Ctx.KeywordValue.Kind <> jkString then
    Ctx.Error('"$ref" must be a string')
  else
    Ctx.RegisterRef(Ctx.KeywordValue);
end;

procedure CheckAnchor(Ctx: TCompileContext);
var
  S: string;
  I: Integer;
  Ok: Boolean;
begin
  if Ctx.KeywordValue.Kind <> jkString then
  begin
    Ctx.Error('"$anchor" must be a string');
    Exit;
  end;
  S := Ctx.KeywordValue.StringValue;
  Ok := (S <> '') and (IsLetterChar(S[1]) or (S[1] = '_'));
  for I := 2 to Length(S) do
    if not (IsLetterChar(S[I]) or IsDigitChar(S[I]) or (S[I] = '_') or (S[I] = '-')
      or (S[I] = '.')) then
      Ok := False;
  if Ok then
    Ctx.DeclareAnchor(S)
  else
    Ctx.Error('"$anchor" must start with a letter or "_" and contain only letters, digits, "-", "_" and "."');
end;

end.
