{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestQueryComparisonFalseCases;

{$APPTYPE CONSOLE}

uses
  TestSupport;

const
  Doc =
    '{"obj": {"x": "y"}, "arr": [2, 3]}';

begin
  BeginSuite('Query: comparison semantics (false cases)');
  Check(not ExprIsTrue(Doc, '$.absent == ''g'''), 'absent is not equal to a value (==)');
  Check(not ExprIsTrue(Doc, '$.absent1 != $.absent2'), 'empty nodelists are not unequal');
  Check(not ExprIsTrue(Doc, '1 > 2'), 'numeric >');
  Check(not ExprIsTrue(Doc, '13 == ''13'''), 'number is not equal to string');
  Check(not ExprIsTrue(Doc, '''a'' > ''b'''), 'string >');
  Check(not ExprIsTrue(Doc, '$.obj == $.arr'), 'object is not equal to array');
  Check(not ExprIsTrue(Doc, '$.obj != $.obj'), 'object is not unequal to itself');
  Check(not ExprIsTrue(Doc, '$.arr != $.arr'), 'array is not unequal to itself');
  Check(not ExprIsTrue(Doc, '$.obj == 17'), 'object is not equal to number');
  Check(not ExprIsTrue(Doc, '$.obj <= $.arr'), 'object <= array is false');
  Check(not ExprIsTrue(Doc, '$.obj < $.arr'), 'object < array is false');
  Check(not ExprIsTrue(Doc, '1 <= $.arr'), 'number <= array is false');
  Check(not ExprIsTrue(Doc, '1 >= $.arr'), 'number >= array is false');
  Check(not ExprIsTrue(Doc, '1 > $.arr'), 'number > array is false');
  Check(not ExprIsTrue(Doc, '1 < $.arr'), 'number < array is false');
  Check(not ExprIsTrue(Doc, 'true > true'), 'boolean > is false');
  Halt(EndSuite);
end.
