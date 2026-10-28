{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit JSONPathQuery;

{ Evaluates a parsed RFC 9535 JSONPath query against a JSON document.

    Path := TJSONPath.Create('$.store.book[?@.price < 10].title');
    try
      Res := Path.Evaluate(Doc);
      try
        WriteLn(Res.ToJSONText);   // ["Sayings of the Century","Moby Dick"]
        WriteLn(Res.Paths[0]);     // $['store']['book'][0]['title']
      finally
        Res.Free;
      end;
    finally
      Path.Free;
    end;

  Result values point into the queried document: keep the document alive
  for as long as the result is used. }

interface

uses
  SysUtils, Classes, JSONPathCommon, JSONPathJSON, JSONPathRegex,
  JSONPathLexer, JSONPathParser;

type
  TJSONPathResult = class
  private
    FValues: TList;
    FPaths: TStringList;
    function GetCount: Integer;
    function GetValue(Index: Integer): TJSONValue;
    function GetPath(Index: Integer): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(AValue: TJSONValue; const APath: string);
    { Compact JSON array of all selected values }
    function ToJSONText: string;
    { Same array, pretty-printed with a 2-space indent and LF line breaks }
    function JSONToTextPretty: string;
    { Normalized paths (RFC 9535 2.7) joined with ";" }
    function PathsToText: string;
    property Count: Integer read GetCount;
    property Values[Index: Integer]: TJSONValue read GetValue;
    property Paths[Index: Integer]: string read GetPath;
  end;

  TJSONPath = class
  private
    FSource: string;
    FQuery: TJSONPathQueryNode;
  public
    { Raises EJSONPathParseException for invalid or ill-typed queries }
    constructor Create(const AQuery: string);
    destructor Destroy; override;
    { The caller owns the returned result }
    function Evaluate(ARoot: TJSONValue): TJSONPathResult;
    { Shortcuts for JSONPathParser.RegisterJSONPathFunction, e.g.
        TJSONPath.RegisterFunction('upper', [vtValue], vtValue, FnUpper); }
    class procedure RegisterFunction(const AName: string;
      const AParams: array of TJSONPathValueType; AResultType: TJSONPathValueType;
      AHandler: TJSONPathFunctionHandler); overload;
    class procedure RegisterFunction(const AName: string;
      const AParams: array of TJSONPathValueType; AResultType: TJSONPathValueType;
      AHandler: TJSONPathFunctionMethod); overload;
    class function UnregisterFunction(const AName: string): Boolean;
    property Source: string read FSource;
    property Query: TJSONPathQueryNode read FQuery;
  end;

{ One-shot helper: parse + evaluate. The caller owns the result. }
function JSONPathSelect(const AQuery: string; ARoot: TJSONValue): TJSONPathResult;
{ Escapes a member name for use inside a normalized path: ['name'] }
function NormalizedPathEscape(const AName: string): string;

implementation

{ ---- TJSONPathResult ---- }

constructor TJSONPathResult.Create;
begin
  inherited Create;
  FValues := TList.Create;
  FPaths := TStringList.Create;
end;

destructor TJSONPathResult.Destroy;
begin
  FPaths.Free;
  FValues.Free;
  inherited Destroy;
end;

function TJSONPathResult.GetCount: Integer;
begin
  Result := FValues.Count;
end;

function TJSONPathResult.GetValue(Index: Integer): TJSONValue;
begin
  Result := TJSONValue(FValues[Index]);
end;

function TJSONPathResult.GetPath(Index: Integer): string;
begin
  Result := FPaths[Index];
end;

procedure TJSONPathResult.Add(AValue: TJSONValue; const APath: string);
begin
  FValues.Add(Pointer(AValue));
  FPaths.Add(APath);
end;

function TJSONPathResult.ToJSONText: string;
var
  I: Integer;
begin
  Result := '[';
  for I := 0 to Count - 1 do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + JSONToText(Values[I]);
  end;
  Result := Result + ']';
end;

function TJSONPathResult.JSONToTextPretty: string;
const
  IndentWidth = 2;
var
  I: Integer;
  Pad, Item: string;
begin
  if Count = 0 then
  begin
    Result := '[]';
    Exit;
  end;
  Pad := StringOfChar(' ', IndentWidth);
  Result := '[' + #10;
  for I := 0 to Count - 1 do
  begin
    { the unit-qualified call avoids resolving to this method }
    Item := StringReplace(JSONPathJSON.JSONToTextPretty(Values[I], IndentWidth),
      #10, #10 + Pad, [rfReplaceAll]);
    Result := Result + Pad + Item;
    if I < Count - 1 then
      Result := Result + ',';
    Result := Result + #10;
  end;
  Result := Result + ']';
end;

function TJSONPathResult.PathsToText: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Count - 1 do
  begin
    if I > 0 then
      Result := Result + ';';
    Result := Result + Paths[I];
  end;
end;

{ ---- normalized paths ---- }

function NormalizedPathEscape(const AName: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(AName) do
  begin
    C := AName[I];
    case C of
      '''': Result := Result + '\''';
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
end;

{ ---- evaluation machinery ---- }

type
  TJPNode = class
  public
    Value: TJSONValue;
    Parent: TJPNode;
    IsIndex: Boolean;
    Index: Integer;
    Name: string;
  end;

  TJPNodeList = class
  private
    FItems: TList;
    function GetCount: Integer;
    function GetNode(Index: Integer): TJPNode;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(ANode: TJPNode);
    property Count: Integer read GetCount;
    property Nodes[Index: Integer]: TJPNode read GetNode; default;
  end;

  TJPResultKind = (rkNothing, rkValue, rkLogical, rkNodes);

  TJPResult = record
    Kind: TJPResultKind;
    Value: TJSONValue;
    Logical: Boolean;
    Nodes: TJPNodeList;
  end;

  TJPEvaluator = class
  private
    FRoot: TJPNode;
    FNodes: TOwnedList;
    FLists: TOwnedList;
    FTemps: TOwnedList;
    FRegexPatterns: array of string;
    FRegexCount: Integer;
    FRegexObjs: TOwnedList;
    function NewNode(AValue: TJSONValue; AParent: TJPNode): TJPNode;
    function NewList: TJPNodeList;
    function MakeChild(Parent: TJPNode; Index: Integer): TJPNode;
    function TempNumber(D: Double): TJSONValue;
    function TempString(const S: string): TJSONValue;
    function TempBool(B: Boolean): TJSONValue;
    function TempNull: TJSONValue;
    function EvalCustom(Call: TJSONPathFunctionCall; Current: TJPNode): TJPResult;
    function GetRegex(const Pattern: string): TIRegexp;
    procedure ApplySelector(Sel: TJSONPathSelector; Node: TJPNode; Output: TJPNodeList);
    procedure ApplySlice(Slice: TJSONPathSlice; Node: TJPNode; Output: TJPNodeList);
    procedure ApplyFilter(Sel: TJSONPathFilterSelector; Node: TJPNode; Output: TJPNodeList);
    procedure ApplySelectors(Seg: TJSONPathSegment; Node: TJPNode; Output: TJPNodeList);
    procedure VisitDescendants(Seg: TJSONPathSegment; Node: TJPNode; Output: TJPNodeList);
    function EvalLogical(Expr: TJSONPathExpression; Current: TJPNode): Boolean;
    function EvalComparable(Expr: TJSONPathExpression; Current: TJPNode): TJPResult;
    function EvalArgument(Arg: TJSONPathExpression; ParamType: TJSONPathValueType;
      Current: TJPNode): TJPResult;
    function EvalFunction(Call: TJSONPathFunctionCall; Current: TJPNode): TJPResult;
    function CompareResults(Op: TJSONPathCompareOp; const L, R: TJPResult): Boolean;
  public
    constructor Create(ARoot: TJSONValue);
    destructor Destroy; override;
    function EvalQuery(Q: TJSONPathQueryNode; Current: TJPNode): TJPNodeList;
    function Run(Q: TJSONPathQueryNode): TJPNodeList;
  end;

function ResNothing: TJPResult;
begin
  Result.Kind := rkNothing;
  Result.Value := nil;
  Result.Logical := False;
  Result.Nodes := nil;
end;

function ResValue(AValue: TJSONValue): TJPResult;
begin
  Result := ResNothing;
  Result.Kind := rkValue;
  Result.Value := AValue;
end;

function ResLogical(AValue: Boolean): TJPResult;
begin
  Result := ResNothing;
  Result.Kind := rkLogical;
  Result.Logical := AValue;
end;

function ResNodes(AList: TJPNodeList): TJPResult;
begin
  Result := ResNothing;
  Result.Kind := rkNodes;
  Result.Nodes := AList;
end;

function NodePath(ANode: TJPNode): string;
var
  N: TJPNode;
begin
  Result := '';
  N := ANode;
  while N.Parent <> nil do
  begin
    if N.IsIndex then
      Result := '[' + IntToStr(N.Index) + ']' + Result
    else
      Result := '[''' + NormalizedPathEscape(N.Name) + ''']' + Result;
    N := N.Parent;
  end;
  Result := '$' + Result;
end;

{ TJPNodeList }

constructor TJPNodeList.Create;
begin
  inherited Create;
  FItems := TList.Create;
end;

destructor TJPNodeList.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TJPNodeList.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TJPNodeList.GetNode(Index: Integer): TJPNode;
begin
  Result := TJPNode(FItems[Index]);
end;

procedure TJPNodeList.Add(ANode: TJPNode);
begin
  FItems.Add(Pointer(ANode));
end;

{ TJPEvaluator }

constructor TJPEvaluator.Create(ARoot: TJSONValue);
begin
  inherited Create;
  FNodes := TOwnedList.Create;
  FLists := TOwnedList.Create;
  FTemps := TOwnedList.Create;
  FRegexObjs := TOwnedList.Create;
  FRoot := NewNode(ARoot, nil);
end;

destructor TJPEvaluator.Destroy;
begin
  FRegexObjs.Free;
  FTemps.Free;
  FLists.Free;
  FNodes.Free;
  inherited Destroy;
end;

function TJPEvaluator.NewNode(AValue: TJSONValue; AParent: TJPNode): TJPNode;
begin
  Result := TJPNode.Create;
  FNodes.Add(Result);
  Result.Value := AValue;
  Result.Parent := AParent;
end;

function TJPEvaluator.NewList: TJPNodeList;
begin
  Result := TJPNodeList.Create;
  FLists.Add(Result);
end;

function TJPEvaluator.MakeChild(Parent: TJPNode; Index: Integer): TJPNode;
begin
  Result := NewNode(Parent.Value[Index], Parent);
  if Parent.Value.Kind = jkArray then
  begin
    Result.IsIndex := True;
    Result.Index := Index;
  end
  else
    Result.Name := Parent.Value.Names[Index];
end;

function TJPEvaluator.TempNumber(D: Double): TJSONValue;
begin
  Result := NewJSONNumber(D);
  FTemps.Add(Result);
end;

function TJPEvaluator.TempString(const S: string): TJSONValue;
begin
  Result := NewJSONString(S);
  FTemps.Add(Result);
end;

function TJPEvaluator.TempBool(B: Boolean): TJSONValue;
begin
  Result := NewJSONBool(B);
  FTemps.Add(Result);
end;

function TJPEvaluator.TempNull: TJSONValue;
begin
  Result := NewJSONNull;
  FTemps.Add(Result);
end;

function TJPEvaluator.EvalCustom(Call: TJSONPathFunctionCall; Current: TJPNode): TJPResult;
var
  Fn: TJSONPathCustomFunction;
  Args: TJSONPathArgs;
  A: TJPResult;
  FR: TJSONPathFuncResult;
  Nodes: array of TJSONValue;
  I, K: Integer;
begin
  Fn := Call.Custom;
  Args := TJSONPathArgs.Create;
  try
    for I := 0 to Call.ArgumentCount - 1 do
    begin
      A := EvalArgument(Call.Arguments[I], Fn.Params[I], Current);
      case Fn.Params[I] of
        vtValue:
          if A.Kind = rkValue then
            Args.AddValue(A.Value)
          else
            Args.AddValue(nil);
        vtLogical:
          Args.AddLogical(A.Logical);
      else
        begin
          SetLength(Nodes, 0);
          if A.Kind = rkNodes then
          begin
            SetLength(Nodes, A.Nodes.Count);
            for K := 0 to A.Nodes.Count - 1 do
              Nodes[K] := A.Nodes[K].Value;
          end;
          Args.AddNodes(Nodes);
        end;
      end;
    end;
    FR := Fn.Invoke(Args);
  finally
    Args.Free;
  end;
  { turn the handler's answer into an evaluator result of the declared type }
  Result := ResNothing;
  if Fn.ResultType = vtLogical then
  begin
    case FR.Kind of
      frLogical, frBool: Result := ResLogical(FR.Bool);
      frValue:
        Result := ResLogical((FR.Value <> nil) and (FR.Value.Kind = jkBoolean)
          and FR.Value.BoolValue);
    else
      Result := ResLogical(False);
    end;
  end
  else
  begin
    case FR.Kind of
      frValue:
        if FR.Value <> nil then
          Result := ResValue(FR.Value);
      frNumber: Result := ResValue(TempNumber(FR.Num));
      frString: Result := ResValue(TempString(FR.Str));
      frBool, frLogical: Result := ResValue(TempBool(FR.Bool));
      frNull: Result := ResValue(TempNull);
    end;
  end;
end;

function TJPEvaluator.GetRegex(const Pattern: string): TIRegexp;
var
  I: Integer;
begin
  for I := 0 to FRegexCount - 1 do
    if FRegexPatterns[I] = Pattern then
    begin
      Result := TIRegexp(FRegexObjs[I]);
      Exit;
    end;
  try
    Result := TIRegexp.Create(Pattern);
  except
    on EJSONPathRegexError do
      Result := nil;
  end;
  if FRegexCount >= Length(FRegexPatterns) then
    SetLength(FRegexPatterns, FRegexCount * 2 + 4);
  FRegexPatterns[FRegexCount] := Pattern;
  Inc(FRegexCount);
  FRegexObjs.Add(Result); { a nil entry caches "invalid pattern" }
end;

{ ---- selectors ---- }

procedure TJPEvaluator.ApplySlice(Slice: TJSONPathSlice; Node: TJPNode; Output: TJPNodeList);
var
  Len, Step, StartV, EndV, NStart, NEnd, Lower, Upper, I: Int64;

  function Normalize(Idx: Int64): Int64;
  begin
    if Idx >= 0 then
      Result := Idx
    else
      Result := Len + Idx;
  end;

begin
  if Node.Value.Kind <> jkArray then
    Exit;
  Step := Slice.EffectiveStep;
  if Step = 0 then
    Exit;
  Len := Node.Value.Count;
  if Slice.HasStart then
    StartV := Slice.Start
  else if Step > 0 then
    StartV := 0
  else
    StartV := Len - 1;
  if Slice.HasEnd then
    EndV := Slice.EndIndex
  else if Step > 0 then
    EndV := Len
  else
    EndV := -Len - 1;
  NStart := Normalize(StartV);
  NEnd := Normalize(EndV);
  if Step > 0 then
  begin
    Lower := MinInt64(MaxInt64(NStart, 0), Len);
    Upper := MinInt64(MaxInt64(NEnd, 0), Len);
    I := Lower;
    while I < Upper do
    begin
      Output.Add(MakeChild(Node, Integer(I)));
      I := I + Step;
    end;
  end
  else
  begin
    Upper := MinInt64(MaxInt64(NStart, -1), Len - 1);
    Lower := MinInt64(MaxInt64(NEnd, -1), Len - 1);
    I := Upper;
    while I > Lower do
    begin
      Output.Add(MakeChild(Node, Integer(I)));
      I := I + Step;
    end;
  end;
end;

procedure TJPEvaluator.ApplyFilter(Sel: TJSONPathFilterSelector; Node: TJPNode;
  Output: TJPNodeList);
var
  I: Integer;
  Child: TJPNode;
begin
  if (Node.Value.Kind <> jkArray) and (Node.Value.Kind <> jkObject) then
    Exit;
  for I := 0 to Node.Value.Count - 1 do
  begin
    Child := MakeChild(Node, I);
    if EvalLogical(Sel.Expression, Child) then
      Output.Add(Child);
  end;
end;

procedure TJPEvaluator.ApplySelector(Sel: TJSONPathSelector; Node: TJPNode;
  Output: TJPNodeList);
var
  I: Integer;
  Idx: Int64;
  Member: TJSONValue;
  Child: TJPNode;
begin
  if Sel is TJSONPathNameSelector then
  begin
    if Node.Value.Kind = jkObject then
    begin
      Member := Node.Value.FindMember(TJSONPathNameSelector(Sel).Name);
      if Member <> nil then
      begin
        Child := NewNode(Member, Node);
        Child.Name := TJSONPathNameSelector(Sel).Name;
        Output.Add(Child);
      end;
    end;
  end
  else if Sel is TJSONPathWildcardSelector then
  begin
    if (Node.Value.Kind = jkArray) or (Node.Value.Kind = jkObject) then
      for I := 0 to Node.Value.Count - 1 do
        Output.Add(MakeChild(Node, I));
  end
  else if Sel is TJSONPathIndexSelector then
  begin
    if Node.Value.Kind = jkArray then
    begin
      Idx := TJSONPathIndexSelector(Sel).Index;
      if Idx < 0 then
        Idx := Idx + Node.Value.Count;
      if (Idx >= 0) and (Idx < Node.Value.Count) then
        Output.Add(MakeChild(Node, Integer(Idx)));
    end;
  end
  else if Sel is TJSONPathSlice then
    ApplySlice(TJSONPathSlice(Sel), Node, Output)
  else if Sel is TJSONPathFilterSelector then
    ApplyFilter(TJSONPathFilterSelector(Sel), Node, Output);
end;

procedure TJPEvaluator.ApplySelectors(Seg: TJSONPathSegment; Node: TJPNode;
  Output: TJPNodeList);
var
  I: Integer;
begin
  for I := 0 to Seg.SelectorCount - 1 do
    ApplySelector(Seg.Selectors[I], Node, Output);
end;

procedure TJPEvaluator.VisitDescendants(Seg: TJSONPathSegment; Node: TJPNode;
  Output: TJPNodeList);
var
  I: Integer;
begin
  ApplySelectors(Seg, Node, Output);
  if (Node.Value.Kind = jkArray) or (Node.Value.Kind = jkObject) then
    for I := 0 to Node.Value.Count - 1 do
      VisitDescendants(Seg, MakeChild(Node, I), Output);
end;

function TJPEvaluator.EvalQuery(Q: TJSONPathQueryNode; Current: TJPNode): TJPNodeList;
var
  Cur, Next: TJPNodeList;
  S, N: Integer;
  Seg: TJSONPathSegment;
begin
  Cur := NewList;
  if Q.IsRelative then
    Cur.Add(Current)
  else
    Cur.Add(FRoot);
  for S := 0 to Q.SegmentCount - 1 do
  begin
    Seg := Q.Segments[S];
    Next := NewList;
    for N := 0 to Cur.Count - 1 do
      if Seg.IsDescendant then
        VisitDescendants(Seg, Cur[N], Next)
      else
        ApplySelectors(Seg, Cur[N], Next);
    Cur := Next;
  end;
  Result := Cur;
end;

function TJPEvaluator.Run(Q: TJSONPathQueryNode): TJPNodeList;
begin
  Result := EvalQuery(Q, FRoot);
end;

{ ---- filter expressions ---- }

function TJPEvaluator.CompareResults(Op: TJSONPathCompareOp; const L, R: TJPResult): Boolean;

  function Equal(const A, B: TJPResult): Boolean;
  begin
    if (A.Kind = rkNothing) and (B.Kind = rkNothing) then
      Result := True
    else if (A.Kind = rkNothing) or (B.Kind = rkNothing) then
      Result := False
    else
      Result := JSONEquals(A.Value, B.Value);
  end;

  function Less(const A, B: TJPResult): Boolean;
  begin
    Result := False;
    if (A.Kind <> rkValue) or (B.Kind <> rkValue) then
      Exit;
    if (A.Value.Kind = jkNumber) and (B.Value.Kind = jkNumber) then
      Result := JSONNumberCompare(A.Value, B.Value) < 0
    else if (A.Value.Kind = jkString) and (B.Value.Kind = jkString) then
      Result := CompareStr(A.Value.StringValue, B.Value.StringValue) < 0;
  end;

begin
  case Op of
    coEq: Result := Equal(L, R);
    coNe: Result := not Equal(L, R);
    coLt: Result := Less(L, R);
    coLe: Result := Less(L, R) or Equal(L, R);
    coGt: Result := Less(R, L);
    coGe: Result := Less(R, L) or Equal(L, R);
  else
    Result := False;
  end;
end;

function TJPEvaluator.EvalLogical(Expr: TJSONPathExpression; Current: TJPNode): Boolean;
var
  Res: TJPResult;
  Cmp: TJSONPathComparison;
begin
  Result := False;
  if Expr is TJSONPathLogicalOr then
    Result := EvalLogical(TJSONPathLogicalOr(Expr).Left, Current)
      or EvalLogical(TJSONPathLogicalOr(Expr).Right, Current)
  else if Expr is TJSONPathLogicalAnd then
    Result := EvalLogical(TJSONPathLogicalAnd(Expr).Left, Current)
      and EvalLogical(TJSONPathLogicalAnd(Expr).Right, Current)
  else if Expr is TJSONPathLogicalNot then
    Result := not EvalLogical(TJSONPathLogicalNot(Expr).Operand, Current)
  else if Expr is TJSONPathComparison then
  begin
    Cmp := TJSONPathComparison(Expr);
    Result := CompareResults(Cmp.Op, EvalComparable(Cmp.Left, Current),
      EvalComparable(Cmp.Right, Current));
  end
  else if Expr is TJSONPathQueryExpr then
    Result := EvalQuery(TJSONPathQueryExpr(Expr).Query, Current).Count > 0
  else if Expr is TJSONPathFunctionCall then
  begin
    Res := EvalFunction(TJSONPathFunctionCall(Expr), Current);
    case Res.Kind of
      rkLogical: Result := Res.Logical;
      rkNodes: Result := Res.Nodes.Count > 0;
    end;
  end;
end;

function TJPEvaluator.EvalComparable(Expr: TJSONPathExpression; Current: TJPNode): TJPResult;
var
  Nodes: TJPNodeList;
begin
  Result := ResNothing;
  if Expr is TJSONPathLiteral then
    Result := ResValue(TJSONPathLiteral(Expr).Value)
  else if Expr is TJSONPathQueryExpr then
  begin
    Nodes := EvalQuery(TJSONPathQueryExpr(Expr).Query, Current);
    if Nodes.Count = 1 then
      Result := ResValue(Nodes[0].Value);
  end
  else if Expr is TJSONPathFunctionCall then
    Result := EvalFunction(TJSONPathFunctionCall(Expr), Current);
end;

function TJPEvaluator.EvalArgument(Arg: TJSONPathExpression; ParamType: TJSONPathValueType;
  Current: TJPNode): TJPResult;
begin
  case ParamType of
    vtValue:
      Result := EvalComparable(Arg, Current);
    vtNodes:
      if Arg is TJSONPathQueryExpr then
        Result := ResNodes(EvalQuery(TJSONPathQueryExpr(Arg).Query, Current))
      else if Arg is TJSONPathFunctionCall then
        Result := EvalFunction(TJSONPathFunctionCall(Arg), Current)
      else
        Result := ResNodes(NewList);
  else
    Result := ResLogical(EvalLogical(Arg, Current));
  end;
end;

function TJPEvaluator.EvalFunction(Call: TJSONPathFunctionCall; Current: TJPNode): TJPResult;
var
  A0, A1: TJPResult;
  Rx: TIRegexp;
  Matched: Boolean;
begin
  Result := ResNothing;
  case Call.FunctionKind of
    fkLength:
      begin
        A0 := EvalArgument(Call.Arguments[0], vtValue, Current);
        if A0.Kind = rkValue then
          case A0.Value.Kind of
            jkString: Result := ResValue(TempNumber(CodePointLength(A0.Value.StringValue)));
            jkArray, jkObject: Result := ResValue(TempNumber(A0.Value.Count));
          end;
      end;
    fkCount:
      begin
        A0 := EvalArgument(Call.Arguments[0], vtNodes, Current);
        if A0.Kind = rkNodes then
          Result := ResValue(TempNumber(A0.Nodes.Count));
      end;
    fkValue:
      begin
        A0 := EvalArgument(Call.Arguments[0], vtNodes, Current);
        if (A0.Kind = rkNodes) and (A0.Nodes.Count = 1) then
          Result := ResValue(A0.Nodes[0].Value);
      end;
    fkCustom:
      Result := EvalCustom(Call, Current);
    fkMatch, fkSearch:
      begin
        Result := ResLogical(False);
        A0 := EvalArgument(Call.Arguments[0], vtValue, Current);
        A1 := EvalArgument(Call.Arguments[1], vtValue, Current);
        if (A0.Kind = rkValue) and (A0.Value.Kind = jkString)
          and (A1.Kind = rkValue) and (A1.Value.Kind = jkString) then
        begin
          Rx := GetRegex(A1.Value.StringValue);
          if Rx <> nil then
          begin
            if Call.FunctionKind = fkMatch then
              Matched := Rx.IsMatch(A0.Value.StringValue)
            else
              Matched := Rx.IsSearch(A0.Value.StringValue);
            Result := ResLogical(Matched);
          end;
        end;
      end;
  end;
end;

{ ---- TJSONPath ---- }

constructor TJSONPath.Create(const AQuery: string);
begin
  inherited Create;
  FSource := AQuery;
  FQuery := ParseJSONPath(AQuery);
end;

destructor TJSONPath.Destroy;
begin
  FQuery.Free;
  inherited Destroy;
end;

function TJSONPath.Evaluate(ARoot: TJSONValue): TJSONPathResult;
var
  Ev: TJPEvaluator;
  Nodes: TJPNodeList;
  Res: TJSONPathResult;
  I: Integer;
begin
  if ARoot = nil then
    raise Exception.Create('JSONPath: the root JSON value must not be nil');
  Res := TJSONPathResult.Create;
  try
    Ev := TJPEvaluator.Create(ARoot);
    try
      Nodes := Ev.Run(FQuery);
      for I := 0 to Nodes.Count - 1 do
        Res.Add(Nodes[I].Value, NodePath(Nodes[I]));
    finally
      Ev.Free;
    end;
    Result := Res;
    Res := nil;
  finally
    Res.Free;
  end;
end;

class procedure TJSONPath.RegisterFunction(const AName: string;
  const AParams: array of TJSONPathValueType; AResultType: TJSONPathValueType;
  AHandler: TJSONPathFunctionHandler);
begin
  RegisterJSONPathFunction(AName, AParams, AResultType, AHandler);
end;

class procedure TJSONPath.RegisterFunction(const AName: string;
  const AParams: array of TJSONPathValueType; AResultType: TJSONPathValueType;
  AHandler: TJSONPathFunctionMethod);
begin
  RegisterJSONPathFunction(AName, AParams, AResultType, AHandler);
end;

class function TJSONPath.UnregisterFunction(const AName: string): Boolean;
begin
  Result := UnregisterJSONPathFunction(AName);
end;

function JSONPathSelect(const AQuery: string; ARoot: TJSONValue): TJSONPathResult;
var
  P: TJSONPath;
begin
  P := TJSONPath.Create(AQuery);
  try
    Result := P.Evaluate(ARoot);
  finally
    P.Free;
  end;
end;

end.
