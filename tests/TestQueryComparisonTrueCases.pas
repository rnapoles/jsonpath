{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryComparisonTrueCases;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '{"obj": {"x": "y"}, "arr": [2, 3]}';

begin
  BeginSuite('Query: comparison semantics (true cases)');
  Check(ExprIsTrue(Doc, '$.absent1 == $.absent2'), 'empty nodelists are equal');
  Check(ExprIsTrue(Doc, '$.absent1 <= $.absent2'), 'equality implies <= for empty nodelists');
  Check(ExprIsTrue(Doc, '$.absent != ''g'''), 'absent is not equal to a value');
  Check(ExprIsTrue(Doc, '1 <= 2'), 'numeric <=');
  Check(ExprIsTrue(Doc, '''a'' <= ''b'''), 'string <=');
  Check(ExprIsTrue(Doc, '$.obj != $.arr'), 'object differs from array');
  Check(ExprIsTrue(Doc, '$.obj == $.obj'), 'object equals itself');
  Check(ExprIsTrue(Doc, '$.arr == $.arr'), 'array equals itself');
  Check(ExprIsTrue(Doc, '$.obj != 17'), 'object differs from number');
  Check(ExprIsTrue(Doc, '$.obj <= $.obj'), 'object <= itself');
  Check(ExprIsTrue(Doc, '$.arr <= $.arr'), 'array <= itself');
  Check(ExprIsTrue(Doc, 'true <= true'), 'boolean <= itself');
  Halt(EndSuite);
end.
