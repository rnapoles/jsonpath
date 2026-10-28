{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestParserSingularQueries;

{$APPTYPE CONSOLE}

uses
  TestSupport, JSONPathParser;

function IsSingular(const AQuery: string): Boolean;
var
  Q: TJSONPathQueryNode;
begin
  Q := ParseJSONPath(AQuery);
  try
    Result := Q.IsSingular;
  finally
    Q.Free;
  end;
end;

begin
  BeginSuite('Parser: singular query detection');
  Check(IsSingular('$.a.b'), 'names are singular');
  Check(IsSingular('$["a"][0][-1]'), 'names and indices are singular');
  Check(IsSingular('$'), 'the bare root is singular');
  Check(not IsSingular('$.*'), 'wildcard is not singular');
  Check(not IsSingular('$..a'), 'descendant segment is not singular');
  Check(not IsSingular('$[0,1]'), 'multiple selectors are not singular');
  Check(not IsSingular('$[0:1]'), 'slice is not singular');
  Check(not IsSingular('$[?@.a]'), 'filter is not singular');
  Halt(EndSuite);
end.
