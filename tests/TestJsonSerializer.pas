{$IFDEF FPC}{$MODE DELPHI}{$modeswitch prefixedattributes}{$ENDIF}
{$H+}
{$M+}
program TestJsonSerializer;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils, Classes, JSONPathJSON, JsonSerializer;

type
  TColor = (clRed, clGreen);
  TIntArray = array of Integer;

  TAddress = class
  private
    FCity: string;
  published
    property City: string read FCity write FCity;
  end;

  TPerson = class
  private
    FName: string;
    FAge: Integer;
    FActive: Boolean;
    FScore: Double;
    FColor: TColor;
    FAddress: TAddress;
    FNumbers: TIntArray;
    FTags: TStringList;
  published
    [JsonName('full_name')]
    property Name: string read FName write FName;
    property Age: Integer read FAge write FAge;
    property Active: Boolean read FActive write FActive;
    property Score: Double read FScore write FScore;
    property Color: TColor read FColor write FColor;
    property Address: TAddress read FAddress write FAddress;
    property Numbers: TIntArray read FNumbers write FNumbers;
    property Tags: TStringList read FTags write FTags;
  end;

  TLoop = class
  private
    FSelf: TLoop;
  published
    property Me: TLoop read FSelf write FSelf;
  end;

function SerializeCity(const ACity: string): string;
var
  A: TAddress;
begin
  A := TAddress.Create;
  try
    A.City := ACity;
    Result := TJsonSerializer.SerializeToText(A);
  finally
    A.Free;
  end;
end;

var
  P: TPerson;
  A: TAddress;
  V: TJSONValue;
  L: TLoop;
  Raised: Boolean;

begin
  BeginSuite('JsonSerializer: object to TJSONValue');
  P := TPerson.Create;
  A := TAddress.Create;
  try
    P.Name := 'Ann';
    P.Age := 30;
    P.Active := True;
    P.Score := 1.5;
    P.Color := clGreen;
    SetLength(P.FNumbers, 2);
    P.FNumbers[0] := 1;
    P.FNumbers[1] := 2;
    P.FTags := TStringList.Create;
    P.FTags.Add('x');
    P.FTags.Add('y');
    V := TJsonSerializer.Serialize(P);
    try
      Check(V.Kind = jkObject, 'an object serializes to a JSON object');
      Check(V.FindMember('full_name') <> nil, 'JsonName attribute renames the key');
      Check(V.FindMember('Name') = nil, 'the original property name is not used');
      CheckEqualsStr('Ann', V.FindMember('full_name').StringValue, 'string property value');
      CheckEqualsInt(30, Trunc(V.FindMember('Age').NumberValue), 'integer property value');
      Check(V.FindMember('Active').BoolValue, 'boolean property value');
      Check(V.FindMember('Score').NumberValue = 1.5, 'float property value');
      CheckEqualsStr('clGreen', V.FindMember('Color').StringValue, 'enumeration becomes its identifier');
      Check(V.FindMember('Address').Kind = jkNull, 'nil object property becomes null');
      CheckEqualsStr('[1,2]', JSONToText(V.FindMember('Numbers')), 'dynamic array becomes a JSON array');
      CheckEqualsStr('["x","y"]', JSONToText(V.FindMember('Tags')), 'TStrings becomes an array of strings');
    finally
      V.Free;
    end;

    P.Address := A;
    A.City := 'Oslo';
    V := TJsonSerializer.Serialize(P);
    try
      CheckEqualsStr('Oslo', V.FindMember('Address').FindMember('City').StringValue,
        'nested objects are serialized recursively');
    finally
      V.Free;
    end;
  finally
    P.FTags.Free;
    A.Free;
    P.Free;
  end;

  V := TJsonSerializer.Serialize(nil);
  try
    Check(V.Kind = jkNull, 'nil serializes to null');
  finally
    V.Free;
  end;

  L := TLoop.Create;
  try
    L.Me := L;
    Raised := False;
    try
      TJsonSerializer.Serialize(L).Free;
    except
      on EJsonSerializerError do
        Raised := True;
    end;
    Check(Raised, 'a self-referencing object raises EJsonSerializerError');
  finally
    L.Free;
  end;

  CheckEqualsStr('{"City":"x"}', SerializeCity('x'), 'SerializeToText gives compact JSON');
  Halt(EndSuite);
end.
