{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestJSONEquality;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils, JSONPathJSON;

function Eq(const A, B: string): Boolean;
var
  VA, VB: TJSONValue;
begin
  VA := ParseJSON(A);
  try
    VB := ParseJSON(B);
    try
      Result := JSONEquals(VA, VB);
    finally
      VB.Free;
    end;
  finally
    VA.Free;
  end;
end;

begin
  BeginSuite('JSON: deep equality');
  Check(Eq('{"a":1,"b":2}', '{"b":2,"a":1}'), 'object equality ignores member order');
  Check(Eq('[1,2]', '[1,2]'), 'equal arrays');
  Check(not Eq('[1,2]', '[2,1]'), 'array order matters');
  Check(not Eq('1', '"1"'), 'number differs from string');
  Check(Eq('1.0', '1'), 'numbers compare by value');
  Check(not Eq('{"a":1}', '{"a":1,"b":2}'), 'different member counts');
  Check(Eq('null', 'null'), 'null equals null');
  Check(not Eq('null', 'false'), 'null differs from false');
  Halt(EndSuite);
end.
