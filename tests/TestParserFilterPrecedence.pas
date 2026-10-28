{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestParserFilterPrecedence;

{$APPTYPE CONSOLE}

uses
  TestSupport, JSONPathParser;

var
  Q: TJSONPathQueryNode;
  E: TJSONPathExpression;

begin
  BeginSuite('Parser: filter operator precedence in the AST');
  Q := ParseJSONPath('$[?@.a || @.b && @.c]');
  try
  E := TJSONPathFilterSelector(Q.Segments[0].Selectors[0]).Expression;
  Check(E is TJSONPathLogicalOr, 'top node is OR');
  Check(TJSONPathLogicalOr(E).Right is TJSONPathLogicalAnd, 'AND binds tighter than OR');
  finally
  Q.Free;
  end;
  Q := ParseJSONPath('$[?(@.a || @.b) && @.c]');
  try
  E := TJSONPathFilterSelector(Q.Segments[0].Selectors[0]).Expression;
  Check(E is TJSONPathLogicalAnd, 'parentheses make AND the top node');
  Check(TJSONPathLogicalAnd(E).Left is TJSONPathLogicalOr, 'grouped OR is the left operand');
  finally
  Q.Free;
  end;
  Q := ParseJSONPath('$[?!@.a && @.b]');
  try
  E := TJSONPathFilterSelector(Q.Segments[0].Selectors[0]).Expression;
  Check(E is TJSONPathLogicalAnd, 'NOT binds tighter than AND');
  Check(TJSONPathLogicalAnd(E).Left is TJSONPathLogicalNot, 'left operand is a NOT');
  finally
  Q.Free;
  end;
  Q := ParseJSONPath('$[?@.a == 1]');
  try
  E := TJSONPathFilterSelector(Q.Segments[0].Selectors[0]).Expression;
  Check(E is TJSONPathComparison, 'comparison node');
  Check(TJSONPathComparison(E).Op = coEq, 'comparison operator is ==');
  finally
  Q.Free;
  end;
  Halt(EndSuite);
end.
