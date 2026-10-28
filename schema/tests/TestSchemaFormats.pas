{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestSchemaFormats;

{$APPTYPE CONSOLE}

uses
  TestSupport, SchemaTestSupport;

begin
  BeginSuite('Schema: format assertions');
  Check(SchemaAccepts('{"format":"email"}', '"a@b.co"'), 'email accepts a@b.co');
  Check(not SchemaAccepts('{"format":"email"}', '"nope"'), 'email rejects nope');
  Check(not SchemaAccepts('{"format":"email"}', '"a@@b.co"'), 'email rejects a@@b.co');
  Check(SchemaAccepts('{"format":"date"}', '"2024-02-29"'), 'date accepts 2024-02-29');
  Check(not SchemaAccepts('{"format":"date"}', '"2023-02-29"'), 'date rejects 2023-02-29');
  Check(not SchemaAccepts('{"format":"date"}', '"2024-13-01"'), 'date rejects 2024-13-01');
  Check(SchemaAccepts('{"format":"date-time"}', '"2024-01-02T03:04:05Z"'), 'date-time accepts 2024-01-02T03:04:05Z');
  Check(SchemaAccepts('{"format":"date-time"}', '"2024-01-02T03:04:05.123+02:00"'), 'date-time accepts 2024-01-02T03:04:05.123+02:00');
  Check(not SchemaAccepts('{"format":"date-time"}', '"2024-01-02 03:04:05"'), 'date-time rejects 2024-01-02 03:04:05');
  Check(SchemaAccepts('{"format":"time"}', '"12:30:45Z"'), 'time accepts 12:30:45Z');
  Check(not SchemaAccepts('{"format":"time"}', '"25:00:00Z"'), 'time rejects 25:00:00Z');
  Check(SchemaAccepts('{"format":"ipv4"}', '"192.168.0.1"'), 'ipv4 accepts 192.168.0.1');
  Check(not SchemaAccepts('{"format":"ipv4"}', '"256.1.1.1"'), 'ipv4 rejects 256.1.1.1');
  Check(not SchemaAccepts('{"format":"ipv4"}', '"01.1.1.1"'), 'ipv4 rejects 01.1.1.1');
  Check(not SchemaAccepts('{"format":"ipv4"}', '"1.2.3"'), 'ipv4 rejects 1.2.3');
  Check(SchemaAccepts('{"format":"ipv6"}', '"::1"'), 'ipv6 accepts ::1');
  Check(SchemaAccepts('{"format":"ipv6"}', '"2001:db8::ff00:42:8329"'), 'ipv6 accepts 2001:db8::ff00:42:8329');
  Check(SchemaAccepts('{"format":"ipv6"}', '"1:2:3:4:5:6:7:8"'), 'ipv6 accepts 1:2:3:4:5:6:7:8');
  Check(not SchemaAccepts('{"format":"ipv6"}', '"1:2:3"'), 'ipv6 rejects 1:2:3');
  Check(not SchemaAccepts('{"format":"ipv6"}', '":::"'), 'ipv6 rejects :::');
  Check(SchemaAccepts('{"format":"uuid"}', '"123e4567-e89b-12d3-a456-426614174000"'), 'uuid accepts 123e4567-e89b-12d3-a456-426614174000');
  Check(not SchemaAccepts('{"format":"uuid"}', '"123e4567e89b12d3a456426614174000"'), 'uuid rejects 123e4567e89b12d3a456426614174000');
  Check(SchemaAccepts('{"format":"hostname"}', '"example.com"'), 'hostname accepts example.com');
  Check(not SchemaAccepts('{"format":"hostname"}', '"-bad.com"'), 'hostname rejects -bad.com');
  Check(SchemaAccepts('{"format":"uri"}', '"https://example.com/x"'), 'uri accepts https://example.com/x');
  Check(not SchemaAccepts('{"format":"uri"}', '"nocolon"'), 'uri rejects nocolon');
  Check(SchemaAccepts('{"format":"json-pointer"}', '"/a/b"'), 'json-pointer accepts /a/b');
  Check(not SchemaAccepts('{"format":"json-pointer"}', '"a/b"'), 'json-pointer rejects a/b');
  Check(not SchemaAccepts('{"format":"json-pointer"}', '"/a~2"'), 'json-pointer rejects /a~2');
  Check(SchemaAccepts('{"format":"made-up"}', '"anything"'), 'unknown formats are annotations only');
  Check(SchemaAccepts('{"format":"email"}', '5'), 'formats ignore non-strings');
  Check(SchemaAcceptsNoFormats('{"format":"email"}', '"nope"'), 'AssertFormats=False disables format checks');
  Check(SchemaIsInvalid('{"format":5}'), 'format must be a string');
  Halt(EndSuite);
end.
