{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestJSONParseOptions;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils, JSONPathJSON;

function Opts(AComments, ATrailing: Boolean; ADup: TDuplicateKeyPolicy;
  ADepth: Integer): TJSONParseOptions;
begin
  Result := DefaultJSONParseOptions;
  Result.AllowComments := AComments;
  Result.AllowTrailingCommas := ATrailing;
  Result.DuplicateKeys := ADup;
  Result.MaxDepth := ADepth;
end;

{ compact text of the parsed document, or "ERR line:column" }
function Run(const AText: string; const AOptions: TJSONParseOptions): string;
var
  V: TJSONValue;
begin
  try
    V := ParseJSON(AText, AOptions);
    try
      Result := JSONToText(V);
    finally
      V.Free;
    end;
  except
    on E: EJSONPathJSONError do
      Result := 'ERR ' + IntToStr(E.Line) + ':' + IntToStr(E.Column);
  end;
end;

function Strict(const AText: string): string;
begin
  Result := Run(AText, DefaultJSONParseOptions);
end;

function Lenient(const AText: string): string;
begin
  Result := Run(AText, LenientJSONParseOptions);
end;

function Dup(const AText: string; APolicy: TDuplicateKeyPolicy): string;
begin
  Result := Run(AText, Opts(False, False, APolicy, 512));
end;

function Deep(const AText: string; ADepth: Integer): string;
begin
  Result := Run(AText, Opts(False, False, dkLastWins, ADepth));
end;

var
  E1: EJSONPathJSONError;
  Position, Line, Column: Integer;
  Message: string;
begin
  BeginSuite('JSON: parser options and error positions');

  { defaults }
  Check(not DefaultJSONParseOptions.AllowComments, 'comments are off by default');
  Check(not DefaultJSONParseOptions.AllowTrailingCommas, 'trailing commas are off by default');
  Check(DefaultJSONParseOptions.DuplicateKeys = dkLastWins, 'the last duplicate wins by default');
  CheckEqualsInt(512, DefaultJSONParseOptions.MaxDepth, 'the default depth limit is 512');
  Check(LenientJSONParseOptions.AllowComments and LenientJSONParseOptions.AllowTrailingCommas,
    'the lenient preset enables comments and trailing commas');

  { comments }
  CheckEqualsStr('ERR 1:5', Strict('[1, // c' + #10 + '2]'), 'strict mode rejects line comments');
  CheckEqualsStr('ERR 1:5', Strict('[1, /* c */ 2]'), 'strict mode rejects block comments');
  CheckEqualsStr('[1,2]', Lenient('[1, // c' + #10 + '2]'), 'line comments are skipped');
  CheckEqualsStr('[1,2]', Lenient('[1, /* c */ 2]'), 'block comments are skipped');
  CheckEqualsStr('{"a":1}', Lenient('{/* a */"a"/* b */:/* c */1/* d */}'), 'comments between every token');
  CheckEqualsStr('"a // b /* c */"', Lenient('"a // b /* c */"'), 'comment markers inside strings are text');
  CheckEqualsStr('5', Lenient('// head' + #10 + '5 // tail'), 'comments before and after the document');
  CheckEqualsStr('5', Lenient('/* multi' + #10 + 'line */ 5'), 'block comments may span lines');
  CheckEqualsStr('ERR 1:4', Lenient('[1 /* x'), 'an unterminated block comment is reported at its start');
  CheckEqualsStr('ERR 1:4', Lenient('[1 / 2]'), 'a lone slash is not a comment');
  CheckEqualsStr('1', Lenient('1 //x'), 'a line comment may end the document');

  { trailing commas }
  CheckEqualsStr('ERR 1:4', Strict('[1,]'), 'strict mode rejects a trailing comma in arrays');
  CheckEqualsStr('ERR 1:8', Strict('{"a":1,}'), 'strict mode rejects a trailing comma in objects');
  CheckEqualsStr('[1]', Lenient('[1,]'), 'a trailing comma in an array is accepted');
  CheckEqualsStr('{"a":1}', Lenient('{"a":1,}'), 'a trailing comma in an object is accepted');
  CheckEqualsStr('[1]', Lenient('[1, /* x */ ]'), 'a trailing comma may be followed by a comment');
  CheckEqualsStr('[[1],{"a":[2]}]', Lenient('[[1,],{"a":[2,],},]'), 'nested trailing commas');
  CheckEqualsStr('ERR 1:2', Lenient('[,]'), 'a lone comma is still an error');
  CheckEqualsStr('ERR 1:4', Lenient('[1,,2]'), 'a double comma is still an error');
  CheckEqualsStr('ERR 1:2', Lenient('{,}'), 'a lone comma in an object is still an error');
  CheckEqualsStr('[1]', Run('[1,]', Opts(False, True, dkLastWins, 512)), 'trailing commas can be enabled alone');
  CheckEqualsStr('ERR 1:4', Run('[1,// x' + #10 + ']', Opts(False, True, dkLastWins, 512)), 'comments stay off when only commas are enabled');

  { duplicate keys }
  CheckEqualsStr('{"a":2}', Dup('{"a":1,"a":2}', dkLastWins), 'last wins');
  CheckEqualsStr('{"a":1}', Dup('{"a":1,"a":2}', dkFirstWins), 'first wins');
  CheckEqualsStr('ERR 1:8', Dup('{"a":1,"a":2}', dkError), 'duplicates can be errors (reported at the repeated key)');
  CheckEqualsStr('{"a":3,"b":2}', Dup('{"a":1,"b":2,"a":3}', dkLastWins), 'last wins keeps the position of the first occurrence');
  CheckEqualsStr('{"a":1,"b":2}', Dup('{"a":1,"b":2,"a":3}', dkFirstWins), 'first wins ignores later values');
  CheckEqualsStr('{"a":1}', Dup('{"a":1,"a":{"b":[1,2]}}', dkFirstWins), 'ignored values may be containers');
  CheckEqualsStr('{"o":{"a":2},"p":{"a":1}}', Dup('{"o":{"a":1,"a":2},"p":{"a":1}}', dkLastWins), 'duplicates are per object');
  CheckEqualsStr('{"a":1,"b":{"a":2}}', Dup('{"a":1,"b":{"a":2}}', dkError), 'the same name in different objects is fine');

  { depth limit }
  CheckEqualsStr('[[[]]]', Deep('[[[]]]', 3), 'depth 3 is allowed with MaxDepth 3');
  CheckEqualsStr('ERR 1:4', Deep('[[[[]]]]', 3), 'depth 4 is rejected with MaxDepth 3');
  CheckEqualsStr('[1,2,3]', Deep('[1,2,3]', 1), 'scalars do not count');
  CheckEqualsStr('ERR 1:2', Deep('[[1]]', 1), 'nested arrays count');
  CheckEqualsStr('ERR 1:6', Deep('{"a":{"b":1}}', 1), 'nested objects count');
  CheckEqualsStr('[[1],[2],[3]]', Deep('[[1],[2],[3]]', 2), 'siblings do not add up');
  CheckEqualsStr('ERR 1:1', Deep('[]', 0), 'MaxDepth 0 rejects every container');
  CheckEqualsStr('7', Deep('7', 0), 'MaxDepth 0 still allows scalars');
  Check(Strict(StringOfChar('[', 512) + StringOfChar(']', 512)) <> 'ERR 1:513', 'the default limit allows 512 levels');
  CheckEqualsStr('ERR 1:513', Strict(StringOfChar('[', 513) + StringOfChar(']', 513)), 'the default limit rejects 513 levels');

  { error positions }
  CheckEqualsStr('ERR 2:8', Strict('{' + #10 + '  "a": tru' + #10 + '}'), 'line and column of a bad literal');
  CheckEqualsStr('ERR 2:2', Strict('[1,' + #13#10 + ' x]'), 'CRLF counts as one line break');
  CheckEqualsStr('ERR 1:5', Strict('"abc'), 'an unterminated string is reported at the end');
  CheckEqualsStr('ERR 1:1', Strict(''), 'empty input');
  CheckEqualsStr('ERR 1:3', Strict('1 x'), 'trailing characters');
  CheckEqualsStr('ERR 1:3', Strict('[01]'), 'a leading zero is reported where the problem shows');
  CheckEqualsStr('ERR 1:1', Strict('1e999'), 'a number out of range is reported at its start');
  CheckEqualsStr('ERR 3:1', Strict('[' + #10 + '1' + #10 + '}'), 'a wrong closing bracket');

  try
    ParseJSON('{' + #10 + '  "a": tru' + #10 + '}').Free;
  except
    on E: EJSONPathJSONError do
    begin
      Position := E.Position;
      Line := E.Line;
      Column := E.Column;
      Message := E.Message;
    end;
  end;
  CheckEqualsInt(9, Position, 'the exception carries the 0-based offset');
  CheckEqualsInt(2, Line, 'the exception carries the line');
  CheckEqualsInt(8, Column, 'the exception carries the column');
  Check(Pos('line 2, column 8', Message) > 0, 'the message mentions line and column');

  E1 := EJSONPathJSONError.CreateAt('x', 5);
  try
    CheckEqualsInt(5, E1.Position, 'CreateAt keeps the offset');
    CheckEqualsInt(0, E1.Line, 'CreateAt has no line information');
  finally
    E1.Free;
  end;
  Halt(EndSuite);
end.
