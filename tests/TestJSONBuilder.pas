{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestJSONBuilder;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils, JSONPathJSON;

{ 0 = no error, 1 = EJSONBuilderError, 2 = EJSONPathJSONError }
function Misuse(AKind: Integer; out AMessage: string): Integer;
var
  B: TJSONBuilder;
  V: TJSONValue;
begin
  Result := 0;
  AMessage := '';
  B := TJSONBuilder.Create;
  try
    try
      case AKind of
        1: B.BeginObject.AddString('x');
        2: B.BeginArray.PutString('a', 'b');
        3: B.PutString('a', 'b');
        4: B.EndArray;
        5: B.BeginArray.EndObject;
        6: B.BeginObject.EndArray;
        7:
          begin
            V := B.BeginObject.Build;
            V.Free;
          end;
        8:
          begin
            V := B.Build;
            V.Free;
          end;
        9: B.AddInt(1).AddInt(2);
        10: B.BeginObject.EndObject.AddString('late');
        11: B.AddNumberText('01');
        12: B.AddValue(nil);
        13: B.BeginObject.PutValue('k', nil);
        14: B.BeginArray('named');
      end;
    except
      on E: EJSONBuilderError do
      begin
        Result := 1;
        AMessage := E.Message;
      end;
      on E: EJSONPathJSONError do
      begin
        Result := 2;
        AMessage := E.Message;
      end;
    end;
  finally
    B.Free;
  end;
end;

function Built(B: TJSONBuilder): string;
var
  V: TJSONValue;
begin
  V := B.Build;
  try
    Result := JSONToText(V);
  finally
    V.Free;
  end;
end;

var
  B: TJSONBuilder;
  V: TJSONValue;
  Msg: string;
begin
  BeginSuite('JSON: fluent builder');

  B := TJSONBuilder.Create;
  try
    B.BeginObject
      .PutString('name', 'Ann')
      .PutInt('id', 9223372036854775807)
      .PutDecimal('price', 1999, 2)
      .PutBool('active', True)
      .PutNull('nothing')
      .BeginArray('tags').AddString('a').AddString('b').EndArray
      .BeginObject('address').PutString('city', 'Oslo').EndObject
      .PutNumber('ratio', 0.5)
      .PutNumberText('big', '12345678901234567890123')
    .EndObject;
    CheckEqualsStr('{"name":"Ann","id":9223372036854775807,"price":19.99,"active":true,"nothing":null,' +
      '"tags":["a","b"],"address":{"city":"Oslo"},"ratio":0.5,"big":12345678901234567890123}',
      Built(B), 'a nested document with exact numbers');

    B.BeginArray
      .BeginObject.PutInt('a', 1).EndObject
      .BeginObject.PutInt('a', 2).EndObject
    .EndArray;
    CheckEqualsStr('[{"a":1},{"a":2}]', Built(B), 'an array of objects; the builder is reusable after Build');

    B.AddInt(5);
    CheckEqualsStr('5', Built(B), 'a scalar root');
    B.AddNull;
    CheckEqualsStr('null', Built(B), 'a null root');

    B.BeginObject.PutInt('a', 1).PutInt('a', 2).EndObject;
    CheckEqualsStr('{"a":2}', Built(B), 'a repeated member name replaces the value');

    B.BeginObject.PutValue('k', ParseJSON('[1,2]')).EndObject;
    CheckEqualsStr('{"k":[1,2]}', Built(B), 'PutValue takes ownership of an existing value');

    B.BeginArray.AddValue(ParseJSON('{"x":1}')).AddBool(False).AddNumber(1.5).AddDecimal(-5, 2).EndArray;
    CheckEqualsStr('[{"x":1},false,1.5,-0.05]', Built(B), 'AddValue and the other Add methods');

    Check(B.BeginArray = B, 'Begin returns the builder itself');
    CheckEqualsInt(1, B.Depth, 'Depth counts open containers');
    Check(B.BeginObject = B, 'BeginObject returns the builder itself');
    CheckEqualsInt(2, B.Depth, 'Depth with two open containers');
    B.EndObject.EndArray;
    CheckEqualsInt(0, B.Depth, 'Depth is 0 when everything is closed');
    V := B.Build;
    try
      CheckEqualsStr('[{}]', JSONToText(V), 'the document built above');
    finally
      V.Free;
    end;
  finally
    B.Free;
  end;

  CheckEqualsInt(1, Misuse(1, Msg), 'Add... inside an object is an error');
  Check(Pos('Put', Msg) > 0, 'the message points to Put...');
  CheckEqualsInt(1, Misuse(2, Msg), 'Put... inside an array is an error');
  CheckEqualsInt(1, Misuse(3, Msg), 'Put... at the root is an error');
  CheckEqualsInt(1, Misuse(4, Msg), 'EndArray without an open array is an error');
  CheckEqualsInt(1, Misuse(5, Msg), 'EndObject while an array is open is an error');
  CheckEqualsInt(1, Misuse(6, Msg), 'EndArray while an object is open is an error');
  CheckEqualsInt(1, Misuse(7, Msg), 'Build with an open container is an error');
  Check(Pos('1 container', Msg) > 0, 'the message counts the open containers');
  CheckEqualsInt(1, Misuse(8, Msg), 'Build without any value is an error');
  CheckEqualsInt(1, Misuse(9, Msg), 'a second root value is an error');
  Check(Pos('root', Msg) > 0, 'the message mentions the root');
  CheckEqualsInt(1, Misuse(10, Msg), 'values after a finished root are an error');
  CheckEqualsInt(2, Misuse(11, Msg), 'an invalid number text raises EJSONPathJSONError');
  CheckEqualsInt(1, Misuse(12, Msg), 'AddValue(nil) is an error');
  CheckEqualsInt(1, Misuse(13, Msg), 'PutValue(name, nil) is an error');
  CheckEqualsInt(1, Misuse(14, Msg), 'a named Begin at the root is an error');

  { an unfinished document is freed with the builder }
  B := TJSONBuilder.Create;
  B.BeginObject.BeginArray('a').AddInt(1);
  B.Free;
  Check(True, 'freeing a builder with open containers does not leak or crash');
  Halt(EndSuite);
end.
