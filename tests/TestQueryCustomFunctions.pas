{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryCustomFunctions;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils, JSONPathJSON, JSONPathParser, JSONPathQuery;

type
  TCalc = class
  public
    Calls: Integer;
    function Twice(Args: TJSONPathArgs): TJSONPathFuncResult;
  end;

function TCalc.Twice(Args: TJSONPathArgs): TJSONPathFuncResult;
begin
  Inc(Calls);
  if Args.IsNumber(0) then
    Result := FuncNumber(Args.AsNumber(0) * 2)
  else
    Result := FuncNothing;
end;

function FnUpper(Args: TJSONPathArgs): TJSONPathFuncResult;
begin
  if Args.IsString(0) then
    Result := FuncString(UpperCase(Args.AsString(0)))
  else
    Result := FuncNothing;
end;

function FnShout(Args: TJSONPathArgs): TJSONPathFuncResult;
begin
  if Args.IsString(0) then
    Result := FuncString(UpperCase(Args.AsString(0)) + '!')
  else
    Result := FuncNothing;
end;

function FnBetween(Args: TJSONPathArgs): TJSONPathFuncResult;
begin
  Result := FuncLogical((Args.AsNumber(0, -1) >= Args.AsNumber(1)) and
    (Args.AsNumber(0, -1) <= Args.AsNumber(2)));
end;

function FnFirst(Args: TJSONPathArgs): TJSONPathFuncResult;
begin
  if Args.NodeCount(0) > 0 then
    Result := FuncValue(Args.Node(0, 0))
  else
    Result := FuncNothing;
end;

function FnIsEmpty(Args: TJSONPathArgs): TJSONPathFuncResult;
begin
  Result := FuncLogical(Args.IsNothing(0));
end;

function FnNegate(Args: TJSONPathArgs): TJSONPathFuncResult;
begin
  Result := FuncLogical(not Args.AsBoolean(0));
end;

function FnLabel(Args: TJSONPathArgs): TJSONPathFuncResult;
begin
  if Args.AsBoolean(0) then
    Result := FuncString('yes')
  else
    Result := FuncBool(False);
end;

function RegistrationFails(const AName: string; AResult: TJSONPathValueType): Boolean;
begin
  Result := False;
  try
    RegisterJSONPathFunction(AName, [vtValue], AResult, FnUpper);
  except
    on EJSONPathFunctionError do
      Result := True;
  end;
end;

const
  People =
    '[{"n":"ann","age":30},{"n":"bob","age":12},{"n":"cy","age":70},{"n":3}]';

var
  Calc: TCalc;
  Doc: TJSONValue;
  Path: TJSONPath;
  Res: TJSONPathResult;

begin
  BeginSuite('Query: custom functions');
  RegisterJSONPathFunction('upper', [vtValue], vtValue, FnUpper);
  RegisterJSONPathFunction('between', [vtValue, vtValue, vtValue], vtLogical, FnBetween);
  TJSONPath.RegisterFunction('first', [vtNodes], vtValue, FnFirst);
  RegisterJSONPathFunction('is_empty', [vtValue], vtLogical, FnIsEmpty);
  RegisterJSONPathFunction('negate', [vtLogical], vtLogical, FnNegate);
  RegisterJSONPathFunction('label', [vtLogical], vtValue, FnLabel);

  Check(IsJSONPathFunctionRegistered('upper'), 'registered functions are reported');
  Check(not IsJSONPathFunctionRegistered('nope'), 'unknown functions are not reported');

  CheckEqualsStr('[{"n":"ann","age":30}]', QueryValues(People, '$[?upper(@.n) == "ANN"]'),
    'value function returning a string');
  CheckEqualsStr('[{"n":"ann","age":30},{"n":"cy","age":70}]',
    QueryValues(People, '$[?between(@.age, 18, 99)]'),
    'logical function used as a test expression');
  CheckEqualsStr('[{"n":"bob","age":12}]',
    QueryValues(People, '$[?!between(@.age, 18, 99) && @.age]'),
    'logical function can be negated and combined');
  CheckEqualsStr('[{"a":[30,31]}]',
    QueryValues('[{"a":[30,31]},{"a":[]}]', '$[?first(@.a[*]) == 30]'),
    'nodes argument gives access to the selected values');
  CheckEqualsStr('[{"n":3}]', QueryValues(People, '$[?is_empty(@.age)]'),
    'empty value argument is reported by IsNothing');
  CheckEqualsStr('[{"n":3}]', QueryValues(People, '$[?negate(@.age)]'),
    'logical parameter receives the existence test result');
  CheckEqualsInt(3, QueryCount(People, '$[?label(@.age) == "yes"]'),
    'value function with a logical parameter');
  CheckEqualsInt(1, QueryCount(People, '$[?label(@.age) == false]'),
    'FuncBool results compare as JSON booleans');

  { type checking uses the registered signatures }
  Check(not QueryParses('$[?upper(@.*) == "A"]'), 'non-singular query for a value parameter is rejected');
  Check(not QueryParses('$[?between(@.a, 1)]'), 'too few arguments are rejected');
  Check(not QueryParses('$[?between(@.a, 1, 2, 3)]'), 'too many arguments are rejected');
  Check(not QueryParses('$[?between(@.a, 1, 2) == true]'), 'logical result in a comparison is rejected');
  Check(not QueryParses('$[?upper(@.n)]'), 'value result used as a test is rejected');
  Check(not QueryParses('$[?first(1) == 1]'), 'literal for a nodes parameter is rejected');
  Check(QueryParses('$[?upper(@.n) == "A" && between(@.age, 1, 2)]'), 'custom functions combine in one filter');

  { registration rules }
  Check(RegistrationFails('Upper', vtValue), 'uppercase names are rejected');
  Check(RegistrationFails('', vtValue), 'empty names are rejected');
  Check(RegistrationFails('1a', vtValue), 'names starting with a digit are rejected');
  Check(RegistrationFails('a-b', vtValue), 'names with a hyphen are rejected');
  Check(RegistrationFails('length', vtValue), 'built-in names cannot be replaced');
  Check(RegistrationFails('nodes_result', vtNodes), 'vtNodes results are rejected');

  { replacing a function }
  RegisterJSONPathFunction('upper', [vtValue], vtValue, FnShout);
  CheckEqualsStr('[{"n":"ann","age":30}]', QueryValues(People, '$[?upper(@.n) == "ANN!"]'),
    're-registering a name replaces the implementation');

  { method handlers and unregistering }
  Calc := TCalc.Create;
  try
    RegisterJSONPathFunction('twice', [vtValue], vtValue, Calc.Twice);
    CheckEqualsStr('[3]', QueryValues('[3,4]', '$[?twice(@) == 6]'), 'method handler works');
    CheckEqualsInt(2, Calc.Calls, 'the method is called once per candidate node');

    Doc := ParseJSON('[3,4]');
    try
      Path := TJSONPath.Create('$[?twice(@) == 6]');
      try
        Check(UnregisterJSONPathFunction('twice'), 'unregistering a known function succeeds');
        Check(not UnregisterJSONPathFunction('twice'), 'unregistering twice reports False');
        Res := Path.Evaluate(Doc);
        try
          CheckEqualsStr('[3]', Res.ToJSONText, 'an already parsed query keeps working');
        finally
          Res.Free;
        end;
      finally
        Path.Free;
      end;
    finally
      Doc.Free;
    end;
    Check(not QueryParses('$[?twice(@) == 6]'), 'unregistered functions are unknown to new queries');
  finally
    Calc.Free;
  end;

  UnregisterJSONPathFunction('upper');
  UnregisterJSONPathFunction('between');
  UnregisterJSONPathFunction('first');
  UnregisterJSONPathFunction('is_empty');
  UnregisterJSONPathFunction('negate');
  UnregisterJSONPathFunction('label');
  Halt(EndSuite);
end.
