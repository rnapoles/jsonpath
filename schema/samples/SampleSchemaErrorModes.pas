{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program SampleSchemaErrorModes;

{ Return-based and exception-based error handling, and the difference between
  invalid schemas and invalid instances.

  Build (Free Pascal, from this folder):
    fpc -Mdelphi -Fu../.. -Fu.. SampleSchemaErrorModes.pas }

{$APPTYPE CONSOLE}

uses
  SysUtils, JsonSchemaErrors, JsonSchemaValidator;

var
  V: TJsonSchemaValidator;
  R: TValidationResult;
  I: Integer;
begin
  V := TJsonSchemaValidator.Create;
  try
    V.RegisterSchema('age', '{"type":"integer","minimum":0,"maximum":150}');

    WriteLn('--- return mode (default) ---');
    V.ErrorMode := emReturn;
    R := V.ValidateText('200', 'age');
    try
      WriteLn('valid: ', R.IsValid);
      for I := 0 to R.Errors.Count - 1 do
        WriteLn('  keyword=', R.Errors[I].Keyword, ' instance="', R.Errors[I].InstanceLocation,
          '" schema="', R.Errors[I].SchemaLocation, '" : ', R.Errors[I].Message);
    finally
      R.Free;
    end;

    WriteLn('--- raise mode ---');
    V.ErrorMode := emRaise;
    try
      V.ValidateText('"old"', 'age').Free;
    except
      on E: EValidationError do
      begin
        WriteLn('EValidationError: ', E.Message);
        for I := 0 to E.Errors.Count - 1 do
          WriteLn('  ', E.Errors[I].Describe);
      end;
    end;
    R := V.ValidateText('42', 'age'); { valid instances still return a result }
    try
      WriteLn('42 valid: ', R.IsValid);
    finally
      R.Free;
    end;

    WriteLn('--- invalid schemas are always exceptions ---');
    try
      V.RegisterSchema('broken', '{"type":"integr","minimum":"zero"}');
    except
      on E: ESchemaError do
      begin
        WriteLn('ESchemaError: ', E.Message);
        for I := 0 to E.Errors.Count - 1 do
          WriteLn('  ', E.Errors[I].Describe);
      end;
    end;

    WriteLn('--- collecting every error of one instance ---');
    V.ErrorMode := emReturn;
    V.RegisterSchema('user',
      '{"type":"object","required":["id","name"],' +
      '"properties":{"id":{"type":"integer"},"tags":{"items":{"type":"string"}}}}');
    R := V.ValidateText('{"id":"x","tags":[1,"a",2]}', 'user');
    try
      WriteLn(R.ErrorText);
    finally
      R.Free;
    end;
  finally
    V.Free;
  end;
end.
