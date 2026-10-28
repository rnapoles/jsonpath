{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestParserSlices;

{$APPTYPE CONSOLE}

uses
  TestSupport, JSONPathParser;

var
  Q: TJSONPathQueryNode;
  S: TJSONPathSlice;

begin
  BeginSuite('Parser: slice selector fields');
  Q := ParseJSONPath('$[1:3]');
  try
  S := TJSONPathSlice(Q.Segments[0].Selectors[0]);
  Check(S.HasStart and S.HasEnd and not S.HasStep, 'start and end present, no step');
  CheckEqualsInt(1, S.Start, 'start value');
  CheckEqualsInt(3, S.EndIndex, 'end value');
  CheckEqualsInt(1, S.EffectiveStep, 'default step is 1');
  finally
  Q.Free;
  end;
  Q := ParseJSONPath('$[::-2]');
  try
  S := TJSONPathSlice(Q.Segments[0].Selectors[0]);
  Check(not S.HasStart and not S.HasEnd and S.HasStep, 'only step present');
  CheckEqualsInt(-2, S.EffectiveStep, 'negative step value');
  finally
  Q.Free;
  end;
  Q := ParseJSONPath('$[ 1 : 2 : 3 ]');
  try
  S := TJSONPathSlice(Q.Segments[0].Selectors[0]);
  CheckEqualsInt(3, S.EffectiveStep, 'whitespace inside a slice is allowed');
  finally
  Q.Free;
  end;
  Check(QueryParses('$[:]'), 'fully open slice parses');
  Check(QueryParses('$[1:2:]'), 'empty step after the second colon parses');
  Check(not QueryParses('$[1:2:3:4]'), 'too many colons are rejected');
  Check(not QueryParses('$[1::0x]'), 'garbage after a slice is rejected');
  Halt(EndSuite);
end.
