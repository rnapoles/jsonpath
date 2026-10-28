{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit JSONPathLexer;

{ Lexical layer for the RFC 9535 JSONPath parser.

  The lexer is scannerless: it tracks FInput / FPos / FLen and offers lookahead
  primitives (PeekChar, ConsumeChar, MatchToken) plus the lexical productions
  of the ABNF (int, number, string-literal, member-name-shorthand, ...).
  The grammar-level productions live in JSONPathParser.

  FPos is a 1-based string index; the public Position/Line/Column values
  reported in exceptions are 0-based offset, 1-based line, 1-based column. }

interface

uses
  SysUtils, Classes, JSONPathCommon;

type
  EJSONPathParseException = class(Exception)
  private
    FPosition: Integer;
    FLine: Integer;
    FColumn: Integer;
    FUnexpectedToken: string;
    FRuleName: string;
  public
    constructor CreateAt(const AMessage, ARuleName, AToken: string;
      APosition, ALine, AColumn: Integer);
    { 0-based character offset into the query text }
    property Position: Integer read FPosition;
    property Line: Integer read FLine;
    property Column: Integer read FColumn;
    { The offending text ('<end of input>' when the query ended early) }
    property UnexpectedToken: string read FUnexpectedToken;
    { The ABNF production that was being matched }
    property RuleName: string read FRuleName;
  end;

  TJSONPathLexer = class
  private
    FInput: string;
    FPos: Integer;
    FLen: Integer;
    procedure ScanEscape(Quote: Char; var Dest: string);
    function ScanHex4: Cardinal;
  public
    constructor Create(const AInput: string);

    { lookahead primitives }
    function IsAtEnd: Boolean;
    function PeekChar: Char;
    function PeekCharAt(Offset: Integer): Char;
    function ConsumeChar: Char;
    function MatchChar(C: Char): Boolean;
    function LookingAt(const Token: string): Boolean;
    function MatchToken(const Token: string): Boolean;
    procedure ExpectChar(C: Char; const RuleName: string);
    procedure SkipWhitespace;
    function Mark: Integer;
    procedure Reset(AMark: Integer);

    { character classes }
    class function IsDigit(C: Char): Boolean;
    class function IsNameFirst(C: Char): Boolean;
    class function IsNameChar(C: Char): Boolean;
    class function IsLowerAlpha(C: Char): Boolean;

    { lexical productions }
    function ScanInt(const RuleName: string): Int64;
    function ScanNumberLiteral: Double;
    function ScanStringLiteral: string;
    function ScanNameShorthand: string;
    function ScanFunctionName: string;

    { errors }
    procedure Fail(const RuleName, AMessage: string);
    procedure FailAt(APos: Integer; const RuleName, AMessage: string);

    property Input: string read FInput;
  end;

implementation

{ EJSONPathParseException }

constructor EJSONPathParseException.CreateAt(const AMessage, ARuleName, AToken: string;
  APosition, ALine, AColumn: Integer);
begin
  inherited Create(Format('JSONPath syntax error at line %d, column %d (offset %d) in rule "%s": %s [near %s]',
    [ALine, AColumn, APosition, ARuleName, AMessage, AToken]));
  FPosition := APosition;
  FLine := ALine;
  FColumn := AColumn;
  FUnexpectedToken := AToken;
  FRuleName := ARuleName;
end;

{ TJSONPathLexer }

constructor TJSONPathLexer.Create(const AInput: string);
begin
  inherited Create;
  FInput := AInput;
  FLen := Length(AInput);
  FPos := 1;
end;

function TJSONPathLexer.IsAtEnd: Boolean;
begin
  Result := FPos > FLen;
end;

function TJSONPathLexer.PeekChar: Char;
begin
  if FPos <= FLen then
    Result := FInput[FPos]
  else
    Result := #0;
end;

function TJSONPathLexer.PeekCharAt(Offset: Integer): Char;
begin
  if (FPos + Offset >= 1) and (FPos + Offset <= FLen) then
    Result := FInput[FPos + Offset]
  else
    Result := #0;
end;

function TJSONPathLexer.ConsumeChar: Char;
begin
  Result := PeekChar;
  if FPos <= FLen then
    Inc(FPos);
end;

function TJSONPathLexer.MatchChar(C: Char): Boolean;
begin
  Result := (FPos <= FLen) and (FInput[FPos] = C);
  if Result then
    Inc(FPos);
end;

function TJSONPathLexer.LookingAt(const Token: string): Boolean;
begin
  Result := Copy(FInput, FPos, Length(Token)) = Token;
end;

function TJSONPathLexer.MatchToken(const Token: string): Boolean;
begin
  Result := LookingAt(Token);
  if Result then
    Inc(FPos, Length(Token));
end;

procedure TJSONPathLexer.ExpectChar(C: Char; const RuleName: string);
begin
  if not MatchChar(C) then
    Fail(RuleName, '"' + C + '" expected');
end;

procedure TJSONPathLexer.SkipWhitespace;
begin
  while (FPos <= FLen) and
    ((FInput[FPos] = ' ') or (FInput[FPos] = #9) or (FInput[FPos] = #10) or (FInput[FPos] = #13)) do
    Inc(FPos);
end;

function TJSONPathLexer.Mark: Integer;
begin
  Result := FPos;
end;

procedure TJSONPathLexer.Reset(AMark: Integer);
begin
  FPos := AMark;
end;

class function TJSONPathLexer.IsDigit(C: Char): Boolean;
begin
  Result := (C >= '0') and (C <= '9');
end;

class function TJSONPathLexer.IsLowerAlpha(C: Char): Boolean;
begin
  Result := (C >= 'a') and (C <= 'z');
end;

class function TJSONPathLexer.IsNameFirst(C: Char): Boolean;
begin
  { ALPHA / "_" / %x80-D7FF / %xE000-10FFFF. Under UTF-8 (FPC) every byte
    >= $80 belongs to such a code point; under UTF-16 (Delphi) surrogate
    halves of supplementary characters are accepted the same way. }
  Result := ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z'))
    or (C = '_') or (Ord(C) >= $80);
end;

class function TJSONPathLexer.IsNameChar(C: Char): Boolean;
begin
  Result := IsNameFirst(C) or IsDigit(C);
end;

procedure TJSONPathLexer.Fail(const RuleName, AMessage: string);
begin
  FailAt(FPos, RuleName, AMessage);
end;

procedure TJSONPathLexer.FailAt(APos: Integer; const RuleName, AMessage: string);
var
  I, Line, LineStart: Integer;
  Token: string;
begin
  if APos < 1 then
    APos := 1;
  if APos > FLen + 1 then
    APos := FLen + 1;
  Line := 1;
  LineStart := 1;
  for I := 1 to APos - 1 do
    if FInput[I] = #10 then
    begin
      Inc(Line);
      LineStart := I + 1;
    end;
  if APos > FLen then
    Token := '<end of input>'
  else
    Token := '"' + Copy(FInput, APos, 1) + '"';
  raise EJSONPathParseException.CreateAt(AMessage, RuleName, Token,
    APos - 1, Line, APos - LineStart + 1);
end;

function TJSONPathLexer.ScanInt(const RuleName: string): Int64;
var
  Negative: Boolean;
  Digits: Integer;
  StartPos: Integer;
begin
  StartPos := FPos;
  Negative := MatchChar('-');
  if not IsDigit(PeekChar) then
    FailAt(FPos, RuleName, 'digit expected');
  if PeekChar = '0' then
  begin
    Inc(FPos);
    if IsDigit(PeekChar) then
      FailAt(StartPos, RuleName, 'leading zeros are not allowed');
    if Negative then
      FailAt(StartPos, RuleName, '"-0" is not a valid integer');
    Result := 0;
    Exit;
  end;
  Result := 0;
  Digits := 0;
  while IsDigit(PeekChar) do
  begin
    Inc(Digits);
    if Digits > 16 then
      FailAt(StartPos, RuleName, 'integer out of range');
    Result := Result * 10 + (Ord(PeekChar) - Ord('0'));
    Inc(FPos);
  end;
  if Result > JSONPATH_MAX_INT then
    FailAt(StartPos, RuleName, 'integer out of range');
  if Negative then
    Result := -Result;
end;

function TJSONPathLexer.ScanNumberLiteral: Double;
var
  StartPos: Integer;
  Value: Double;
begin
  StartPos := FPos;
  MatchChar('-');
  if PeekChar = '0' then
  begin
    Inc(FPos);
    if IsDigit(PeekChar) then
      FailAt(StartPos, 'number', 'leading zeros are not allowed');
  end
  else if IsDigit(PeekChar) then
  begin
    while IsDigit(PeekChar) do
      Inc(FPos);
  end
  else
    FailAt(FPos, 'number', 'digit expected');
  if PeekChar = '.' then
  begin
    Inc(FPos);
    if not IsDigit(PeekChar) then
      FailAt(FPos, 'frac', 'digit expected after decimal point');
    while IsDigit(PeekChar) do
      Inc(FPos);
  end;
  if (PeekChar = 'e') or (PeekChar = 'E') then
  begin
    Inc(FPos);
    if (PeekChar = '+') or (PeekChar = '-') then
      Inc(FPos);
    if not IsDigit(PeekChar) then
      FailAt(FPos, 'exp', 'digit expected in exponent');
    while IsDigit(PeekChar) do
      Inc(FPos);
  end;
  if not TryJSONTextToDouble(Copy(FInput, StartPos, FPos - StartPos), Value) then
    FailAt(StartPos, 'number', 'invalid number');
  Result := Value;
end;

function TJSONPathLexer.ScanHex4: Cardinal;
var
  I, D: Integer;
begin
  Result := 0;
  for I := 1 to 4 do
  begin
    D := HexDigitValue(PeekChar);
    if IsAtEnd or (D < 0) then
      Fail('hexchar', 'four hexadecimal digits expected after \u');
    Result := (Result shl 4) or Cardinal(D);
    Inc(FPos);
  end;
end;

procedure TJSONPathLexer.ScanEscape(Quote: Char; var Dest: string);
var
  C: Char;
  CP, LowSur: Cardinal;
  EscStart: Integer;
begin
  { FPos is just after the backslash }
  EscStart := FPos - 1;
  if IsAtEnd then
    FailAt(FPos, 'escapable', 'unterminated escape sequence');
  C := ConsumeChar;
  case C of
    'b': Dest := Dest + #8;
    'f': Dest := Dest + #12;
    'n': Dest := Dest + #10;
    'r': Dest := Dest + #13;
    't': Dest := Dest + #9;
    '/': Dest := Dest + '/';
    '\': Dest := Dest + '\';
    '"':
      if Quote = '"' then
        Dest := Dest + '"'
      else
        FailAt(EscStart, 'escapable', 'escaped double quote is not allowed in a single-quoted string');
    '''':
      if Quote = '''' then
        Dest := Dest + ''''
      else
        FailAt(EscStart, 'escapable', 'escaped single quote is not allowed in a double-quoted string');
    'u':
      begin
        CP := ScanHex4;
        if (CP >= $D800) and (CP <= $DBFF) then
        begin
          if LookingAt('\u') then
          begin
            Inc(FPos, 2);
            LowSur := ScanHex4;
            if (LowSur < $DC00) or (LowSur > $DFFF) then
              FailAt(EscStart, 'hexchar', 'high surrogate must be followed by a low surrogate');
            CP := $10000 + ((CP - $D800) shl 10) + (LowSur - $DC00);
          end
          else
            FailAt(EscStart, 'hexchar', 'lone high surrogate');
        end
        else if (CP >= $DC00) and (CP <= $DFFF) then
          FailAt(EscStart, 'hexchar', 'lone low surrogate');
        AppendCodePoint(Dest, CP);
      end;
  else
    FailAt(EscStart, 'escapable', 'invalid escape sequence');
  end;
end;

function TJSONPathLexer.ScanStringLiteral: string;
var
  Quote, C: Char;
  StartPos: Integer;
begin
  StartPos := FPos;
  Quote := ConsumeChar;
  Result := '';
  while True do
  begin
    if IsAtEnd then
      FailAt(StartPos, 'string-literal', 'unterminated string literal');
    C := PeekChar;
    if C = Quote then
    begin
      Inc(FPos);
      Break;
    end
    else if C = '\' then
    begin
      Inc(FPos);
      ScanEscape(Quote, Result);
    end
    else
    begin
      if Ord(C) < $20 then
        FailAt(FPos, 'string-literal', 'control characters must be escaped');
      Result := Result + C;
      Inc(FPos);
    end;
  end;
end;

function TJSONPathLexer.ScanNameShorthand: string;
var
  StartPos: Integer;
begin
  StartPos := FPos;
  if IsAtEnd or not IsNameFirst(PeekChar) then
    Fail('member-name-shorthand', 'member name expected (letter, "_" or non-ASCII character)');
  while (not IsAtEnd) and IsNameChar(PeekChar) do
    Inc(FPos);
  Result := Copy(FInput, StartPos, FPos - StartPos);
end;

function TJSONPathLexer.ScanFunctionName: string;
var
  StartPos: Integer;
  C: Char;
begin
  StartPos := FPos;
  if IsAtEnd or not IsLowerAlpha(PeekChar) then
    Fail('function-name', 'function name must start with a lowercase letter');
  while not IsAtEnd do
  begin
    C := PeekChar;
    if IsLowerAlpha(C) or (C = '_') or IsDigit(C) then
      Inc(FPos)
    else
      Break;
  end;
  Result := Copy(FInput, StartPos, FPos - StartPos);
end;

end.
