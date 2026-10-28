{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
unit JsonSerializer;

(* Converts an object graph into a TJSONValue (from JSONPathJSON) using RTTI.

    uses JsonSerializer, JSONPathJSON;

    {$M+}                              // FPC: needed for a published section
    type
      TPerson = class
      private
        FName: string;
        FAge: Integer;
      published
        [JsonName('full_name')]        // FPC: {$modeswitch prefixedattributes}
        property Name: string read FName write FName;
        property Age: Integer read FAge write FAge;
      end;

    V := TJsonSerializer.Serialize(Person);   // {"full_name":"Ann","Age":30}
    try
      WriteLn(JSONToTextPretty(V, 2));
    finally
      V.Free;
    end;

  What is serialized
    * Every readable, non-indexed property RTTI exposes. Delphi's default RTTI
      includes public and published properties; Free Pascal exposes published
      properties only (put the class under {$M+} and use "published").
    * A property is written under its JsonName attribute value if it has
      one, otherwise under its own name.
    * Integers and floats -> numbers (TDateTime is a float, so also a number);
      Boolean -> true/false; other enumerations -> their identifier as a
      string; string and character types -> strings; nested objects -> JSON
      objects (nil -> null); TStrings -> array of strings; dynamic and static
      arrays -> JSON arrays.
    * Sets, records, variants, interfaces, methods and pointers are written
      as null.
    * Object cycles are detected by a nesting-depth limit and raise
      EJsonSerializerError. *)

interface

uses
  SysUtils, Classes,
{$IFDEF FPC}
  TypInfo, Rtti,
{$ELSE}
  System.TypInfo, System.Rtti,
{$ENDIF}
  JSONPathJSON;

type
  EJsonSerializerError = class(Exception);

  { Maps a property to a specific JSON key name }
  JsonNameAttribute = class(TCustomAttribute)
  private
    FName: string;
  public
    constructor Create(const AName: string); virtual;
    property Name: string read FName;
  end;

  TJsonSerializer = class
  private
    FDepth: Integer;
    FMaxDepth: Integer;
    function ValueToJSON(const AValue: TValue): TJSONValue;
    function ObjectToJSON(AObject: TObject): TJSONValue;
  public
    constructor Create;
    { Converts AObject (may be nil) to a JSON value. The caller owns the
      result and must free it. }
    function ToJSONValue(AObject: TObject): TJSONValue;
    { Convenience wrappers around a temporary serializer }
    class function Serialize(AObject: TObject): TJSONValue;
    { Compact text when Ident <= 0, pretty-printed otherwise }
    class function SerializeToText(AObject: TObject; Ident: Integer = 0): string;
    { Maximum object nesting before a cycle is assumed (default 64) }
    property MaxDepth: Integer read FMaxDepth write FMaxDepth;
  end;

implementation

const
{$IFDEF FPC}
  StringKinds = [tkSString, tkLString, tkAString, tkWString, tkUString, tkChar, tkWChar, tkUChar];
  IntegerKinds = [tkInteger, tkInt64];
{$ELSE}
  StringKinds = [tkString, tkLString, tkWString, tkUString, tkChar, tkWChar];
  IntegerKinds = [tkInteger, tkInt64];
{$ENDIF}

{ JsonNameAttribute }

constructor JsonNameAttribute.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
end;

{ TJsonSerializer }

constructor TJsonSerializer.Create;
begin
  inherited Create;
  FMaxDepth := 64;
end;

function TJsonSerializer.ValueToJSON(const AValue: TValue): TJSONValue;
var
  I: Integer;
  Node: TJSONValue;
begin
  Result := nil;
  if AValue.IsEmpty then
  begin
    Result := NewJSONNull;
    Exit;
  end;
{$IFDEF FPC}
  if AValue.Kind = tkBool then
  begin
    Result := NewJSONBool(AValue.AsBoolean);
    Exit;
  end;
{$ENDIF}
  if AValue.Kind = tkEnumeration then
  begin
    if AValue.TypeInfo = TypeInfo(Boolean) then
      Result := NewJSONBool(AValue.AsBoolean)
    else
      Result := NewJSONString(GetEnumName(AValue.TypeInfo, Integer(AValue.AsOrdinal)));
  end
  else if AValue.Kind in IntegerKinds then
    Result := NewJSONInt64(AValue.AsInt64)
  else if AValue.Kind = tkFloat then
    Result := NewJSONNumber(AValue.AsExtended)
  else if AValue.Kind in StringKinds then
    Result := NewJSONString(AValue.AsString)
  else if AValue.Kind = tkClass then
    Result := ObjectToJSON(AValue.AsObject)
  else if AValue.IsArray then
  begin
    Node := NewJSONArray;
    try
      for I := 0 to AValue.GetArrayLength - 1 do
        Node.AddItem(ValueToJSON(AValue.GetArrayElement(I)));
      Result := Node;
      Node := nil;
    finally
      Node.Free;
    end;
  end
  else
    Result := NewJSONNull;
end;

function TJsonSerializer.ObjectToJSON(AObject: TObject): TJSONValue;
var
  Ctx: TRttiContext;
  Node: TJSONValue;
  Prop: TRttiProperty;
  Attr: TCustomAttribute;
  Key: string;
  I: Integer;
begin
  Result := nil;
  if AObject = nil then
  begin
    Result := NewJSONNull;
    Exit;
  end;
  Inc(FDepth);
  try
    if FDepth > FMaxDepth then
      raise EJsonSerializerError.Create(
        'Maximum nesting depth exceeded; the object graph probably contains a cycle');
    if AObject is TStrings then
    begin
      Node := NewJSONArray;
      try
        for I := 0 to TStrings(AObject).Count - 1 do
          Node.AddItem(NewJSONString(TStrings(AObject)[I]));
        Result := Node;
        Node := nil;
      finally
        Node.Free;
      end;
    end
    else
    begin
      Node := NewJSONObject;
      try
        Ctx := TRttiContext.Create;
        try
          for Prop in Ctx.GetType(AObject.ClassType).GetProperties do
          begin
            if not Prop.IsReadable then
              Continue;
            Key := Prop.Name;
            for Attr in Prop.GetAttributes do
              if Attr is JsonNameAttribute then
                Key := JsonNameAttribute(Attr).Name;
            Node.SetMember(Key, ValueToJSON(Prop.GetValue(AObject)));
          end;
        finally
          Ctx.Free;
        end;
        Result := Node;
        Node := nil;
      finally
        Node.Free;
      end;
    end;
  finally
    Dec(FDepth);
  end;
end;

function TJsonSerializer.ToJSONValue(AObject: TObject): TJSONValue;
begin
  FDepth := 0;
  Result := ObjectToJSON(AObject);
end;

class function TJsonSerializer.Serialize(AObject: TObject): TJSONValue;
var
  S: TJsonSerializer;
begin
  S := TJsonSerializer.Create;
  try
    Result := S.ToJSONValue(AObject);
  finally
    S.Free;
  end;
end;

class function TJsonSerializer.SerializeToText(AObject: TObject; Ident: Integer): string;
var
  V: TJSONValue;
begin
  V := Serialize(AObject);
  try
    if Ident > 0 then
      Result := JSONToTextPretty(V, Ident)
    else
      Result := JSONToText(V);
  finally
    V.Free;
  end;
end;

end.
