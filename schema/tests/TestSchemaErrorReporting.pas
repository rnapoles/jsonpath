{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestSchemaErrorReporting;

{$APPTYPE CONSOLE}

uses
  TestSupport, SchemaTestSupport, SysUtils, JSONPathJSON, JsonSchemaErrors, JsonSchemaValidator;

procedure ModeTests;
var
  V: TJsonSchemaValidator;
  R: TValidationResult;
  Errs: TValidationErrors;
  Raised: Boolean;
  Doc, Inst: TJSONValue;
begin
  V := NewValidator;
  try
    V.RegisterSchema('s', '{"type":"integer","minimum":3}');
    { return mode (default): no exception for invalid instances }
    R := V.ValidateText('"x"', 's');
    try
      Check(not R.IsValid, 'return mode: the result is invalid');
      CheckEqualsInt(1, R.Errors.Count, 'return mode: errors are available on the result');
      CheckEqualsStr('type', R.Errors[0].Keyword, 'return mode: the violated keyword is recorded');
      Check(R.ErrorText <> '', 'ErrorText describes the errors');
      Errs := R.DetachErrors;
      try
        CheckEqualsInt(1, Errs.Count, 'DetachErrors hands the list to the caller');
        Check(R.IsValid, 'a result without errors is valid');
      finally
        Errs.Free;
      end;
    finally
      R.Free;
    end;
    { raise mode }
    V.ErrorMode := emRaise;
    Raised := False;
    try
      V.ValidateText('"x"', 's').Free;
    except
      on E: EValidationError do
      begin
        Raised := True;
        CheckEqualsInt(1, E.Errors.Count, 'raise mode: the exception carries the errors');
        CheckEqualsStr('type', E.Errors[0].Keyword, 'raise mode: the keyword is recorded');
        Check(Pos('"s"', E.Message) > 0, 'raise mode: the message names the schema');
      end;
    end;
    Check(Raised, 'raise mode raises EValidationError for invalid instances');
    R := V.ValidateText('5', 's');
    try
      Check(R.IsValid, 'raise mode still returns a result for valid instances');
    finally
      R.Free;
    end;
    { schema problems are never EValidationError }
    Raised := False;
    try
      V.RegisterSchema('broken', '{"type":"nope"}');
    except
      on E: EValidationError do
        Raised := False;
      on E: ESchemaError do
        Raised := True;
    end;
    Check(Raised, 'invalid schemas raise ESchemaError, not EValidationError, in raise mode too');
    V.ErrorMode := emReturn;
    { StopOnFirstError }
    V.RegisterSchema('two', '{"properties":{"a":{"type":"integer"}},"required":["b"]}');
    R := V.ValidateText('{"a":"x"}', 'two');
    try
      CheckEqualsInt(2, R.Errors.Count, 'by default all errors are collected');
    finally
      R.Free;
    end;
    V.StopOnFirstError := True;
    R := V.ValidateText('{"a":"x"}', 'two');
    try
      CheckEqualsInt(1, R.Errors.Count, 'StopOnFirstError stops after the first failing keyword');
    finally
      R.Free;
    end;
    V.StopOnFirstError := False;
    { ad-hoc schema }
    Doc := ParseJSON('{"type":"string"}');
    Inst := ParseJSON('5');
    try
      R := V.ValidateWithSchema(Inst, Doc);
    finally
      Doc.Free;
      Inst.Free;
    end;
    try
      Check(not R.IsValid, 'ValidateWithSchema validates against an unregistered schema');
    finally
      R.Free;
    end;
    { misuse }
    Raised := False;
    try
      V.Validate(nil, 's').Free;
    except
      on EJsonSchemaError do
        Raised := True;
    end;
    Check(Raised, 'a nil instance raises EJsonSchemaError');
    Raised := False;
    try
      V.ValidateText('{bad', 's').Free;
    except
      on EJsonSchemaError do
        Raised := True;
    end;
    Check(Raised, 'instance text that is not JSON raises EJsonSchemaError');
    Raised := False;
    try
      V.ValidateText('1', 'unknown-id').Free;
    except
      on ESchemaRegistrationError do
        Raised := True;
    end;
    Check(Raised, 'an unknown schema id raises ESchemaRegistrationError');
    Inst := ParseJSON('5');
    try
      Check(V.IsValid(Inst, 's'), 'IsValid is a shortcut for Validate');
    finally
      Inst.Free;
    end;
  finally
    V.Free;
  end;
end;

begin
  BeginSuite('Schema: error collection, locations and error modes');
  CheckEqualsStr('type@/a;required@', ErrorSummary('{"properties":{"a":{"type":"integer"}},"required":["b"]}', '{"a":"x"}'), 'keyword and instance location, several errors');
  CheckEqualsStr('/properties/a/type;/required', ErrorSchemaLocations('{"properties":{"a":{"type":"integer"}},"required":["b"]}', '{"a":"x"}'), 'schema locations of those errors');
  CheckEqualsStr('type@/0;type@/2', ErrorSummary('{"items":{"type":"integer"}}', '["a",1,"b"]'), 'one error per failing array element');
  CheckEqualsStr('type@/a~1b;type@/m~0n', ErrorSummary('{"properties":{"a/b":{"type":"integer"},"m~n":{"type":"integer"}}}', '{"a/b":"x","m~n":"y"}'), 'pointer escaping of / and ~');
  CheckEqualsStr('anyOf@', ErrorSummary('{"anyOf":[{"type":"integer"},{"type":"string"}]}', 'null'), 'anyOf reports one error');
  CheckEqualsStr('oneOf@', ErrorSummary('{"oneOf":[{"type":"integer"},{"minimum":3}]}', '5'), 'oneOf reports one error');
  CheckEqualsStr('@/a', ErrorSummary('{"properties":{"a":false}}', '{"a":1}'), 'false schema reports no keyword');
  CheckEqualsStr('required@;required@', ErrorSummary('{"required":["a","b"]}', '{}'), 'every missing property is reported');
  CheckEqualsStr('type@/list/1/n', ErrorSummary('{"properties":{"list":{"items":{"properties":{"n":{"type":"integer"}}}}}}', '{"list":[{"n":1},{"n":"x"}]}'), 'deep instance locations');
  CheckEqualsStr('/properties/a/$ref/type', ErrorSchemaLocations('{"$defs":{"d":{"type":"integer"}},"properties":{"a":{"$ref":"#/$defs/d"}}}', '{"a":"x"}'), 'schema location follows $ref');
  CheckEqualsStr('/allOf/0/type', ErrorSchemaLocations('{"allOf":[{"type":"integer"},{"minimum":3}]}', '"x"'), 'schema location inside allOf');
  Check(Pos('greater than or equal to 5', FirstErrorMessage('{"minimum":5}', '1')) > 0, 'messages describe the violation');
  ModeTests;
  Halt(EndSuite);
end.
