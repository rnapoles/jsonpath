{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestParserSelectorKinds;

{$APPTYPE CONSOLE}

uses
  TestSupport, JSONPathParser;

var
  Q: TJSONPathQueryNode;
  Seg: TJSONPathSegment;

begin
  BeginSuite('Parser: AST selector node types');
  Q := ParseJSONPath('$["a",1,*,1:2,?@.a]');
  try
  Seg := Q.Segments[0];
  CheckEqualsInt(5, Seg.SelectorCount, 'five selectors in one segment');
  Check(Seg.Selectors[0] is TJSONPathNameSelector, 'first is a name selector');
  Check(Seg.Selectors[1] is TJSONPathIndexSelector, 'second is an index selector');
  Check(Seg.Selectors[2] is TJSONPathWildcardSelector, 'third is a wildcard');
  Check(Seg.Selectors[3] is TJSONPathSlice, 'fourth is a slice');
  Check(Seg.Selectors[4] is TJSONPathFilterSelector, 'fifth is a filter');
  Check(not Seg.IsDescendant, 'a plain bracket is a child segment');
  finally
  Q.Free;
  end;
  Q := ParseJSONPath('$..a');
  try
  Check(Q.Segments[0].IsDescendant, 'double dot makes a descendant segment');
  Check(not Q.IsRelative, 'root query is absolute');
  finally
  Q.Free;
  end;
  Halt(EndSuite);
end.
