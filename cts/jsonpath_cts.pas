{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$H+}
program jsonpath_cts;

{ Command line runner for the JSONPath Compliance Test Suite.

  Build (Free Pascal, from the jsonpath folder):  ./build_cts.sh
  Usage:  jsonpath_cts [options] <file-or-directory> [<file-or-directory> ...]
  Run with --help for the options. }

{$APPTYPE CONSOLE}

uses
  SysUtils, Classes, JSONPathCTS;

type
  TConsoleOutput = class
  public
    procedure Line(const ALine: string);
  end;

procedure TConsoleOutput.Line(const ALine: string);
begin
  WriteLn(ALine);
end;

procedure ShowUsage;
begin
  WriteLn('jsonpath_cts - runs JSONPath compliance test suite files against this library');
  WriteLn;
  WriteLn('Usage: jsonpath_cts [options] <file-or-directory> [<file-or-directory> ...]');
  WriteLn;
  WriteLn('  A file is one suite file (format of cts.schema.json); a directory is scanned for');
  WriteLn('  suite files (cts.schema.json itself and other *.schema.json files are skipped).');
  WriteLn;
  WriteLn('Options:');
  WriteLn('  -f, --filter <text>    only run tests whose name contains <text> (case-insensitive)');
  WriteLn('  -t, --tag <tag>        only run tests that carry this tag');
  WriteLn('      --fail-fast        stop after the first failing test');
  WriteLn('  -v, --verbose          also list passing tests');
  WriteLn('  -q, --quiet            print only the summary');
  WriteLn('      --no-recursive     do not descend into sub directories');
  WriteLn('      --ext <list>       file endings to scan, e.g. ".json;.cts" (default ".json")');
  WriteLn('      --schema <file>    validate suite files against this cts.schema.json');
  WriteLn('                         (default: look next to the input, in the current directory');
  WriteLn('                          and next to the program)');
  WriteLn('      --no-validate      do not validate suite files against the schema');
  WriteLn('  -h, --help             show this help');
  WriteLn;
  WriteLn('Exit codes: 0 all tests passed, 1 some tests failed, 2 usage or file errors.');
end;

var
  Opts: TCtsOptions;
  Paths: TStringList;
  Output: TConsoleOutput;
  Runner: TCtsRunner;
  I, EqPos: Integer;
  Arg, Value: string;
  HasInline: Boolean;
  ExitCode: Integer;

function TakeValue(const AOption: string): string;
begin
  if HasInline then
    Result := Value
  else
  begin
    if I >= ParamCount then
    begin
      WriteLn('error: option ', AOption, ' needs a value');
      Halt(2);
    end;
    Inc(I);
    Result := ParamStr(I);
  end;
end;

begin
  Opts := DefaultCtsOptions;
  Paths := TStringList.Create;
  Output := TConsoleOutput.Create;
  try
    I := 1;
    while I <= ParamCount do
    begin
      Arg := ParamStr(I);
      HasInline := False;
      Value := '';
      EqPos := Pos('=', Arg);
      if (Copy(Arg, 1, 2) = '--') and (EqPos > 0) then
      begin
        HasInline := True;
        Value := Copy(Arg, EqPos + 1, Length(Arg));
        Arg := Copy(Arg, 1, EqPos - 1);
      end;
      if (Arg = '-h') or (Arg = '--help') then
      begin
        ShowUsage;
        Halt(0);
      end
      else if (Arg = '-f') or (Arg = '--filter') then
        Opts.NameFilter := TakeValue(Arg)
      else if (Arg = '-t') or (Arg = '--tag') then
        Opts.TagFilter := TakeValue(Arg)
      else if Arg = '--fail-fast' then
        Opts.FailFast := True
      else if (Arg = '-v') or (Arg = '--verbose') then
        Opts.Verbose := True
      else if (Arg = '-q') or (Arg = '--quiet') then
        Opts.Quiet := True
      else if Arg = '--no-recursive' then
        Opts.Recursive := False
      else if Arg = '--ext' then
        Opts.Extensions := TakeValue(Arg)
      else if Arg = '--schema' then
        Opts.SchemaFile := TakeValue(Arg)
      else if Arg = '--no-validate' then
        Opts.Validate := False
      else if (Length(Arg) > 1) and (Arg[1] = '-') then
      begin
        WriteLn('error: unknown option ', Arg, ' (try --help)');
        Halt(2);
      end
      else
        Paths.Add(ParamStr(I));
      Inc(I);
    end;

    if Paths.Count = 0 then
    begin
      ShowUsage;
      Halt(2);
    end;

    Runner := TCtsRunner.Create(Opts, Output.Line);
    try
      for I := 0 to Paths.Count - 1 do
        if not Runner.Stopped then
          Runner.RunPath(Paths[I]);
      WriteLn;
      WriteLn(Runner.SummaryLine);
      if Runner.Stats.FileErrors > 0 then
        ExitCode := 2
      else if Runner.Stats.Failed > 0 then
        ExitCode := 1
      else
        ExitCode := 0;
    finally
      Runner.Free;
    end;
  finally
    Output.Free;
    Paths.Free;
  end;
  Halt(ExitCode);
end.
