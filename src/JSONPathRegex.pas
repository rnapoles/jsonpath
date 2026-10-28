{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit JSONPathRegex;

(* Small dependency-free matcher for I-Regexp (RFC 9485), the regular
  expression dialect used by the JSONPath match() and search() functions.

  Supported: literals, ".", character classes (ranges, negation, escapes),
  groups, alternation, and the quantifiers * + ? {n} {n,} {n,m}.
  Not supported: \p{..} / \P{..} Unicode category escapes. A pattern using
  them raises EJSONPathRegexError, which the query engine treats as "no
  match" (RFC 9535 says an invalid pattern makes match()/search() false).

  Matching is a Thompson NFA simulation, so it runs in O(text * pattern)
  and cannot blow up exponentially. *)

interface

uses
  SysUtils, Classes, JSONPathCommon;

type
  EJSONPathRegexError = class(Exception);

  TRegexClass = record
    Negated: Boolean;
    Count: Integer;
    Lo: array of Cardinal;
    Hi: array of Cardinal;
  end;

  TRegexClassArray = array of TRegexClass;
  TIntArray = array of Integer;

  TRegexInst = record
    Op: Integer;
    X: Integer;
    Y: Integer;
  end;

  TIRegexp = class
  private
    FPattern: TCodePointArray;
    FProg: array of TRegexInst;
    FProgLen: Integer;
    FClasses: TRegexClassArray;
    FClassCount: Integer;
    function Run(const Text: TCodePointArray; AnchorStart, AnchorEnd: Boolean): Boolean;
    function ClassMatches(Index: Integer; C: Cardinal): Boolean;
    procedure AddThread(var List: TIntArray; var Count: Integer;
      var Marks: TIntArray; Pc, Stamp: Integer);
    function Emit(AOp, AX, AY: Integer): Integer;
    { parsing + compilation are fused through a small node tree }
    procedure ParseAndCompile;
  public
    constructor Create(const APattern: string);
    { RFC 9535 match(): the whole text must match }
    function IsMatch(const AText: string): Boolean;
    { RFC 9535 search(): some substring must match }
    function IsSearch(const AText: string): Boolean;
    { Generalisation of IsMatch/IsSearch: when AnchorStart is set the match
      must begin at the first character, when AnchorEnd is set it must end
      at the last one. }
    function IsFind(const AText: string; AnchorStart, AnchorEnd: Boolean): Boolean;
  end;

implementation

const
  OP_CHAR = 0;
  OP_ANY = 1;
  OP_CLASS = 2;
  OP_SPLIT = 3;
  OP_JMP = 4;
  OP_MATCH = 5;

  MAX_PROGRAM = 20000;
  MAX_REPEAT = 1000;

type
  TNodeKind = (nkEmpty, nkChar, nkAny, nkClass, nkConcat, nkAlt, nkRepeat);

  TRNode = class
  public
    Kind: TNodeKind;
    Ch: Cardinal;
    ClassIndex: Integer;
    MinCount: Integer;
    MaxCount: Integer; { -1 = unbounded }
    Kids: TOwnedList;
    constructor Create(AKind: TNodeKind);
    destructor Destroy; override;
  end;

constructor TRNode.Create(AKind: TNodeKind);
begin
  inherited Create;
  Kind := AKind;
  if (AKind = nkConcat) or (AKind = nkAlt) or (AKind = nkRepeat) then
    Kids := TOwnedList.Create;
end;

destructor TRNode.Destroy;
begin
  Kids.Free;
  inherited Destroy;
end;

{ ---- pattern parser (builds TRNode trees) ---- }

type
  TRegexParser = class
  private
    FPat: TCodePointArray;
    FPos: Integer;
    FDepth: Integer;
    procedure Fail(const Msg: string);
    function AtEnd: Boolean;
    function Peek: Cardinal;
    function ParseAlternation: TRNode;
    function ParseBranch: TRNode;
    function ParsePiece: TRNode;
    function ParseAtom: TRNode;
    function ParseEscapeChar: Cardinal;
    procedure ParseCharClass(var Cls: TRegexClass);
    function ParseInteger: Integer;
  public
    ClassTable: TRegexClassArray;
    ClassCount: Integer;
    constructor Create(const APattern: TCodePointArray);
    function ParsePattern: TRNode;
  end;

constructor TRegexParser.Create(const APattern: TCodePointArray);
begin
  inherited Create;
  FPat := APattern;
  FPos := 0;
end;

procedure TRegexParser.Fail(const Msg: string);
begin
  raise EJSONPathRegexError.Create(Msg);
end;

function TRegexParser.AtEnd: Boolean;
begin
  Result := FPos >= Length(FPat);
end;

function TRegexParser.Peek: Cardinal;
begin
  if FPos < Length(FPat) then
    Result := FPat[FPos]
  else
    Result := 0;
end;

function TRegexParser.ParsePattern: TRNode;
var
  Node: TRNode;
begin
  Node := ParseAlternation;
  try
    if not AtEnd then
      Fail('unexpected character in pattern');
    Result := Node;
    Node := nil;
  finally
    Node.Free;
  end;
end;

function TRegexParser.ParseAlternation: TRNode;
var
  Alt, Branch: TRNode;
begin
  Inc(FDepth);
  try
    if FDepth > 200 then
      Fail('pattern nesting too deep');
    Alt := TRNode.Create(nkAlt);
    try
      Branch := ParseBranch;
      Alt.Kids.Add(Branch);
      while (not AtEnd) and (Peek = Ord('|')) do
      begin
        Inc(FPos);
        Branch := ParseBranch;
        Alt.Kids.Add(Branch);
      end;
      Result := Alt;
      Alt := nil;
    finally
      Alt.Free;
    end;
  finally
    Dec(FDepth);
  end;
end;

function TRegexParser.ParseBranch: TRNode;
var
  Seq, Piece: TRNode;
begin
  Seq := TRNode.Create(nkConcat);
  try
    while (not AtEnd) and (Peek <> Ord('|')) and (Peek <> Ord(')')) do
    begin
      Piece := ParsePiece;
      Seq.Kids.Add(Piece);
    end;
    Result := Seq;
    Seq := nil;
  finally
    Seq.Free;
  end;
end;

function TRegexParser.ParseInteger: Integer;
var
  Digits: Integer;
begin
  Result := 0;
  Digits := 0;
  while (not AtEnd) and (Peek >= Ord('0')) and (Peek <= Ord('9')) do
  begin
    Result := Result * 10 + Integer(Peek - Ord('0'));
    Inc(Digits);
    Inc(FPos);
    if Result > MAX_REPEAT then
      Fail('repetition count too large');
  end;
  if Digits = 0 then
    Fail('number expected in quantifier');
end;

function TRegexParser.ParsePiece: TRNode;
var
  Atom, Rep: TRNode;
  C: Cardinal;
  MinC, MaxC: Integer;
begin
  Atom := ParseAtom;
  try
    if not AtEnd then
    begin
      C := Peek;
      MinC := -2;
      MaxC := -2;
      if C = Ord('*') then begin MinC := 0; MaxC := -1; Inc(FPos); end
      else if C = Ord('+') then begin MinC := 1; MaxC := -1; Inc(FPos); end
      else if C = Ord('?') then begin MinC := 0; MaxC := 1; Inc(FPos); end
      else if C = Ord('{') then
      begin
        Inc(FPos);
        MinC := ParseInteger;
        if (not AtEnd) and (Peek = Ord(',')) then
        begin
          Inc(FPos);
          if (not AtEnd) and (Peek = Ord('}')) then
            MaxC := -1
          else
          begin
            MaxC := ParseInteger;
            if MaxC < MinC then
              Fail('invalid repetition range');
          end;
        end
        else
          MaxC := MinC;
        if AtEnd or (Peek <> Ord('}')) then
          Fail('"}" expected');
        Inc(FPos);
      end;
      if MinC <> -2 then
      begin
        Rep := TRNode.Create(nkRepeat);
        Rep.MinCount := MinC;
        Rep.MaxCount := MaxC;
        Rep.Kids.Add(Atom);
        Atom := Rep;
      end;
    end;
    Result := Atom;
    Atom := nil;
  finally
    Atom.Free;
  end;
end;

function TRegexParser.ParseEscapeChar: Cardinal;
var
  C: Cardinal;
begin
  { positioned just after the backslash }
  if AtEnd then
    Fail('incomplete escape');
  C := Peek;
  Inc(FPos);
  case C of
    Ord('n'): Result := 10;
    Ord('r'): Result := 13;
    Ord('t'): Result := 9;
    Ord('('), Ord(')'), Ord('*'), Ord('+'), Ord('-'), Ord('.'), Ord('?'),
    Ord('['), Ord('\'), Ord(']'), Ord('^'), Ord('{'), Ord('|'), Ord('}'):
      Result := C;
  else
    if (C = Ord('p')) or (C = Ord('P')) then
      Fail('Unicode category escapes are not supported')
    else
      Fail('invalid escape');
    Result := 0;
  end;
end;

procedure TRegexParser.ParseCharClass(var Cls: TRegexClass);
var
  Lo, Hi: Cardinal;

  procedure AddRange(ALo, AHi: Cardinal);
  begin
    if Cls.Count >= Length(Cls.Lo) then
    begin
      SetLength(Cls.Lo, Cls.Count * 2 + 4);
      SetLength(Cls.Hi, Cls.Count * 2 + 4);
    end;
    Cls.Lo[Cls.Count] := ALo;
    Cls.Hi[Cls.Count] := AHi;
    Inc(Cls.Count);
  end;

  function ParseClassChar: Cardinal;
  var
    C: Cardinal;
  begin
    if AtEnd then
      Fail('unterminated character class');
    C := Peek;
    Inc(FPos);
    if C = Ord('\') then
      Result := ParseEscapeChar
    else
    begin
      if (C = Ord('[')) then
        Fail('"[" must be escaped inside a character class');
      Result := C;
    end;
  end;

begin
  Cls.Negated := False;
  Cls.Count := 0;
  SetLength(Cls.Lo, 4);
  SetLength(Cls.Hi, 4);
  Inc(FPos); { [ }
  if (not AtEnd) and (Peek = Ord('^')) then
  begin
    Cls.Negated := True;
    Inc(FPos);
  end;
  { a leading "-" is a literal }
  if (not AtEnd) and (Peek = Ord('-')) then
  begin
    AddRange(Ord('-'), Ord('-'));
    Inc(FPos);
  end;
  while True do
  begin
    if AtEnd then
      Fail('unterminated character class');
    if Peek = Ord(']') then
    begin
      Inc(FPos);
      Break;
    end;
    if Peek = Ord('-') then
    begin
      { only valid as the last element }
      Inc(FPos);
      if AtEnd or (Peek <> Ord(']')) then
        Fail('"-" must be escaped inside a character class');
      AddRange(Ord('-'), Ord('-'));
      Continue;
    end;
    Lo := ParseClassChar;
    Hi := Lo;
    if (not AtEnd) and (Peek = Ord('-')) and (FPos + 1 < Length(FPat))
      and (FPat[FPos + 1] <> Ord(']')) then
    begin
      Inc(FPos);
      Hi := ParseClassChar;
      if Hi < Lo then
        Fail('invalid character range');
    end;
    AddRange(Lo, Hi);
  end;
  if Cls.Count = 0 then
    Fail('empty character class');
end;

function TRegexParser.ParseAtom: TRNode;
var
  C: Cardinal;
  Node, Inner: TRNode;
  Cls: TRegexClass;
begin
  if AtEnd then
    Fail('atom expected');
  C := Peek;
  if C = Ord('(') then
  begin
    Inc(FPos);
    Inner := ParseAlternation;
    try
      if AtEnd or (Peek <> Ord(')')) then
        Fail('")" expected');
      Inc(FPos);
      Result := Inner;
      Inner := nil;
    finally
      Inner.Free;
    end;
    Exit;
  end;
  if C = Ord('.') then
  begin
    Inc(FPos);
    Result := TRNode.Create(nkAny);
    Exit;
  end;
  if C = Ord('[') then
  begin
    ParseCharClass(Cls);
    if ClassCount >= Length(ClassTable) then
      SetLength(ClassTable, ClassCount * 2 + 4);
    ClassTable[ClassCount] := Cls;
    Result := TRNode.Create(nkClass);
    Result.ClassIndex := ClassCount;
    Inc(ClassCount);
    Exit;
  end;
  if C = Ord('\') then
  begin
    Inc(FPos);
    Node := TRNode.Create(nkChar);
    try
      Node.Ch := ParseEscapeChar;
      Result := Node;
      Node := nil;
    finally
      Node.Free;
    end;
    Exit;
  end;
  case C of
    Ord('*'), Ord('+'), Ord('?'), Ord('{'), Ord('}'), Ord(')'), Ord(']'), Ord('|'):
      Fail('unexpected metacharacter');
  end;
  Inc(FPos);
  Result := TRNode.Create(nkChar);
  Result.Ch := C;
end;

{ ---- compiler ---- }

function TIRegexp.Emit(AOp, AX, AY: Integer): Integer;
begin
  if FProgLen >= MAX_PROGRAM then
    raise EJSONPathRegexError.Create('pattern too complex');
  if FProgLen >= Length(FProg) then
    SetLength(FProg, FProgLen * 2 + 16);
  FProg[FProgLen].Op := AOp;
  FProg[FProgLen].X := AX;
  FProg[FProgLen].Y := AY;
  Result := FProgLen;
  Inc(FProgLen);
end;

procedure TIRegexp.ParseAndCompile;
var
  Parser: TRegexParser;
  Root: TRNode;

  procedure Gen(Node: TRNode);
  var
    I, K, Split, JmpAt, Start: Integer;
    Jumps: array of Integer;
    Splits: array of Integer;
  begin
    case Node.Kind of
      nkEmpty: ;
      nkChar: Emit(OP_CHAR, Integer(Node.Ch), 0);
      nkAny: Emit(OP_ANY, 0, 0);
      nkClass: Emit(OP_CLASS, Node.ClassIndex, 0);
      nkConcat:
        for I := 0 to Node.Kids.Count - 1 do
          Gen(TRNode(Node.Kids[I]));
      nkAlt:
        if Node.Kids.Count = 1 then
          Gen(TRNode(Node.Kids[0]))
        else
        begin
          SetLength(Jumps, Node.Kids.Count);
          K := 0;
          for I := 0 to Node.Kids.Count - 2 do
          begin
            Split := Emit(OP_SPLIT, 0, 0);
            FProg[Split].X := FProgLen;
            Gen(TRNode(Node.Kids[I]));
            JmpAt := Emit(OP_JMP, 0, 0);
            Jumps[K] := JmpAt;
            Inc(K);
            FProg[Split].Y := FProgLen;
          end;
          Gen(TRNode(Node.Kids[Node.Kids.Count - 1]));
          for I := 0 to K - 1 do
            FProg[Jumps[I]].X := FProgLen;
        end;
      nkRepeat:
        begin
          for I := 1 to Node.MinCount do
            Gen(TRNode(Node.Kids[0]));
          if Node.MaxCount < 0 then
          begin
            Start := Emit(OP_SPLIT, 0, 0);
            FProg[Start].X := FProgLen;
            Gen(TRNode(Node.Kids[0]));
            Emit(OP_JMP, Start, 0);
            FProg[Start].Y := FProgLen;
          end
          else
          begin
            SetLength(Splits, Node.MaxCount - Node.MinCount);
            for I := 0 to Node.MaxCount - Node.MinCount - 1 do
            begin
              Split := Emit(OP_SPLIT, 0, 0);
              FProg[Split].X := FProgLen;
              Splits[I] := Split;
              Gen(TRNode(Node.Kids[0]));
            end;
            for I := 0 to High(Splits) do
              FProg[Splits[I]].Y := FProgLen;
          end;
        end;
    end;
  end;

begin
  Parser := TRegexParser.Create(FPattern);
  try
    Root := Parser.ParsePattern;
    try
      FClasses := Parser.ClassTable;
      FClassCount := Parser.ClassCount;
      FProgLen := 0;
      Gen(Root);
      Emit(OP_MATCH, 0, 0);
    finally
      Root.Free;
    end;
  finally
    Parser.Free;
  end;
end;

constructor TIRegexp.Create(const APattern: string);
begin
  inherited Create;
  FPattern := StringToCodePoints(APattern);
  ParseAndCompile;
end;

{ ---- matcher ---- }

function TIRegexp.ClassMatches(Index: Integer; C: Cardinal): Boolean;
var
  I: Integer;
  Found: Boolean;
begin
  Found := False;
  for I := 0 to FClasses[Index].Count - 1 do
    if (C >= FClasses[Index].Lo[I]) and (C <= FClasses[Index].Hi[I]) then
    begin
      Found := True;
      Break;
    end;
  Result := Found <> FClasses[Index].Negated;
end;

procedure TIRegexp.AddThread(var List: TIntArray; var Count: Integer;
  var Marks: TIntArray; Pc, Stamp: Integer);
begin
  if Marks[Pc] = Stamp then
    Exit;
  Marks[Pc] := Stamp;
  case FProg[Pc].Op of
    OP_JMP:
      AddThread(List, Count, Marks, FProg[Pc].X, Stamp);
    OP_SPLIT:
      begin
        AddThread(List, Count, Marks, FProg[Pc].X, Stamp);
        AddThread(List, Count, Marks, FProg[Pc].Y, Stamp);
      end;
  else
    List[Count] := Pc;
    Inc(Count);
  end;
end;

function TIRegexp.Run(const Text: TCodePointArray; AnchorStart, AnchorEnd: Boolean): Boolean;
var
  Cur, Nxt, Marks: TIntArray;
  CurCount, NxtCount, Idx, I, Pc, N: Integer;
  C: Cardinal;
  Ok: Boolean;
  Tmp: TIntArray;
begin
  Result := False;
  N := Length(Text);
  SetLength(Cur, FProgLen);
  SetLength(Nxt, FProgLen);
  SetLength(Marks, FProgLen);
  for I := 0 to FProgLen - 1 do
    Marks[I] := -1;
  CurCount := 0;
  AddThread(Cur, CurCount, Marks, 0, 0);
  for Idx := 0 to N do
  begin
    NxtCount := 0;
    if Idx < N then
      C := Text[Idx]
    else
      C := 0;
    for I := 0 to CurCount - 1 do
    begin
      Pc := Cur[I];
      Ok := False;
      case FProg[Pc].Op of
        OP_MATCH:
          if (not AnchorEnd) or (Idx = N) then
          begin
            Result := True;
            Exit;
          end;
        OP_CHAR:
          Ok := (Idx < N) and (C = Cardinal(FProg[Pc].X));
        OP_ANY:
          Ok := (Idx < N) and (C <> 10) and (C <> 13);
        OP_CLASS:
          Ok := (Idx < N) and ClassMatches(FProg[Pc].X, C);
      else
        Ok := False;
      end;
      if (FProg[Pc].Op <> OP_MATCH) and Ok then
        AddThread(Nxt, NxtCount, Marks, Pc + 1, Idx + 1);
    end;
    { for substring search a new attempt may start at every position }
    if (not AnchorStart) and (Idx < N) then
      AddThread(Nxt, NxtCount, Marks, 0, Idx + 1);
    Tmp := Cur;
    Cur := Nxt;
    Nxt := Tmp;
    CurCount := NxtCount;
  end;
end;

function TIRegexp.IsMatch(const AText: string): Boolean;
begin
  Result := Run(StringToCodePoints(AText), True, True);
end;

function TIRegexp.IsFind(const AText: string; AnchorStart, AnchorEnd: Boolean): Boolean;
begin
  Result := Run(StringToCodePoints(AText), AnchorStart, AnchorEnd);
end;

function TIRegexp.IsSearch(const AText: string): Boolean;
begin
  Result := Run(StringToCodePoints(AText), False, False);
end;

end.
