{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestSchemaStrings;

{$APPTYPE CONSOLE}

uses
  TestSupport, SchemaTestSupport;

begin
  BeginSuite('Schema: string keywords');
  Check(not SchemaAccepts('{"minLength":2}', '"a"'), 'minLength');
  Check(SchemaAccepts('{"minLength":2}', '"ab"'), 'minLength boundary');
  Check(SchemaAccepts('{"minLength":2}', '5'), 'minLength ignores numbers');
  Check(not SchemaAccepts('{"maxLength":1}', '"ab"'), 'maxLength');
  Check(SchemaAccepts('{"maxLength":1}', '"\ud83d\ude00"'), 'length counts code points, not UTF-16 units');
  Check(SchemaAccepts('{"pattern":"^[a-z]+$"}', '"abc"'), 'pattern anchored both ends');
  Check(not SchemaAccepts('{"pattern":"^[a-z]+$"}', '"ab1"'), 'pattern rejects digits');
  Check(not SchemaAccepts('{"pattern":"^[a-z]+$"}', '""'), 'plus needs one character');
  Check(SchemaAccepts('{"pattern":"abc"}', '"xxabcxx"'), 'pattern is a search by default');
  Check(not SchemaAccepts('{"pattern":"abc"}', '"xyz"'), 'search miss');
  Check(SchemaAccepts('{"pattern":"\\d{3}"}', '"a123"'), 'digit class');
  Check(not SchemaAccepts('{"pattern":"\\d{3}"}', '"12"'), 'digit class miss');
  Check(SchemaAccepts('{"pattern":"^\\d{3}-\\d{4}$"}', '"555-1234"'), 'anchored phone pattern');
  Check(not SchemaAccepts('{"pattern":"^\\d{3}-\\d{4}$"}', '"5555-123"'), 'anchored phone miss');
  Check(SchemaAccepts('{"pattern":"(?:ab)+c"}', '"xababc"'), 'non-capturing group');
  Check(not SchemaAccepts('{"pattern":"(?:ab)+c"}', '"ac"'), 'non-capturing group miss');
  Check(SchemaAccepts('{"pattern":"^[\\w-]+$"}', '"a-b_c"'), 'word class inside brackets');
  Check(not SchemaAccepts('{"pattern":"^[\\w-]+$"}', '"a b"'), 'word class miss');
  Check(SchemaAccepts('{"pattern":"^ab"}', '"abc"'), 'only start anchored');
  Check(not SchemaAccepts('{"pattern":"^ab"}', '"cab"'), 'start anchor miss');
  Check(SchemaAccepts('{"pattern":"bc$"}', '"abc"'), 'only end anchored');
  Check(not SchemaAccepts('{"pattern":"bc$"}', '"bca"'), 'end anchor miss');
  Check(SchemaAccepts('{"pattern":"a+?b"}', '"aab"'), 'lazy quantifier answers like greedy');
  Check(SchemaIsInvalid('{"pattern":"(?=a)"}'), 'lookahead is not supported');
  Check(SchemaIsInvalid('{"pattern":"a^b"}'), 'mid-pattern anchor is not supported');
  Check(SchemaIsInvalid('{"pattern":"\\bfoo"}'), 'word boundary is not supported');
  Check(SchemaIsInvalid('{"pattern":"["}'), 'unterminated class');
  Check(SchemaIsInvalid('{"pattern":5}'), 'pattern must be a string');
  Check(SchemaIsInvalid('{"patternProperties":{"(":{}}}'), 'patternProperties patterns are checked too');
  Halt(EndSuite);
end.
