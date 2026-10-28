{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestSchemaRegex;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils, JsonSchemaRegex;

function Translate(const APattern: string): string;
var
  AnchorStart, AnchorEnd: Boolean;
  Text: string;
begin
  Text := TranslateEcmaPattern(APattern, AnchorStart, AnchorEnd);
  Result := Text + '|' + IntToStr(Ord(AnchorStart)) + IntToStr(Ord(AnchorEnd));
end;

function Finds(const APattern, AText: string): Boolean;
var
  Rx: TSchemaRegex;
begin
  Rx := TSchemaRegex.Create(APattern);
  try
    Result := Rx.Search(AText);
  finally
    Rx.Free;
  end;
end;

function Unsupported(const APattern: string): Boolean;
begin
  Result := False;
  try
    Translate(APattern);
    Finds(APattern, 'x');
  except
    on EJsonSchemaRegexError do
      Result := True;
  end;
end;

var
  Cache: TSchemaRegexCache;
  Msg: string;
  First, Second: TSchemaRegex;
begin
  BeginSuite('Schema: ECMA pattern translation');
  CheckEqualsStr('[0-9]+|11', Translate('^\d+$'), 'digits and both anchors');
  CheckEqualsStr('a\.b|00', Translate('a\.b'), 'escaped dot stays escaped');
  CheckEqualsStr('a/b|00', Translate('a\/b'), 'escaped slash loses its backslash');
  CheckEqualsStr('(a)|00', Translate('(?:a)'), 'non-capturing groups become groups');
  CheckEqualsStr('a+|00', Translate('a+?'), 'lazy quantifiers become greedy');
  CheckEqualsStr('[0-9_]|00', Translate('[\d_]'), 'class escapes inside brackets');
  CheckEqualsStr('[ \t\n\r]*|00', Translate('\s*'), 'whitespace class');
  CheckEqualsStr('[^0-9]|00', Translate('\D'), 'negated digit class');
  CheckEqualsStr('a$b|00', Translate('a\$b'), 'an escaped dollar is a literal');
  CheckEqualsStr('abc|10', Translate('^abc'), 'only the start anchored');
  CheckEqualsStr('abc|01', Translate('abc$'), 'only the end anchored');

  Check(Finds('^a', 'ab'), 'start anchor matches at the start');
  Check(not Finds('^a', 'ba'), 'start anchor does not match later');
  Check(Finds('a$', 'ba'), 'end anchor matches at the end');
  Check(not Finds('a$', 'ab'), 'end anchor does not match earlier');
  Check(Finds('^a$', 'a') and not Finds('^a$', 'aa'), 'both anchors need a full match');
  Check(Finds('b', 'abc'), 'no anchors: substring search');
  Check(Finds('\d+', 'ab12'), 'digits');
  Check(not Finds('\d+', 'ab'), 'no digits');
  Check(Finds('^[\w-]+$', 'ab-1_c'), 'word characters and hyphen');
  Check(Finds('(?:ab)+$', 'xxabab'), 'repeated group at the end');
  Check(Finds('^(a|b)c$', 'bc'), 'alternation in a group');

  Check(Unsupported('a^b'), 'a caret in the middle is unsupported');
  Check(Unsupported('a$b'), 'a dollar in the middle is unsupported');
  Check(Unsupported('\bfoo'), 'word boundaries are unsupported');
  Check(Unsupported('(?=a)'), 'lookahead is unsupported');
  Check(Unsupported('(?<n>a)'), 'named groups are unsupported');
  Check(Unsupported('\p{L}'), 'unicode properties are unsupported');
  Check(Unsupported('\1'), 'back-references are unsupported');
  Check(Unsupported('[\D]'), 'negated class escapes inside brackets are unsupported');
  Check(Unsupported('a\'), 'a trailing backslash is invalid');
  Check(Unsupported('('), 'unbalanced parentheses are invalid');

  Cache := TSchemaRegexCache.Create;
  try
    First := Cache.Get('^a$', Msg);
    Second := Cache.Get('^a$', Msg);
    Check((First <> nil) and (First = Second), 'the cache compiles each pattern once');
    Check(Cache.Get('(?=a)', Msg) = nil, 'unusable patterns yield nil');
    Check(Msg <> '', 'unusable patterns come with a message');
    Msg := '';
    Check(Cache.Get('(?=a)', Msg) = nil, 'unusable patterns are cached too');
    Check(Msg <> '', 'the cached message is returned again');
    Check(Cache.Search('^a', 'ab') and not Cache.Search('(?=a)', 'a'), 'Search treats unusable patterns as no match');
  finally
    Cache.Free;
  end;
  Halt(EndSuite);
end.
