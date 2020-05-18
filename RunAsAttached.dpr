(*******************************************************************************

  Jean-Pierre LESUEUR (@DarkCoderSc)
  https://www.phrozen.io/
  jplesueur@phrozen.io

  License : MIT

  Version: 1.0b

  Description:
  ------------------------------------------------------------------------------

    This version doesn't work with programs such as Netcat in the scenario of an
    initial reverse / bind shell.

    Check my Github : https://github.com/darkcodersc to find the version that
    supports netcat ;-)

    Don't forgget to leave a star and follow if you found my work useful ! =P

*******************************************************************************)

program RunAsAttached;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  Windows,
  Classes,
  UntFunctions in 'Units\UntFunctions.pas',
  UntApiDefs in 'Units\UntApiDefs.pas',
  UntGlobalDefs in 'Units\UntGlobalDefs.pas',
  UntStdHandlers in 'Units\UntStdHandlers.pas',
  UntTypeDefs in 'Units\UntTypeDefs.pas';

var SET_USERNAME   : String = '';
    SET_PASSWORD   : String = '';
    SET_DOMAINNAME : String = '';

    LStdoutHandler : TStdoutHandler;
    LStdinHandler  : TStdinHandler;
    AExitCode      : Cardinal;

{-------------------------------------------------------------------------------
  Usage Banner
-------------------------------------------------------------------------------}
function DisplayHelpBanner() : String;
begin
  result := '';
  ///

  WriteLn;

  WriteLn('-----------------------------------------------------------');

  Write('RunAsAttached By ');

  WriteColoredWord('Jean-Pierre LESUEUR ');

  Write('(');

  WriteColoredWord('@DarkCoderSc');

  WriteLn(')');


  WriteLn('https://www.phrozen.io/');
  WriteLn('https://github.com/darkcodersc');
  WriteLn('-----------------------------------------------------------');

  WriteLn;

  WriteLn('RunAsAttached.exe -u <username> -p <password> [-d <domain>]');
  WriteLn;
end;

{-------------------------------------------------------------------------------
  Program Entry
-------------------------------------------------------------------------------}
begin
  isMultiThread := True;
  try
    {
      Parse Parameters
    }
    if NOT GetCommandLineOption('u', SET_USERNAME) then
      raise Exception.Create('');

    if NOT GetCommandLineOption('p', SET_PASSWORD) then
      raise Exception.Create('');

    GetCommandLineOption('d', SET_DOMAINNAME);

    {
      Create Handlers (stdout, stdin, stderr)
    }
    try
      LStdoutHandler := TStdoutHandler.Create(SET_USERNAME, SET_PASSWORD, SET_DOMAINNAME);
      LStdinHandler  := TStdinHandler.Create(LStdoutHandler.ThreadID);

      LStdoutHandler.StdinThreadId := LStdInHandler.ThreadID;
      LStdoutHandler.Resume();

      {
         Stdout is our master
      }
      WaitForSingleObject(LStdoutHandler.Handle, INFINITE); // or LStdoutHandler.WaitFor();

      {
        Close secondary thread if not already
      }
      GetExitCodeThread(LStdinHandler.Handle, AExitCode);
      if (AExitCode = STILL_ACTIVE) then begin
        LStdinHandler.Terminate();
        LStdinHandler.WaitFor();
      end;
    finally
      if Assigned(LStdoutHandler) then
        FreeAndNil(LStdoutHandler);

      if Assigned(LStdinHandler) then
        FreeAndNIl(LStdinHandler);
    end;
  except
    on E: Exception do begin
      if (E.Message <> '') then
        Debug(Format('Exception in class=[%s], message=[%s]', [E.ClassName, E.Message]), dlError)
      else
        DisplayHelpBanner();
    end;
  end;
end.
