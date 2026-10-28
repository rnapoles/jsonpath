{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit JSONPathParser;

{ Recursive-descent parser for RFC 9535 JSONPath.

  Every non-terminal of the RFC's ABNF has a matching method:

    jsonpath-query       ParseQueryBody / Parse
    segments, segment    ParseSegments, ParseSegment
    child-segment        ParseChildSegment
    descendant-segment   ParseDescendantSegment
    bracketed-selection  ParseBracketedSelection
    selector             ParseSelector
    name-selector        ParseNameSelector
    wildcard-selector    ParseWildcardSelector
    index-selector       ParseIndexSelector
    slice-selector       ParseSlice
    filter-selector      ParseFilterSelector
    logical-or-expr      ParseLogicalOrExpr
    logical-and-expr     ParseLogicalAndExpr
    basic-expr           ParseBasicExpr
    paren-expr           ParseParenExpr
    test-expr / comparison-expr / comparable   ParsePrimary + ParseBasicExpr
    literal              ParseLiteral
    function-expr        ParseFunctionCall

  The parser returns an AST owned by the caller. Well-typedness of function
  expressions (RFC 9535 section 2.4.3) is checked while parsing, so an
  ill-typed query is rejected with an EJSONPathParseException. }

interface

uses
  SysUtils, Classes, JSONPathCommon, JSONPathJSON, JSONPathLexer;

type
  TJSONPathValueType = (vtValue, vtLogical, vtNodes);
  TJSONPathFunctionKind = (fkLength, fkCount, fkMatch, fkSearch, fkValue, fkCustom);
  TJSONPathCompareOp = (coEq, coNe, coLt, coLe, coGt, coGe);

  EJSONPathFunctionError = class(Exception);

  { ---- custom function support ----
    Register a function once (e.g. at program start) and use it in any query:

      function FnUpper(Args: TJSONPathArgs): TJSONPathFuncResult;
      begin
        if Args.IsString(0) then
          Result := FuncString(UpperCase(Args.AsString(0)))
        else
          Result := FuncNothing;
      end;

      RegisterJSONPathFunction('upper', [vtValue], vtValue, FnUpper);
      // $[?upper(@.name) == "ANN"]

    Parameter types: vtValue   = a literal, singular query or value function
                                 (IsNothing(i) when the query selects nothing)
                     vtNodes   = any query; read with NodeCount / Node
                     vtLogical = a logical expression; read with AsBoolean
    Result types:    vtValue   = return FuncNumber / FuncString / FuncBool /
                                 FuncNull / FuncValue / FuncNothing
                     vtLogical = return FuncLogical (usable as a test such as
                                 $[?between(@.age, 18, 65)] ) }

  { The evaluated arguments handed to a custom function }
  TJSONPathArgs = class
  private
    FItems: TOwnedList;
    function Fetch(Index: Integer): TObject;
    function GetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    { used by the evaluator }
    procedure AddValue(AValue: TJSONValue);
    procedure AddLogical(AValue: Boolean);
    procedure AddNodes(const ANodes: array of TJSONValue);
    { argument access; Index is 0-based }
    property Count: Integer read GetCount;
    function Kind(Index: Integer): TJSONPathValueType;
    { vtValue arguments: True when the argument is empty (query found nothing) }
    function IsNothing(Index: Integer): Boolean;
    function IsString(Index: Integer): Boolean;
    function IsNumber(Index: Integer): Boolean;
    function IsBoolean(Index: Integer): Boolean;
    function IsNull(Index: Integer): Boolean;
    function IsArray(Index: Integer): Boolean;
    function IsObject(Index: Integer): Boolean;
    { the raw JSON value of a vtValue argument (nil when empty) }
    function Value(Index: Integer): TJSONValue;
    function AsString(Index: Integer; const ADefault: string = ''): string;
    function AsNumber(Index: Integer; ADefault: Double = 0): Double;
    function AsBoolean(Index: Integer; ADefault: Boolean = False): Boolean;
    { vtNodes arguments }
    function NodeCount(Index: Integer): Integer;
    function Node(Index, NodeIndex: Integer): TJSONValue;
  end;

  TJSONPathFuncResultKind = (frNothing, frValue, frNumber, frString, frBool,
    frNull, frLogical);

  { What a custom function returns; build it with the Func* helpers below }
  TJSONPathFuncResult = record
    Kind: TJSONPathFuncResultKind;
    Value: TJSONValue;
    Num: Double;
    Str: string;
    Bool: Boolean;
  end;

  TJSONPathFunctionHandler = function(Args: TJSONPathArgs): TJSONPathFuncResult;
  TJSONPathFunctionMethod = function(Args: TJSONPathArgs): TJSONPathFuncResult of object;

  { A registered function. Instances are owned by the registry. }
  TJSONPathCustomFunction = class
  private
    FName: string;
    FHandler: TJSONPathFunctionHandler;
    FMethod: TJSONPathFunctionMethod;
  public
    Params: array of TJSONPathValueType;
    ResultType: TJSONPathValueType;
    constructor Create(const AName: string;
      const AParams: array of TJSONPathValueType; AResultType: TJSONPathValueType;
      AHandler: TJSONPathFunctionHandler; AMethod: TJSONPathFunctionMethod);
    function Invoke(Args: TJSONPathArgs): TJSONPathFuncResult;
    property Name: string read FName;
  end;

  TJSONPathFunctionSignature = record
    Kind: TJSONPathFunctionKind;
    ParamCount: Integer;
    Params: array of TJSONPathValueType;
    ResultType: TJSONPathValueType;
    Custom: TJSONPathCustomFunction;
  end;

  { ---- AST ---- }

  TJSONPathNode = class
  end;

  TJSONPathExpression = class(TJSONPathNode)
  end;

  TJSONPathSelector = class(TJSONPathNode)
  end;

  TJSONPathNameSelector = class(TJSONPathSelector)
  private
    FName: string;
  public
    constructor Create(const AName: string);
    property Name: string read FName;
  end;

  TJSONPathWildcardSelector = class(TJSONPathSelector)
  end;

  TJSONPathIndexSelector = class(TJSONPathSelector)
  private
    FIndex: Int64;
  public
    constructor Create(AIndex: Int64);
    property Index: Int64 read FIndex;
  end;

  TJSONPathSlice = class(TJSONPathSelector)
  public
    HasStart: Boolean;
    HasEnd: Boolean;
    HasStep: Boolean;
    Start: Int64;
    EndIndex: Int64;
    Step: Int64;
    { 1 when no step was written }
    function EffectiveStep: Int64;
  end;

  TJSONPathFilterSelector = class(TJSONPathSelector)
  private
    FExpression: TJSONPathExpression;
  public
    { takes ownership of AExpression }
    constructor Create(AExpression: TJSONPathExpression);
    destructor Destroy; override;
    property Expression: TJSONPathExpression read FExpression;
  end;

  TJSONPathSegment = class(TJSONPathNode)
  private
    FDescendant: Boolean;
    FSelectors: TOwnedList;
    function GetSelectorCount: Integer;
    function GetSelector(Index: Integer): TJSONPathSelector;
  public
    constructor Create(ADescendant: Boolean);
    destructor Destroy; override;
    procedure AddSelector(ASelector: TJSONPathSelector);
    property IsDescendant: Boolean read FDescendant;
    property SelectorCount: Integer read GetSelectorCount;
    property Selectors[Index: Integer]: TJSONPathSelector read GetSelector;
  end;

  TJSONPathQueryNode = class(TJSONPathNode)
  private
    FRelative: Boolean;
    FSegments: TOwnedList;
    function GetSegmentCount: Integer;
    function GetSegment(Index: Integer): TJSONPathSegment;
  public
    constructor Create(ARelative: Boolean);
    destructor Destroy; override;
    procedure AddSegment(ASegment: TJSONPathSegment);
    { True when the query can select at most one node (RFC 9535 2.3.5.1) }
    function IsSingular: Boolean;
    { '@' queries start at the current node, '$' queries at the root }
    property IsRelative: Boolean read FRelative;
    property SegmentCount: Integer read GetSegmentCount;
    property Segments[Index: Integer]: TJSONPathSegment read GetSegment;
  end;

  TJSONPathBinaryExpression = class(TJSONPathExpression)
  public
    Left: TJSONPathExpression;
    Right: TJSONPathExpression;
    destructor Destroy; override;
  end;

  TJSONPathLogicalOr = class(TJSONPathBinaryExpression)
  end;

  TJSONPathLogicalAnd = class(TJSONPathBinaryExpression)
  end;

  TJSONPathComparison = class(TJSONPathBinaryExpression)
  public
    Op: TJSONPathCompareOp;
  end;

  TJSONPathLogicalNot = class(TJSONPathExpression)
  public
    Operand: TJSONPathExpression;
    destructor Destroy; override;
  end;

  TJSONPathLiteral = class(TJSONPathExpression)
  private
    FValue: TJSONValue;
  public
    { takes ownership of AValue }
    constructor Create(AValue: TJSONValue);
    destructor Destroy; override;
    property Value: TJSONValue read FValue;
  end;

  TJSONPathQueryExpr = class(TJSONPathExpression)
  private
    FQuery: TJSONPathQueryNode;
  public
    { takes ownership of AQuery }
    constructor Create(AQuery: TJSONPathQueryNode);
    destructor Destroy; override;
    property Query: TJSONPathQueryNode read FQuery;
  end;

  TJSONPathFunctionCall = class(TJSONPathExpression)
  private
    FName: string;
    FKind: TJSONPathFunctionKind;
    FResultType: TJSONPathValueType;
    FCustom: TJSONPathCustomFunction;
    FArgs: TOwnedList;
    function GetArgumentCount: Integer;
    function GetArgument(Index: Integer): TJSONPathExpression;
  public
    constructor Create(const AName: string; const ASignature: TJSONPathFunctionSignature);
    destructor Destroy; override;
    procedure AddArgument(AArgument: TJSONPathExpression);
    property Name: string read FName;
    property FunctionKind: TJSONPathFunctionKind read FKind;
    { the registered function when FunctionKind = fkCustom }
    property Custom: TJSONPathCustomFunction read FCustom;
    property ResultType: TJSONPathValueType read FResultType;
    property ArgumentCount: Integer read GetArgumentCount;
    property Arguments[Index: Integer]: TJSONPathExpression read GetArgument;
  end;

  { ---- parser ---- }

  TJSONPathParser = class
  private
    FLexer: TJSONPathLexer;
    FDepth: Integer;
    procedure EnterNesting;
    procedure LeaveNesting;
    function TryScanCompareOp(out Op: TJSONPathCompareOp): Boolean;
    function TryMatchOperator(const Op: string): Boolean;
    procedure RequireLogical(Expr: TJSONPathExpression; StartPos: Integer);
    procedure CheckComparable(Expr: TJSONPathExpression; StartPos: Integer);
    procedure CheckArgument(Expr: TJSONPathExpression; ParamType: TJSONPathValueType;
      StartPos: Integer; const FuncName: string);
    function IsIntStart(C: Char): Boolean;
    function IsSliceAhead: Boolean;

    function ParseQueryBody: TJSONPathQueryNode;
    procedure ParseSegments(Query: TJSONPathQueryNode);
    function ParseSegment: TJSONPathSegment;
    function ParseChildSegment: TJSONPathSegment;
    function ParseDescendantSegment: TJSONPathSegment;
    procedure ParseShorthand(Segment: TJSONPathSegment);
    procedure ParseBracketedSelection(Segment: TJSONPathSegment);
    function ParseSelector: TJSONPathSelector;
    function ParseNameSelector: TJSONPathNameSelector;
    function ParseWildcardSelector: TJSONPathWildcardSelector;
    function ParseIndexSelector: TJSONPathIndexSelector;
    function ParseSlice: TJSONPathSlice;
    function ParseFilterSelector: TJSONPathFilterSelector;
    function ParseLogicalOrExpr: TJSONPathExpression;
    function ParseLogicalAndExpr: TJSONPathExpression;
    function ParseBasicExpr: TJSONPathExpression;
    function ParseParenExpr: TJSONPathExpression;
    function ParsePrimary: TJSONPathExpression;
    function ParseLiteral: TJSONPathLiteral;
    function ParseFunctionCall(const AName: string; NamePos: Integer): TJSONPathFunctionCall;
  public
    constructor Create(const AQuery: string);
    destructor Destroy; override;
    { Parses the complete query. The caller owns the returned AST. }
    function Parse: TJSONPathQueryNode;
  end;

{ Convenience wrapper; the caller owns the result. }
function ParseJSONPath(const AQuery: string): TJSONPathQueryNode;
function FindJSONPathFunction(const AName: string; out Sig: TJSONPathFunctionSignature): Boolean;

{ Registers (or replaces) a custom function. Names follow the RFC grammar
  (lowercase letter, then lowercase letters, digits or "_") and may not reuse
  a built-in name (length, count, match, search, value). Result type vtNodes
  is not supported. Raises EJSONPathFunctionError on invalid input.
  Register functions before parsing queries that use them, and not from
  several threads at once. }
procedure RegisterJSONPathFunction(const AName: string;
  const AParams: array of TJSONPathValueType; AResultType: TJSONPathValueType;
  AHandler: TJSONPathFunctionHandler); overload;
procedure RegisterJSONPathFunction(const AName: string;
  const AParams: array of TJSONPathValueType; AResultType: TJSONPathValueType;
  AHandler: TJSONPathFunctionMethod); overload;
{ Returns False when no such custom function was registered. Queries that
  were already parsed keep working with the old implementation. }
function UnregisterJSONPathFunction(const AName: string): Boolean;
function IsJSONPathFunctionRegistered(const AName: string): Boolean;

{ result builders for custom functions }
function FuncNothing: TJSONPathFuncResult;
function FuncValue(AValue: TJSONValue): TJSONPathFuncResult;
function FuncNumber(AValue: Double): TJSONPathFuncResult;
function FuncString(const AValue: string): TJSONPathFuncResult;
function FuncBool(AValue: Boolean): TJSONPathFuncResult;
function FuncNull: TJSONPathFuncResult;
function FuncLogical(AValue: Boolean): TJSONPathFuncResult;

implementation

const
  MAX_NESTING = 64;

{ ---- AST implementation ---- }

constructor TJSONPathNameSelector.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
end;

constructor TJSONPathIndexSelector.Create(AIndex: Int64);
begin
  inherited Create;
  FIndex := AIndex;
end;

function TJSONPathSlice.EffectiveStep: Int64;
begin
  if HasStep then
    Result := Step
  else
    Result := 1;
end;

constructor TJSONPathFilterSelector.Create(AExpression: TJSONPathExpression);
begin
  inherited Create;
  FExpression := AExpression;
end;

destructor TJSONPathFilterSelector.Destroy;
begin
  FExpression.Free;
  inherited Destroy;
end;

constructor TJSONPathSegment.Create(ADescendant: Boolean);
begin
  inherited Create;
  FDescendant := ADescendant;
  FSelectors := TOwnedList.Create;
end;

destructor TJSONPathSegment.Destroy;
begin
  FSelectors.Free;
  inherited Destroy;
end;

procedure TJSONPathSegment.AddSelector(ASelector: TJSONPathSelector);
begin
  FSelectors.Add(ASelector);
end;

function TJSONPathSegment.GetSelectorCount: Integer;
begin
  Result := FSelectors.Count;
end;

function TJSONPathSegment.GetSelector(Index: Integer): TJSONPathSelector;
begin
  Result := TJSONPathSelector(FSelectors[Index]);
end;

constructor TJSONPathQueryNode.Create(ARelative: Boolean);
begin
  inherited Create;
  FRelative := ARelative;
  FSegments := TOwnedList.Create;
end;

destructor TJSONPathQueryNode.Destroy;
begin
  FSegments.Free;
  inherited Destroy;
end;

procedure TJSONPathQueryNode.AddSegment(ASegment: TJSONPathSegment);
begin
  FSegments.Add(ASegment);
end;

function TJSONPathQueryNode.GetSegmentCount: Integer;
begin
  Result := FSegments.Count;
end;

function TJSONPathQueryNode.GetSegment(Index: Integer): TJSONPathSegment;
begin
  Result := TJSONPathSegment(FSegments[Index]);
end;

function TJSONPathQueryNode.IsSingular: Boolean;
var
  I: Integer;
  Seg: TJSONPathSegment;
  Sel: TJSONPathSelector;
begin
  Result := False;
  for I := 0 to FSegments.Count - 1 do
  begin
    Seg := GetSegment(I);
    if Seg.IsDescendant or (Seg.SelectorCount <> 1) then
      Exit;
    Sel := Seg.Selectors[0];
    if not ((Sel is TJSONPathNameSelector) or (Sel is TJSONPathIndexSelector)) then
      Exit;
  end;
  Result := True;
end;

destructor TJSONPathBinaryExpression.Destroy;
begin
  Left.Free;
  Right.Free;
  inherited Destroy;
end;

destructor TJSONPathLogicalNot.Destroy;
begin
  Operand.Free;
  inherited Destroy;
end;

constructor TJSONPathLiteral.Create(AValue: TJSONValue);
begin
  inherited Create;
  FValue := AValue;
end;

destructor TJSONPathLiteral.Destroy;
begin
  FValue.Free;
  inherited Destroy;
end;

constructor TJSONPathQueryExpr.Create(AQuery: TJSONPathQueryNode);
begin
  inherited Create;
  FQuery := AQuery;
end;

destructor TJSONPathQueryExpr.Destroy;
begin
  FQuery.Free;
  inherited Destroy;
end;

constructor TJSONPathFunctionCall.Create(const AName: string;
  const ASignature: TJSONPathFunctionSignature);
begin
  inherited Create;
  FName := AName;
  FKind := ASignature.Kind;
  FResultType := ASignature.ResultType;
  FCustom := ASignature.Custom;
  FArgs := TOwnedList.Create;
end;

destructor TJSONPathFunctionCall.Destroy;
begin
  FArgs.Free;
  inherited Destroy;
end;

procedure TJSONPathFunctionCall.AddArgument(AArgument: TJSONPathExpression);
begin
  FArgs.Add(AArgument);
end;

function TJSONPathFunctionCall.GetArgumentCount: Integer;
begin
  Result := FArgs.Count;
end;

function TJSONPathFunctionCall.GetArgument(Index: Integer): TJSONPathExpression;
begin
  Result := TJSONPathExpression(FArgs[Index]);
end;

{ ---- result builders ---- }

function MakeFuncResult(AKind: TJSONPathFuncResultKind): TJSONPathFuncResult;
begin
  Result.Kind := AKind;
  Result.Value := nil;
  Result.Num := 0;
  Result.Str := '';
  Result.Bool := False;
end;

function FuncNothing: TJSONPathFuncResult;
begin
  Result := MakeFuncResult(frNothing);
end;

function FuncValue(AValue: TJSONValue): TJSONPathFuncResult;
begin
  Result := MakeFuncResult(frValue);
  Result.Value := AValue;
end;

function FuncNumber(AValue: Double): TJSONPathFuncResult;
begin
  Result := MakeFuncResult(frNumber);
  Result.Num := AValue;
end;

function FuncString(const AValue: string): TJSONPathFuncResult;
begin
  Result := MakeFuncResult(frString);
  Result.Str := AValue;
end;

function FuncBool(AValue: Boolean): TJSONPathFuncResult;
begin
  Result := MakeFuncResult(frBool);
  Result.Bool := AValue;
end;

function FuncNull: TJSONPathFuncResult;
begin
  Result := MakeFuncResult(frNull);
end;

function FuncLogical(AValue: Boolean): TJSONPathFuncResult;
begin
  Result := MakeFuncResult(frLogical);
  Result.Bool := AValue;
end;

{ ---- TJSONPathArgs ---- }

type
  TArgItem = class
  public
    Kind: TJSONPathValueType;
    Value: TJSONValue;
    Logical: Boolean;
    Nodes: array of TJSONValue;
  end;

constructor TJSONPathArgs.Create;
begin
  inherited Create;
  FItems := TOwnedList.Create;
end;

destructor TJSONPathArgs.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TJSONPathArgs.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TJSONPathArgs.Fetch(Index: Integer): TObject;
begin
  if (Index < 0) or (Index >= FItems.Count) then
    raise EJSONPathFunctionError.CreateFmt(
      'Argument index %d is out of range (the function received %d argument(s))',
      [Index, FItems.Count]);
  Result := FItems[Index];
end;

procedure TJSONPathArgs.AddValue(AValue: TJSONValue);
var
  Item: TArgItem;
begin
  Item := TArgItem.Create;
  Item.Kind := vtValue;
  Item.Value := AValue;
  FItems.Add(Item);
end;

procedure TJSONPathArgs.AddLogical(AValue: Boolean);
var
  Item: TArgItem;
begin
  Item := TArgItem.Create;
  Item.Kind := vtLogical;
  Item.Logical := AValue;
  FItems.Add(Item);
end;

procedure TJSONPathArgs.AddNodes(const ANodes: array of TJSONValue);
var
  Item: TArgItem;
  I: Integer;
begin
  Item := TArgItem.Create;
  Item.Kind := vtNodes;
  SetLength(Item.Nodes, Length(ANodes));
  for I := 0 to High(ANodes) do
    Item.Nodes[I] := ANodes[I];
  FItems.Add(Item);
end;

function TJSONPathArgs.Kind(Index: Integer): TJSONPathValueType;
begin
  Result := TArgItem(Fetch(Index)).Kind;
end;

function TJSONPathArgs.Value(Index: Integer): TJSONValue;
var
  Item: TArgItem;
begin
  Item := TArgItem(Fetch(Index));
  if Item.Kind = vtValue then
    Result := Item.Value
  else
    Result := nil;
end;

function TJSONPathArgs.IsNothing(Index: Integer): Boolean;
begin
  Result := Value(Index) = nil;
end;

function TJSONPathArgs.IsString(Index: Integer): Boolean;
var
  V: TJSONValue;
begin
  V := Value(Index);
  Result := (V <> nil) and (V.Kind = jkString);
end;

function TJSONPathArgs.IsNumber(Index: Integer): Boolean;
var
  V: TJSONValue;
begin
  V := Value(Index);
  Result := (V <> nil) and (V.Kind = jkNumber);
end;

function TJSONPathArgs.IsBoolean(Index: Integer): Boolean;
var
  V: TJSONValue;
begin
  V := Value(Index);
  Result := (V <> nil) and (V.Kind = jkBoolean);
end;

function TJSONPathArgs.IsNull(Index: Integer): Boolean;
var
  V: TJSONValue;
begin
  V := Value(Index);
  Result := (V <> nil) and (V.Kind = jkNull);
end;

function TJSONPathArgs.IsArray(Index: Integer): Boolean;
var
  V: TJSONValue;
begin
  V := Value(Index);
  Result := (V <> nil) and (V.Kind = jkArray);
end;

function TJSONPathArgs.IsObject(Index: Integer): Boolean;
var
  V: TJSONValue;
begin
  V := Value(Index);
  Result := (V <> nil) and (V.Kind = jkObject);
end;

function TJSONPathArgs.AsString(Index: Integer; const ADefault: string): string;
begin
  if IsString(Index) then
    Result := Value(Index).StringValue
  else
    Result := ADefault;
end;

function TJSONPathArgs.AsNumber(Index: Integer; ADefault: Double): Double;
begin
  if IsNumber(Index) then
    Result := Value(Index).NumberValue
  else
    Result := ADefault;
end;

function TJSONPathArgs.AsBoolean(Index: Integer; ADefault: Boolean): Boolean;
var
  Item: TArgItem;
begin
  Item := TArgItem(Fetch(Index));
  if Item.Kind = vtLogical then
    Result := Item.Logical
  else if (Item.Kind = vtValue) and (Item.Value <> nil)
    and (Item.Value.Kind = jkBoolean) then
    Result := Item.Value.BoolValue
  else
    Result := ADefault;
end;

function TJSONPathArgs.NodeCount(Index: Integer): Integer;
var
  Item: TArgItem;
begin
  Item := TArgItem(Fetch(Index));
  if Item.Kind = vtNodes then
    Result := Length(Item.Nodes)
  else
    Result := 0;
end;

function TJSONPathArgs.Node(Index, NodeIndex: Integer): TJSONValue;
var
  Item: TArgItem;
begin
  Item := TArgItem(Fetch(Index));
  if (Item.Kind <> vtNodes) or (NodeIndex < 0) or (NodeIndex >= Length(Item.Nodes)) then
    raise EJSONPathFunctionError.CreateFmt(
      'Node %d of argument %d does not exist', [NodeIndex, Index]);
  Result := Item.Nodes[NodeIndex];
end;

{ ---- TJSONPathCustomFunction and the registry ---- }

constructor TJSONPathCustomFunction.Create(const AName: string;
  const AParams: array of TJSONPathValueType; AResultType: TJSONPathValueType;
  AHandler: TJSONPathFunctionHandler; AMethod: TJSONPathFunctionMethod);
var
  I: Integer;
begin
  inherited Create;
  FName := AName;
  SetLength(Params, Length(AParams));
  for I := 0 to High(AParams) do
    Params[I] := AParams[I];
  ResultType := AResultType;
  FHandler := AHandler;
  FMethod := AMethod;
end;

function TJSONPathCustomFunction.Invoke(Args: TJSONPathArgs): TJSONPathFuncResult;
begin
  if Assigned(FHandler) then
    Result := FHandler(Args)
  else
    Result := FMethod(Args);
end;

var
  GCustomFunctions: TList;
  { replaced or unregistered entries stay alive so that already-parsed queries
    never hold a dangling pointer; they are freed at program exit }
  GRetiredFunctions: TList;

function IsBuiltinFunctionName(const AName: string): Boolean;
begin
  Result := (AName = 'length') or (AName = 'count') or (AName = 'match')
    or (AName = 'search') or (AName = 'value');
end;

function IndexOfCustomFunction(const AName: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to GCustomFunctions.Count - 1 do
    if TJSONPathCustomFunction(GCustomFunctions[I]).Name = AName then
    begin
      Result := I;
      Exit;
    end;
end;

function IsValidFunctionName(const AName: string): Boolean;
var
  I: Integer;
  C: Char;
begin
  Result := (AName <> '') and TJSONPathLexer.IsLowerAlpha(AName[1]);
  if not Result then
    Exit;
  for I := 2 to Length(AName) do
  begin
    C := AName[I];
    if not (TJSONPathLexer.IsLowerAlpha(C) or (C = '_') or TJSONPathLexer.IsDigit(C)) then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

procedure InternalRegister(const AName: string;
  const AParams: array of TJSONPathValueType; AResultType: TJSONPathValueType;
  AHandler: TJSONPathFunctionHandler; AMethod: TJSONPathFunctionMethod);
var
  Entry: TJSONPathCustomFunction;
  Idx: Integer;
begin
  if not IsValidFunctionName(AName) then
    raise EJSONPathFunctionError.Create('Invalid function name "' + AName +
      '": use a lowercase letter followed by lowercase letters, digits or "_"');
  if IsBuiltinFunctionName(AName) then
    raise EJSONPathFunctionError.Create('"' + AName + '" is a built-in function and cannot be replaced');
  if AResultType = vtNodes then
    raise EJSONPathFunctionError.Create('Custom functions cannot return vtNodes');
  Entry := TJSONPathCustomFunction.Create(AName, AParams, AResultType, AHandler, AMethod);
  Idx := IndexOfCustomFunction(AName);
  if Idx >= 0 then
  begin
    GRetiredFunctions.Add(GCustomFunctions[Idx]);
    GCustomFunctions[Idx] := Entry;
  end
  else
    GCustomFunctions.Add(Entry);
end;

procedure RegisterJSONPathFunction(const AName: string;
  const AParams: array of TJSONPathValueType; AResultType: TJSONPathValueType;
  AHandler: TJSONPathFunctionHandler);
begin
  if not Assigned(AHandler) then
    raise EJSONPathFunctionError.Create('A handler is required for function "' + AName + '"');
  InternalRegister(AName, AParams, AResultType, AHandler, nil);
end;

procedure RegisterJSONPathFunction(const AName: string;
  const AParams: array of TJSONPathValueType; AResultType: TJSONPathValueType;
  AHandler: TJSONPathFunctionMethod);
begin
  if not Assigned(AHandler) then
    raise EJSONPathFunctionError.Create('A handler is required for function "' + AName + '"');
  InternalRegister(AName, AParams, AResultType, nil, AHandler);
end;

function UnregisterJSONPathFunction(const AName: string): Boolean;
var
  Idx: Integer;
begin
  Idx := IndexOfCustomFunction(AName);
  Result := Idx >= 0;
  if Result then
  begin
    GRetiredFunctions.Add(GCustomFunctions[Idx]);
    GCustomFunctions.Delete(Idx);
  end;
end;

function IsJSONPathFunctionRegistered(const AName: string): Boolean;
begin
  Result := IndexOfCustomFunction(AName) >= 0;
end;

{ ---- function lookup (RFC 9535 section 2.4 built-ins + custom functions) ---- }

procedure SetBuiltin(var Sig: TJSONPathFunctionSignature; AKind: TJSONPathFunctionKind;
  const AParams: array of TJSONPathValueType; AResult: TJSONPathValueType);
var
  I: Integer;
begin
  Sig.Kind := AKind;
  SetLength(Sig.Params, Length(AParams));
  for I := 0 to High(AParams) do
    Sig.Params[I] := AParams[I];
  Sig.ParamCount := Length(AParams);
  Sig.ResultType := AResult;
  Sig.Custom := nil;
end;

function FindJSONPathFunction(const AName: string; out Sig: TJSONPathFunctionSignature): Boolean;
var
  Idx: Integer;
  Entry: TJSONPathCustomFunction;
begin
  Result := True;
  Sig.Custom := nil;
  if AName = 'length' then
    SetBuiltin(Sig, fkLength, [vtValue], vtValue)
  else if AName = 'count' then
    SetBuiltin(Sig, fkCount, [vtNodes], vtValue)
  else if AName = 'match' then
    SetBuiltin(Sig, fkMatch, [vtValue, vtValue], vtLogical)
  else if AName = 'search' then
    SetBuiltin(Sig, fkSearch, [vtValue, vtValue], vtLogical)
  else if AName = 'value' then
    SetBuiltin(Sig, fkValue, [vtNodes], vtValue)
  else
  begin
    Idx := IndexOfCustomFunction(AName);
    if Idx < 0 then
    begin
      Result := False;
      SetBuiltin(Sig, fkLength, [vtValue], vtValue);
      Exit;
    end;
    Entry := TJSONPathCustomFunction(GCustomFunctions[Idx]);
    SetBuiltin(Sig, fkCustom, Entry.Params, Entry.ResultType);
    Sig.Custom := Entry;
  end;
end;

{ ---- parser implementation ---- }

constructor TJSONPathParser.Create(const AQuery: string);
begin
  inherited Create;
  FLexer := TJSONPathLexer.Create(AQuery);
end;

destructor TJSONPathParser.Destroy;
begin
  FLexer.Free;
  inherited Destroy;
end;

procedure TJSONPathParser.EnterNesting;
begin
  Inc(FDepth);
  if FDepth > MAX_NESTING then
    FLexer.Fail('filter-selector', 'expression nesting is too deep');
end;

procedure TJSONPathParser.LeaveNesting;
begin
  Dec(FDepth);
end;

function TJSONPathParser.IsIntStart(C: Char): Boolean;
begin
  Result := TJSONPathLexer.IsDigit(C) or (C = '-');
end;

function TJSONPathParser.TryScanCompareOp(out Op: TJSONPathCompareOp): Boolean;
begin
  Result := True;
  Op := coEq;
  if FLexer.MatchToken('==') then
    Op := coEq
  else if FLexer.MatchToken('!=') then
    Op := coNe
  else if FLexer.MatchToken('<=') then
    Op := coLe
  else if FLexer.MatchToken('>=') then
    Op := coGe
  else if FLexer.MatchChar('<') then
    Op := coLt
  else if FLexer.MatchChar('>') then
    Op := coGt
  else
    Result := False;
end;

function TJSONPathParser.TryMatchOperator(const Op: string): Boolean;
var
  M: Integer;
begin
  M := FLexer.Mark;
  FLexer.SkipWhitespace;
  Result := FLexer.MatchToken(Op);
  if not Result then
    FLexer.Reset(M);
end;

{ ---- type checking helpers ---- }

procedure TJSONPathParser.RequireLogical(Expr: TJSONPathExpression; StartPos: Integer);
begin
  if Expr is TJSONPathLiteral then
    FLexer.FailAt(StartPos, 'test-expr',
      'a literal is not a valid test expression; compare it with another value')
  else if (Expr is TJSONPathFunctionCall)
    and (TJSONPathFunctionCall(Expr).ResultType = vtValue) then
    FLexer.FailAt(StartPos, 'test-expr',
      'function "' + TJSONPathFunctionCall(Expr).Name +
      '" returns a value and must be used in a comparison');
end;

procedure TJSONPathParser.CheckComparable(Expr: TJSONPathExpression; StartPos: Integer);
begin
  if Expr is TJSONPathLiteral then
    Exit;
  if Expr is TJSONPathQueryExpr then
  begin
    if not TJSONPathQueryExpr(Expr).Query.IsSingular then
      FLexer.FailAt(StartPos, 'comparable',
        'a non-singular query is not allowed in a comparison');
    Exit;
  end;
  if Expr is TJSONPathFunctionCall then
  begin
    if TJSONPathFunctionCall(Expr).ResultType <> vtValue then
      FLexer.FailAt(StartPos, 'comparable',
        'function "' + TJSONPathFunctionCall(Expr).Name +
        '" does not return a value and cannot be compared');
    Exit;
  end;
  FLexer.FailAt(StartPos, 'comparable', 'invalid operand in comparison');
end;

procedure TJSONPathParser.CheckArgument(Expr: TJSONPathExpression;
  ParamType: TJSONPathValueType; StartPos: Integer; const FuncName: string);
begin
  case ParamType of
    vtValue:
      begin
        if Expr is TJSONPathLiteral then
          Exit;
        if (Expr is TJSONPathQueryExpr) and TJSONPathQueryExpr(Expr).Query.IsSingular then
          Exit;
        if (Expr is TJSONPathFunctionCall)
          and (TJSONPathFunctionCall(Expr).ResultType = vtValue) then
          Exit;
        FLexer.FailAt(StartPos, 'function-argument',
          'function "' + FuncName + '" expects a value (literal, singular query or value function)');
      end;
    vtNodes:
      begin
        if Expr is TJSONPathQueryExpr then
          Exit;
        if (Expr is TJSONPathFunctionCall)
          and (TJSONPathFunctionCall(Expr).ResultType = vtNodes) then
          Exit;
        FLexer.FailAt(StartPos, 'function-argument',
          'function "' + FuncName + '" expects a query');
      end;
    vtLogical:
      begin
        if Expr is TJSONPathLiteral then
          FLexer.FailAt(StartPos, 'function-argument',
            'function "' + FuncName + '" expects a logical expression');
        if (Expr is TJSONPathFunctionCall)
          and (TJSONPathFunctionCall(Expr).ResultType = vtValue) then
          FLexer.FailAt(StartPos, 'function-argument',
            'function "' + FuncName + '" expects a logical expression');
      end;
  end;
end;

{ ---- productions ---- }

function TJSONPathParser.Parse: TJSONPathQueryNode;
var
  Node: TJSONPathQueryNode;
begin
  if FLexer.PeekChar <> '$' then
    FLexer.Fail('jsonpath-query', 'a query must start with the root identifier "$"');
  Node := ParseQueryBody;
  try
    if not FLexer.IsAtEnd then
      FLexer.Fail('jsonpath-query', 'unexpected input after the end of the query');
    Result := Node;
    Node := nil;
  finally
    Node.Free;
  end;
end;

{ jsonpath-query / rel-query: root-identifier or current-node-identifier,
  followed by segments }
function TJSONPathParser.ParseQueryBody: TJSONPathQueryNode;
var
  Node: TJSONPathQueryNode;
  Relative: Boolean;
begin
  if FLexer.MatchChar('$') then
    Relative := False
  else if FLexer.MatchChar('@') then
    Relative := True
  else
  begin
    FLexer.Fail('filter-query', '"$" or "@" expected');
    Relative := False;
  end;
  Node := TJSONPathQueryNode.Create(Relative);
  try
    ParseSegments(Node);
    Result := Node;
    Node := nil;
  finally
    Node.Free;
  end;
end;

procedure TJSONPathParser.ParseSegments(Query: TJSONPathQueryNode);
var
  M: Integer;
  C: Char;
  Seg: TJSONPathSegment;
begin
  while True do
  begin
    M := FLexer.Mark;
    FLexer.SkipWhitespace;
    C := FLexer.PeekChar;
    if (not FLexer.IsAtEnd) and ((C = '.') or (C = '[')) then
    begin
      Seg := ParseSegment;
      Query.AddSegment(Seg);
    end
    else
    begin
      FLexer.Reset(M);
      Break;
    end;
  end;
end;

function TJSONPathParser.ParseSegment: TJSONPathSegment;
begin
  if FLexer.LookingAt('..') then
    Result := ParseDescendantSegment
  else
    Result := ParseChildSegment;
end;

function TJSONPathParser.ParseChildSegment: TJSONPathSegment;
var
  Seg: TJSONPathSegment;
begin
  Seg := TJSONPathSegment.Create(False);
  try
    if FLexer.PeekChar = '[' then
      ParseBracketedSelection(Seg)
    else
    begin
      FLexer.ExpectChar('.', 'child-segment');
      ParseShorthand(Seg);
    end;
    Result := Seg;
    Seg := nil;
  finally
    Seg.Free;
  end;
end;

function TJSONPathParser.ParseDescendantSegment: TJSONPathSegment;
var
  Seg: TJSONPathSegment;
begin
  Seg := TJSONPathSegment.Create(True);
  try
    if not FLexer.MatchToken('..') then
      FLexer.Fail('descendant-segment', '".." expected');
    if FLexer.PeekChar = '[' then
      ParseBracketedSelection(Seg)
    else
      ParseShorthand(Seg);
    Result := Seg;
    Seg := nil;
  finally
    Seg.Free;
  end;
end;

{ wildcard-selector / member-name-shorthand (after "." or "..") }
procedure TJSONPathParser.ParseShorthand(Segment: TJSONPathSegment);
begin
  if FLexer.PeekChar = '*' then
    Segment.AddSelector(ParseWildcardSelector)
  else
    Segment.AddSelector(TJSONPathNameSelector.Create(FLexer.ScanNameShorthand));
end;

procedure TJSONPathParser.ParseBracketedSelection(Segment: TJSONPathSegment);
begin
  FLexer.ExpectChar('[', 'bracketed-selection');
  FLexer.SkipWhitespace;
  while True do
  begin
    Segment.AddSelector(ParseSelector);
    FLexer.SkipWhitespace;
    if FLexer.MatchChar(',') then
      FLexer.SkipWhitespace
    else
      Break;
  end;
  if not FLexer.MatchChar(']') then
    FLexer.Fail('bracketed-selection', '"," or "]" expected');
end;

function TJSONPathParser.ParseSelector: TJSONPathSelector;
var
  C: Char;
begin
  C := FLexer.PeekChar;
  if FLexer.IsAtEnd then
  begin
    FLexer.Fail('selector', 'selector expected');
    Result := nil;
  end
  else if (C = '''') or (C = '"') then
    Result := ParseNameSelector
  else if C = '*' then
    Result := ParseWildcardSelector
  else if C = '?' then
    Result := ParseFilterSelector
  else if IsIntStart(C) or (C = ':') then
  begin
    if IsSliceAhead then
      Result := ParseSlice
    else
      Result := ParseIndexSelector;
  end
  else
  begin
    FLexer.Fail('selector', 'selector expected (name, "*", index, slice or "?")');
    Result := nil;
  end;
end;

function TJSONPathParser.ParseNameSelector: TJSONPathNameSelector;
begin
  Result := TJSONPathNameSelector.Create(FLexer.ScanStringLiteral);
end;

function TJSONPathParser.ParseWildcardSelector: TJSONPathWildcardSelector;
begin
  FLexer.ExpectChar('*', 'wildcard-selector');
  Result := TJSONPathWildcardSelector.Create;
end;

function TJSONPathParser.ParseIndexSelector: TJSONPathIndexSelector;
begin
  Result := TJSONPathIndexSelector.Create(FLexer.ScanInt('index-selector'));
end;

{ Looks ahead (without consuming) to decide whether "[" starts a slice }
function TJSONPathParser.IsSliceAhead: Boolean;
var
  M: Integer;
begin
  M := FLexer.Mark;
  try
    if FLexer.PeekChar <> ':' then
    begin
      FLexer.ScanInt('index-selector');
      FLexer.SkipWhitespace;
    end;
    Result := FLexer.PeekChar = ':';
  finally
    FLexer.Reset(M);
  end;
end;

{ slice-selector = [start S] ":" S [end S] [":" [S step]] }
function TJSONPathParser.ParseSlice: TJSONPathSlice;
var
  Node: TJSONPathSlice;
begin
  Node := TJSONPathSlice.Create;
  try
    if FLexer.PeekChar <> ':' then
    begin
      Node.HasStart := True;
      Node.Start := FLexer.ScanInt('slice-selector');
      FLexer.SkipWhitespace;
    end;
    FLexer.ExpectChar(':', 'slice-selector');
    FLexer.SkipWhitespace;
    if IsIntStart(FLexer.PeekChar) then
    begin
      Node.HasEnd := True;
      Node.EndIndex := FLexer.ScanInt('slice-selector');
      FLexer.SkipWhitespace;
    end;
    if FLexer.MatchChar(':') then
    begin
      FLexer.SkipWhitespace;
      if IsIntStart(FLexer.PeekChar) then
      begin
        Node.HasStep := True;
        Node.Step := FLexer.ScanInt('slice-selector');
      end;
    end;
    Result := Node;
    Node := nil;
  finally
    Node.Free;
  end;
end;

{ filter-selector = "?" S logical-expr }
function TJSONPathParser.ParseFilterSelector: TJSONPathFilterSelector;
var
  Expr: TJSONPathExpression;
  StartPos: Integer;
begin
  EnterNesting;
  try
    FLexer.ExpectChar('?', 'filter-selector');
    FLexer.SkipWhitespace;
    StartPos := FLexer.Mark;
    Expr := ParseLogicalOrExpr;
    try
      RequireLogical(Expr, StartPos);
      Result := TJSONPathFilterSelector.Create(Expr);
      Expr := nil;
    finally
      Expr.Free;
    end;
  finally
    LeaveNesting;
  end;
end;

{ logical-or-expr = logical-and-expr *(S "||" S logical-and-expr) }
function TJSONPathParser.ParseLogicalOrExpr: TJSONPathExpression;
var
  Left, Right: TJSONPathExpression;
  Node: TJSONPathLogicalOr;
  StartPos, RightPos: Integer;
begin
  Right := nil;
  StartPos := FLexer.Mark;
  Left := ParseLogicalAndExpr;
  try
    while TryMatchOperator('||') do
    begin
      RequireLogical(Left, StartPos);
      FLexer.SkipWhitespace;
      RightPos := FLexer.Mark;
      Right := ParseLogicalAndExpr;
      RequireLogical(Right, RightPos);
      Node := TJSONPathLogicalOr.Create;
      Node.Left := Left;
      Node.Right := Right;
      Left := Node;
      Right := nil;
    end;
    Result := Left;
    Left := nil;
  finally
    Left.Free;
    Right.Free;
  end;
end;

{ logical-and-expr = basic-expr *(S "&&" S basic-expr) }
function TJSONPathParser.ParseLogicalAndExpr: TJSONPathExpression;
var
  Left, Right: TJSONPathExpression;
  Node: TJSONPathLogicalAnd;
  StartPos, RightPos: Integer;
begin
  Right := nil;
  StartPos := FLexer.Mark;
  Left := ParseBasicExpr;
  try
    while TryMatchOperator('&&') do
    begin
      RequireLogical(Left, StartPos);
      FLexer.SkipWhitespace;
      RightPos := FLexer.Mark;
      Right := ParseBasicExpr;
      RequireLogical(Right, RightPos);
      Node := TJSONPathLogicalAnd.Create;
      Node.Left := Left;
      Node.Right := Right;
      Left := Node;
      Right := nil;
    end;
    Result := Left;
    Left := nil;
  finally
    Left.Free;
    Right.Free;
  end;
end;

{ basic-expr = paren-expr / comparison-expr / test-expr.
  Operands that are bare literals/queries/functions are returned as such when
  no comparison operator follows; callers decide (via RequireLogical or
  CheckArgument) whether that is acceptable in their context. }
function TJSONPathParser.ParseBasicExpr: TJSONPathExpression;
var
  Negate: Boolean;
  Expr, Right: TJSONPathExpression;
  Op: TJSONPathCompareOp;
  Cmp: TJSONPathComparison;
  Neg: TJSONPathLogicalNot;
  StartPos, RightPos, AfterPrimary, OpPos: Integer;
begin
  Negate := FLexer.MatchChar('!');
  if Negate then
    FLexer.SkipWhitespace;
  StartPos := FLexer.Mark;
  Expr := nil;
  Right := nil;
  try
    if FLexer.PeekChar = '(' then
      Expr := ParseParenExpr
    else
    begin
      Expr := ParsePrimary;
      AfterPrimary := FLexer.Mark;
      FLexer.SkipWhitespace;
      OpPos := FLexer.Mark;
      if TryScanCompareOp(Op) then
      begin
        if Negate then
          FLexer.FailAt(OpPos, 'comparison-expr',
            'the "!" operator cannot be applied to a comparison; use parentheses');
        FLexer.SkipWhitespace;
        RightPos := FLexer.Mark;
        Right := ParsePrimary;
        CheckComparable(Expr, StartPos);
        CheckComparable(Right, RightPos);
        Cmp := TJSONPathComparison.Create;
        Cmp.Op := Op;
        Cmp.Left := Expr;
        Cmp.Right := Right;
        Expr := Cmp;
        Right := nil;
      end
      else
        FLexer.Reset(AfterPrimary);
    end;
    if Negate then
    begin
      RequireLogical(Expr, StartPos);
      Neg := TJSONPathLogicalNot.Create;
      Neg.Operand := Expr;
      Expr := Neg;
    end;
    Result := Expr;
    Expr := nil;
  finally
    Expr.Free;
    Right.Free;
  end;
end;

{ paren-expr = "(" S logical-expr S ")"  (the NOT prefix is handled by the caller;
  grouping is represented by the tree shape itself) }
function TJSONPathParser.ParseParenExpr: TJSONPathExpression;
var
  Inner: TJSONPathExpression;
  StartPos: Integer;
begin
  EnterNesting;
  try
    FLexer.ExpectChar('(', 'paren-expr');
    FLexer.SkipWhitespace;
    StartPos := FLexer.Mark;
    Inner := ParseLogicalOrExpr;
    try
      RequireLogical(Inner, StartPos);
      FLexer.SkipWhitespace;
      if not FLexer.MatchChar(')') then
        FLexer.Fail('paren-expr', '")" expected');
      Result := Inner;
      Inner := nil;
    finally
      Inner.Free;
    end;
  finally
    LeaveNesting;
  end;
end;

{ literal / filter-query / function-expr }
function TJSONPathParser.ParsePrimary: TJSONPathExpression;
var
  C: Char;
  NameStart: Integer;
  Name: string;
  Q: TJSONPathQueryNode;
begin
  C := FLexer.PeekChar;
  if FLexer.IsAtEnd then
  begin
    FLexer.Fail('basic-expr', 'expression expected');
    Result := nil;
  end
  else if (C = '$') or (C = '@') then
  begin
    Q := ParseQueryBody;
    Result := TJSONPathQueryExpr.Create(Q);
  end
  else if (C = '''') or (C = '"') or IsIntStart(C) then
    Result := ParseLiteral
  else if TJSONPathLexer.IsLowerAlpha(C) then
  begin
    NameStart := FLexer.Mark;
    Name := FLexer.ScanFunctionName;
    if FLexer.PeekChar = '(' then
      Result := ParseFunctionCall(Name, NameStart)
    else if Name = 'true' then
      Result := TJSONPathLiteral.Create(NewJSONBool(True))
    else if Name = 'false' then
      Result := TJSONPathLiteral.Create(NewJSONBool(False))
    else if Name = 'null' then
      Result := TJSONPathLiteral.Create(NewJSONNull)
    else
    begin
      FLexer.FailAt(NameStart, 'basic-expr',
        'unexpected identifier "' + Name + '"');
      Result := nil;
    end;
  end
  else
  begin
    FLexer.Fail('basic-expr', 'expression expected');
    Result := nil;
  end;
end;

function TJSONPathParser.ParseLiteral: TJSONPathLiteral;
var
  C: Char;
begin
  C := FLexer.PeekChar;
  if (C = '''') or (C = '"') then
    Result := TJSONPathLiteral.Create(NewJSONString(FLexer.ScanStringLiteral))
  else
    Result := TJSONPathLiteral.Create(NewJSONNumber(FLexer.ScanNumberLiteral));
end;

{ function-expr = function-name "(" S [function-argument *(S "," S function-argument)] S ")" }
function TJSONPathParser.ParseFunctionCall(const AName: string;
  NamePos: Integer): TJSONPathFunctionCall;
var
  Sig: TJSONPathFunctionSignature;
  Node: TJSONPathFunctionCall;
  Arg: TJSONPathExpression;
  ArgStart, Index: Integer;
  ParamType: TJSONPathValueType;
begin
  if not FindJSONPathFunction(AName, Sig) then
    FLexer.FailAt(NamePos, 'function-expr', 'unknown function "' + AName + '"');
  EnterNesting;
  try
    Node := TJSONPathFunctionCall.Create(AName, Sig);
    try
      FLexer.ExpectChar('(', 'function-expr');
      FLexer.SkipWhitespace;
      Index := 0;
      if FLexer.PeekChar <> ')' then
      begin
        repeat
          FLexer.SkipWhitespace;
          ArgStart := FLexer.Mark;
          Arg := ParseLogicalOrExpr;
          Node.AddArgument(Arg);
          if Index >= Sig.ParamCount then
            FLexer.FailAt(ArgStart, 'function-expr',
              'function "' + AName + '" takes ' + IntToStr(Sig.ParamCount) + ' argument(s)');
          ParamType := Sig.Params[Index];
          CheckArgument(Arg, ParamType, ArgStart, AName);
          Inc(Index);
          FLexer.SkipWhitespace;
        until not FLexer.MatchChar(',');
      end;
      FLexer.SkipWhitespace;
      if not FLexer.MatchChar(')') then
        FLexer.Fail('function-expr', '")" expected');
      if Index <> Sig.ParamCount then
        FLexer.FailAt(NamePos, 'function-expr',
          'function "' + AName + '" takes ' + IntToStr(Sig.ParamCount) + ' argument(s)');
      Result := Node;
      Node := nil;
    finally
      Node.Free;
    end;
  finally
    LeaveNesting;
  end;
end;

function ParseJSONPath(const AQuery: string): TJSONPathQueryNode;
var
  Parser: TJSONPathParser;
begin
  Parser := TJSONPathParser.Create(AQuery);
  try
    Result := Parser.Parse;
  finally
    Parser.Free;
  end;
end;

procedure FreeRegistry;
var
  I: Integer;
begin
  for I := 0 to GCustomFunctions.Count - 1 do
    TObject(GCustomFunctions[I]).Free;
  for I := 0 to GRetiredFunctions.Count - 1 do
    TObject(GRetiredFunctions[I]).Free;
  GCustomFunctions.Free;
  GRetiredFunctions.Free;
end;

initialization
  GCustomFunctions := TList.Create;
  GRetiredFunctions := TList.Create;

finalization
  FreeRegistry;

end.
