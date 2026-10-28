{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestParserErrorPositions;

{$APPTYPE CONSOLE}

uses
  TestSupport, JSONPathLexer, JSONPathParser;

begin
  BeginSuite('Parser: exception coordinates');
  CheckEqualsInt(0, QueryErrorOffset('x'), 'missing root is reported at offset 0');
  CheckEqualsInt(4, QueryErrorOffset('$.a.'), 'dangling dot is reported at the end');
  CheckEqualsInt(2, QueryErrorOffset('$['), 'missing selector is reported after the bracket');
  CheckEqualsInt(3, QueryErrorOffset('$.a b'), 'trailing garbage is reported at its start');
  CheckEqualsInt(9, QueryErrorOffset('$[?@.a ==]'), 'missing operand is reported at the bracket');
  CheckEqualsInt(2, QueryErrorOffset('$[01]'), 'leading zero is reported at the number');
  CheckEqualsInt(2, QueryErrorOffset('$[''abc'), 'unterminated string is reported at its opening quote');
  CheckEqualsInt(-1, QueryErrorOffset('$.a'), 'valid queries report no error');
  CheckEqualsStr('member-name-shorthand', QueryErrorRule('$.a.'), 'rule name for a missing member name');
  CheckEqualsStr('test-expr', QueryErrorRule('$[?1]'), 'rule name for a bare literal');
  CheckEqualsStr('function-expr', QueryErrorRule('$[?foo(@)]'), 'rule name for an unknown function');
  try
  ParseJSONPath('$'#10'.').Free;
  except
  on E: EJSONPathParseException do
  begin
    CheckEqualsInt(2, E.Line, 'line number counts line feeds');
    CheckEqualsInt(2, E.Column, 'column is relative to the line start');
    CheckEqualsStr('<end of input>', E.UnexpectedToken, 'unexpected token at the end of input');
  end;
  end;
  Halt(EndSuite);
end.
