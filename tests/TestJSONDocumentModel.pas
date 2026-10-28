{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestJSONDocumentModel;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils, JSONPathJSON;

var
  O, A: TJSONValue;

begin
  BeginSuite('JSON: building and inspecting documents');
  O := NewJSONObject;
  try
  O.SetMember('a', NewJSONNumber(1));
  O.SetMember('b', NewJSONString('x'));
  O.SetMember('a', NewJSONNumber(2));
  CheckEqualsInt(2, O.Count, 'replacing a member does not add one');
  CheckEqualsStr('a', O.Names[0], 'first member name');
  Check(O.FindMember('a').NumberValue = 2, 'replaced value is visible');
  Check(O.FindMember('zzz') = nil, 'missing member returns nil');
  CheckEqualsStr('{"a":2,"b":"x"}', JSONToText(O), 'serialization');
  finally
  O.Free;
  end;
  A := NewJSONArray;
  try
  A.AddItem(NewJSONBool(True));
  A.AddItem(NewJSONNull);
  CheckEqualsInt(2, A.Count, 'array element count');
  Check(A[0].BoolValue, 'array element access');
  Check(A[1].Kind = jkNull, 'null element kind');
  finally
  A.Free;
  end;
  Halt(EndSuite);
end.
