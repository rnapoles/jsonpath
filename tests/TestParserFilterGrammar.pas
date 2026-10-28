{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestParserFilterGrammar;

{$APPTYPE CONSOLE}

uses
  TestSupport;

begin
  BeginSuite('Parser: filter selector grammar');
  Check(QueryParses('$[?@.a]'), 'existence test');
  Check(QueryParses('$[?(@.a)]'), 'parenthesised existence test');
  Check(QueryParses('$[?!@.a]'), 'negated existence test');
  Check(QueryParses('$[?!(@.a == 1)]'), 'negated parenthesis');
  Check(QueryParses('$[?@.a==1]'), 'comparison with literal');
  Check(QueryParses('$[?@.a  ==  1]'), 'comparison with spaces');
  Check(QueryParses('$[?@.a==$.b]'), 'comparison with root query');
  Check(QueryParses('$[?@.a && @.b || @.c]'), 'and / or chain');
  Check(QueryParses('$[?@.a==''x'']'), 'string literal comparison');
  Check(QueryParses('$[?@.a==true || @.b==false || @.c==null]'), 'boolean and null literals');
  Check(QueryParses('$[?@.a==-1.5e3]'), 'number literal forms');
  Check(QueryParses('$[? @.a]'), 'filter with whitespace after question mark');
  Check(not QueryParses('$[?]'), 'empty filter');
  Check(not QueryParses('$[?@.a==]'), 'missing right operand');
  Check(not QueryParses('$[?1]'), 'bare literal is not a test expression');
  Check(not QueryParses('$[?!@.a==1]'), 'not applied to a comparison');
  Check(not QueryParses('$[?@.a=1]'), 'single equals sign');
  Check(not QueryParses('$[?(@.a]'), 'unbalanced parenthesis');
  Check(not QueryParses('$[?@.a &&]'), 'dangling and');
  Check(not QueryParses('$[?@.a==01]'), 'leading zero in number literal');
  Check(not QueryParses('$[?@.* == 1]'), 'non-singular query in comparison');
  Check(not QueryParses('$[?@[0:2] == 1]'), 'slice in comparison query');
  Check(not QueryParses('$[?@.a == foo]'), 'unknown bare identifier');
  Halt(EndSuite);
end.
