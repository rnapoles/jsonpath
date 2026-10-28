{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit JsonSchemaRegex;

{ Regular expressions for the "pattern" and "patternProperties" keywords.

  JSON Schema patterns are ECMA 262 expressions with search semantics. The
  only engine in this code base is the I-Regexp matcher of JSONPathRegex,
  which has no anchors and no \d \w \s. This unit translates the commonly
  used ECMA subset into that dialect and runs it with anchored/unanchored
  search:

    supported   ^ at the very start, $ at the very end, \d \D \w \W \s \S
                (also inside [...] except the negated forms), (?: ... ),
                lazy quantifiers (treated as greedy: same yes/no answer),
                escaped punctuation, literals, ., [...], groups, |, * + ?
                and counted repeats
    unsupported ^ or $ anywhere else, \b \B, back-references, \p and \P,
                \u and \x escapes, lookahead/lookbehind, named groups

  Unsupported patterns raise EJsonSchemaRegexError; the schema compiler turns
  that into a schema error so nothing is silently ignored. }

interface

uses
  SysUtils, Classes, JSONPathCommon, JSONPathRegex, JsonSchemaErrors;

type
  EJsonSchemaRegexError = class(Exception);

  TSchemaRegex = class
  private
    FRegex: TIRegexp;
    FAnchorStart: Boolean;
    FAnchorEnd: Boolean;
  public
    { Raises EJsonSchemaRegexError for unsupported or invalid patterns }
    constructor Create(const AEcmaPattern: string);
    destructor Destroy; override;
    function Search(const AText: string): Boolean;
  end;

  { Compiles each distinct pattern once }
  TSchemaRegexCache = class
  private
    FPatterns: TStringArray;
    FMessages: TStringArray;
    FCount: Integer;
    FItems: TOwnedList;
    function IndexOf(const APattern: string): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    { Returns nil and sets AErrorMessage when the pattern is not usable }
    function Get(const APattern: string; out AErrorMessage: string): TSchemaRegex;
    function Search(const APattern, AText: string): Boolean;
  end;

{ Exposed for tests: the I-Regexp text produced for an ECMA pattern }
function TranslateEcmaPattern(const APattern: string; out AAnchorStart,
  AAnchorEnd: Boolean): string;

implementation

procedure RegexFail(const AMessage: string);
begin
  raise EJsonSchemaRegexError.Create(AMessage);
end;

function IsAlnum(C: Char): Boolean;
begin
  Result := ((C >= '0') and (C <= '9')) or ((C >= 'a') and (C <= 'z'))
    or ((C >= 'A') and (C <= 'Z'));
end;

function IsEscapable(C: Char): Boolean;
begin
  { characters that I-Regexp lets a backslash protect }
  Result := (C = '(') or (C = ')') or (C = '*') or (C = '+') or (C = '-')
    or (C = '.') or (C = '?') or (C = '[') or (C = '\') or (C = ']')
    or (C = '^') or (C = '{') or (C = '|') or (C = '}');
end;

function TranslateEcmaPattern(const APattern: string; out AAnchorStart,
  AAnchorEnd: Boolean): string;
var
  I, N: Integer;
  C, D: Char;
  InClass: Boolean;
begin
  Result := '';
  AAnchorStart := False;
  AAnchorEnd := False;
  InClass := False;
  N := Length(APattern);
  I := 1;
  while I <= N do
  begin
    C := APattern[I];
    if C = '\' then
    begin
      if I = N then
        RegexFail('the pattern ends with a lone backslash');
      D := APattern[I + 1];
      Inc(I, 2);
      case D of
        'd':
          if InClass then Result := Result + '0-9' else Result := Result + '[0-9]';
        'w':
          if InClass then Result := Result + 'a-zA-Z0-9_'
          else Result := Result + '[a-zA-Z0-9_]';
        's':
          if InClass then Result := Result + ' \t\n\r'
          else Result := Result + '[ \t\n\r]';
        'D', 'W', 'S':
          begin
            if InClass then
              RegexFail('negated class escapes inside [...] are not supported');
            if D = 'D' then Result := Result + '[^0-9]'
            else if D = 'W' then Result := Result + '[^a-zA-Z0-9_]'
            else Result := Result + '[^ \t\n\r]';
          end;
        'n', 'r', 't':
          Result := Result + '\' + D;
      else
        if IsAlnum(D) then
          RegexFail('the escape \' + D + ' is not supported')
        else if IsEscapable(D) then
          Result := Result + '\' + D
        else
          Result := Result + D;
      end;
      Continue;
    end;
    if InClass then
    begin
      if C = ']' then
        InClass := False;
      Result := Result + C;
      Inc(I);
      Continue;
    end;
    case C of
      '[':
        begin
          InClass := True;
          Result := Result + C;
        end;
      '(':
        begin
          if (I < N) and (APattern[I + 1] = '?') then
          begin
            if (I + 2 <= N) and (APattern[I + 2] = ':') then
            begin
              Result := Result + '(';
              Inc(I, 2);
            end
            else
              RegexFail('lookaround and named groups are not supported');
          end
          else
            Result := Result + '(';
        end;
      '^':
        if I = 1 then
          AAnchorStart := True
        else
          RegexFail('"^" is only supported at the start of the pattern');
      '$':
        if I = N then
          AAnchorEnd := True
        else
          RegexFail('"$" is only supported at the end of the pattern');
      '*', '+', '?', '}':
        begin
          Result := Result + C;
          { lazy quantifier: same match/no-match answer as the greedy one }
          if (I < N) and (APattern[I + 1] = '?') then
            Inc(I);
        end;
    else
      Result := Result + C;
    end;
    Inc(I);
  end;
end;

{ TSchemaRegex }

constructor TSchemaRegex.Create(const AEcmaPattern: string);
var
  Translated: string;
begin
  inherited Create;
  Translated := TranslateEcmaPattern(AEcmaPattern, FAnchorStart, FAnchorEnd);
  try
    FRegex := TIRegexp.Create(Translated);
  except
    on E: EJSONPathRegexError do
      RegexFail(E.Message);
  end;
end;

destructor TSchemaRegex.Destroy;
begin
  FRegex.Free;
  inherited Destroy;
end;

function TSchemaRegex.Search(const AText: string): Boolean;
begin
  Result := FRegex.IsFind(AText, FAnchorStart, FAnchorEnd);
end;

{ TSchemaRegexCache }

constructor TSchemaRegexCache.Create;
begin
  inherited Create;
  FItems := TOwnedList.Create;
end;

destructor TSchemaRegexCache.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TSchemaRegexCache.IndexOf(const APattern: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to FCount - 1 do
    if FPatterns[I] = APattern then
    begin
      Result := I;
      Exit;
    end;
end;

function TSchemaRegexCache.Get(const APattern: string;
  out AErrorMessage: string): TSchemaRegex;
var
  Idx: Integer;
  Rx: TSchemaRegex;
  Msg: string;
begin
  AErrorMessage := '';
  Idx := IndexOf(APattern);
  if Idx >= 0 then
  begin
    Result := TSchemaRegex(FItems[Idx]);
    AErrorMessage := FMessages[Idx];
    Exit;
  end;
  Rx := nil;
  Msg := '';
  try
    Rx := TSchemaRegex.Create(APattern);
  except
    on E: EJsonSchemaRegexError do
      Msg := E.Message;
  end;
  if FCount >= Length(FPatterns) then
  begin
    SetLength(FPatterns, FCount * 2 + 8);
    SetLength(FMessages, FCount * 2 + 8);
  end;
  FPatterns[FCount] := APattern;
  FMessages[FCount] := Msg;
  Inc(FCount);
  FItems.Add(Rx); { nil caches "invalid pattern" }
  Result := Rx;
  AErrorMessage := Msg;
end;

function TSchemaRegexCache.Search(const APattern, AText: string): Boolean;
var
  Rx: TSchemaRegex;
  Msg: string;
begin
  Rx := Get(APattern, Msg);
  Result := (Rx <> nil) and Rx.Search(AText);
end;

end.
