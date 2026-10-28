{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program SampleStore;

{ Runs ten JSONPath queries against the classic "store" document and prints,
  for each one, the query text, the number of matches, the matched values
  and their normalized paths.

  Build (Free Pascal):  fpc -Mdelphi -Fu.. SampleStore.pas
  Build (Delphi):       dcc64 -U.. SampleStore.pas }

{$APPTYPE CONSOLE}

uses
  SysUtils, JSONPathJSON, JSONPathLexer, JSONPathQuery;

const
  StoreJson =
    '{' +
    '  "store": {' +
    '    "book": [' +
    '      {"category": "reference", "author": "Nigel Rees",' +
    '       "title": "Sayings of the Century", "price": 8.95},' +
    '      {"category": "fiction", "author": "Evelyn Waugh",' +
    '       "title": "Sword of Honour", "price": 12.99},' +
    '      {"category": "fiction", "author": "Herman Melville",' +
    '       "title": "Moby Dick", "isbn": "0-553-21311-3", "price": 8.99},' +
    '      {"category": "fiction", "author": "J. R. R. Tolkien",' +
    '       "title": "The Lord of the Rings", "isbn": "0-395-19395-8", "price": 22.99}' +
    '    ],' +
    '    "bicycle": {"color": "red", "price": 399}' +
    '  },' +
    ' "expensive": 10' +
    '}';

  QueryCount = 11;
  Queries: array[1..QueryCount] of string = (
    '$.store.bicycle.color',
    '$.store.book[*].title',
    '$.store.book[0].author',
    '$.store.book[-1]',
    '$.store.book[?(@.price < 10)]',
    '$.store.book[?(@.category == ''fiction'')].title',
    '$..price',
    '$.store.book[?(@.price >= 10 && @.price <= 20)]',
    '$.store.book[1:3]',
    '$..[?(@.author)]',
    '$.store.book[?(@.price > $.expensive)].title'
  );

var
  Doc: TJSONValue;
  Path: TJSONPath;
  Res: TJSONPathResult;
  I, J: Integer;

begin
  Doc := ParseJSON(StoreJson);
  try
    for I := 1 to QueryCount do
    begin
      WriteLn(I, '. ', Queries[I]);
      try
        Path := TJSONPath.Create(Queries[I]);
        try
          Res := Path.Evaluate(Doc);
          try
            WriteLn('   matches: ', Res.Count);
            WriteLn('   result:  ', Res.ToJSONText);
            for J := 0 to Res.Count - 1 do
              WriteLn('   path:    ', Res.Paths[J]);
          finally
            Res.Free;
          end;
        finally
          Path.Free;
        end;
      except
        on E: EJSONPathParseException do
          WriteLn('   syntax error: ', E.Message);
      end;
      WriteLn;
    end;
  finally
    Doc.Free;
  end;
end.
