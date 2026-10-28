{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program TestSchemaUriAndPointer;

{$APPTYPE CONSOLE}

uses
  TestSupport, SysUtils, JsonSchemaErrors, JsonSchemaStore;

begin
  BeginSuite('Schema: URI resolution and JSON Pointer helpers');
  CheckEqualsStr('g:h', UriResolve('http://a/b/c/d;p?q', 'g:h'), 'RFC 3986 example: "g:h"');
  CheckEqualsStr('http://a/b/c/g', UriResolve('http://a/b/c/d;p?q', 'g'), 'RFC 3986 example: "g"');
  CheckEqualsStr('http://a/b/c/g', UriResolve('http://a/b/c/d;p?q', './g'), 'RFC 3986 example: "./g"');
  CheckEqualsStr('http://a/b/c/g/', UriResolve('http://a/b/c/d;p?q', 'g/'), 'RFC 3986 example: "g/"');
  CheckEqualsStr('http://a/g', UriResolve('http://a/b/c/d;p?q', '/g'), 'RFC 3986 example: "/g"');
  CheckEqualsStr('http://g', UriResolve('http://a/b/c/d;p?q', '//g'), 'RFC 3986 example: "//g"');
  CheckEqualsStr('http://a/b/c/d;p?y', UriResolve('http://a/b/c/d;p?q', '?y'), 'RFC 3986 example: "?y"');
  CheckEqualsStr('http://a/b/c/g?y', UriResolve('http://a/b/c/d;p?q', 'g?y'), 'RFC 3986 example: "g?y"');
  CheckEqualsStr('http://a/b/c/d;p?q#s', UriResolve('http://a/b/c/d;p?q', '#s'), 'RFC 3986 example: "#s"');
  CheckEqualsStr('http://a/b/c/g#s', UriResolve('http://a/b/c/d;p?q', 'g#s'), 'RFC 3986 example: "g#s"');
  CheckEqualsStr('http://a/b/c/;x', UriResolve('http://a/b/c/d;p?q', ';x'), 'RFC 3986 example: ";x"');
  CheckEqualsStr('http://a/b/c/d;p?q', UriResolve('http://a/b/c/d;p?q', ''), 'RFC 3986 example: ""');
  CheckEqualsStr('http://a/b/c/', UriResolve('http://a/b/c/d;p?q', '.'), 'RFC 3986 example: "."');
  CheckEqualsStr('http://a/b/c/', UriResolve('http://a/b/c/d;p?q', './'), 'RFC 3986 example: "./"');
  CheckEqualsStr('http://a/b/', UriResolve('http://a/b/c/d;p?q', '..'), 'RFC 3986 example: ".."');
  CheckEqualsStr('http://a/b/', UriResolve('http://a/b/c/d;p?q', '../'), 'RFC 3986 example: "../"');
  CheckEqualsStr('http://a/b/g', UriResolve('http://a/b/c/d;p?q', '../g'), 'RFC 3986 example: "../g"');
  CheckEqualsStr('http://a/', UriResolve('http://a/b/c/d;p?q', '../..'), 'RFC 3986 example: "../.."');
  CheckEqualsStr('http://a/', UriResolve('http://a/b/c/d;p?q', '../../'), 'RFC 3986 example: "../../"');
  CheckEqualsStr('http://a/g', UriResolve('http://a/b/c/d;p?q', '../../g'), 'RFC 3986 example: "../../g"');
  CheckEqualsStr('other', UriResolve('', 'other'), 'a relative reference against an empty base');
  CheckEqualsStr('#/a', UriResolve('', '#/a'), 'a fragment against an empty base');
  CheckEqualsStr('http://x/dir/a.json', UriResolve('http://x/dir/s.json', 'a.json'), 'sibling resource');
  CheckEqualsStr('urn:example:root#foo', UriResolve('urn:example:root', '#foo'), 'non-hierarchical base with a fragment');
  CheckEqualsStr('http://y/z', UriResolve('http://x/dir/s.json', 'http://y/z'), 'an absolute reference wins');
  CheckEqualsStr('http://x/s.json', UriWithoutFragment('http://x/s.json#/a/b'), 'UriWithoutFragment');
  CheckEqualsStr('/a/b', UriFragment('http://x/s.json#/a/b'), 'UriFragment');
  CheckEqualsStr('', UriFragment('http://x/s.json'), 'UriFragment without a fragment');
  CheckEqualsStr('a b/c', PercentDecode('a%20b%2Fc'), 'PercentDecode');
  CheckEqualsStr('a%2', PercentDecode('a%2'), 'PercentDecode keeps incomplete escapes');

  CheckEqualsStr('a~1b~0c', JsonPointerEscape('a/b~c'), 'JsonPointerEscape');
  CheckEqualsStr('a/b~c', JsonPointerUnescape('a~1b~0c'), 'JsonPointerUnescape');
  CheckEqualsStr('~1', JsonPointerUnescape('~01'), 'unescaping handles ~0 before the following character');
  CheckEqualsStr('/x', JsonPointerStep('x'), 'JsonPointerStep');
  CheckEqualsStr('/a~1b', JsonPointerStep('a/b'), 'JsonPointerStep escapes');
  CheckEqualsStr('/3', JsonPointerIndexStep(3), 'JsonPointerIndexStep');
  Halt(EndSuite);
end.
