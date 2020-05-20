(*******************************************************************************

  Jean-Pierre LESUEUR (@DarkCoderSc)
  https://www.phrozen.io/
  jplesueur@phrozen.io

  License : MIT

*******************************************************************************)

unit UntStdHandlers;

interface

uses Windows, SysUtils, UntTypeDefs, Classes, SyncObjs;

type
  TStdoutHandler = class(TThread)
  private
    FPipeOutWrite  : THandle;
    FShellProcId   : Cardinal;
    FShell         : TShellKind;

    FUserName      : String;
    FPassword      : String;
    FDomainName    : String;

    function WriteStdin(pData : PVOID; ADataSize : DWORD) : Boolean;
  protected
    {@M}
    procedure Execute(); override;
  public
    {@C}
    constructor Create(AUserName, APassword : String; ADomainName : String = ''); overload;
  end;

implementation

uses UntApiDefs, UntFunctions, UntGlobalDefs;

{+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

  TStdoutHandler (Include Stderr)

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++}

{-------------------------------------------------------------------------------
  Write data to attached shell (stdin)
-------------------------------------------------------------------------------}
function TStdoutHandler.WriteStdin(pData : PVOID; ADataSize : DWORD) : Boolean;
var ABytesWritten : DWORD;
begin
  result := False;
  ///

  if (FPipeOutWrite <= 0) then
    Exit();
  ///

  if (NOT WriteFile(FPipeOutWrite, PByte(pData)^, ADataSize, ABytesWritten, nil)) then
    Exit();

  ///
  result := True;
end;

{-------------------------------------------------------------------------------
  ___process
-------------------------------------------------------------------------------}
procedure TStdoutHandler.Execute();
var AStartupInfo         : TStartupInfo;
    AProcessInfo         : TProcessInformation;
    ASecAttribs          : TSecurityAttributes;
    APipeInRead          : THandle;
    APipeInWrite         : THandle;
    APipeOutRead         : THandle;
    AProgram             : String;
    ABytesAvailable      : DWORD;
    ABuffer              : array of byte;
    ABytesRead           : DWORD;
    b                    : Boolean;
    AMessage             : tagMsg;
    AConsoleOutput       : THandle;
begin
  try
    ZeroMemory(@AStartupInfo, SizeOf(TStartupInfo));
    ZeroMemory(@AProcessInfo, SizeOf(TProcessInformation));
    ZeroMemory(@ASecAttribs, SizeOf(TSecurityAttributes));
    ///

    ASecAttribs.nLength := SizeOf(TSecurityAttributes);
    ASecAttribs.lpSecurityDescriptor := nil;
    ASecAttribs.bInheritHandle := True;

    if NOT CreatePipe(APipeOutRead, FPipeOutWrite, @ASecAttribs, 0) then begin
      DumpLastError('CreatePipe(1)');

      Exit();
    end;

    if NOT SetHandleInformation(APipeOutRead, HANDLE_FLAG_INHERIT, 0) then begin
      DumpLastError('SetHandleInformation(1)');

      Exit();
    end;

    if NOT CreatePipe(APipeInRead, APipeInWrite, @ASecAttribs, 0) then begin
      DumpLastError('CreatePipe(2)');

      Exit();
    end;

    if NOT SetHandleInformation(APipeInWrite, HANDLE_FLAG_INHERIT, 0) then begin
      DumpLastError('SetHandleInformation(2)');

      Exit();
    end;

    ///
    try
      AStartupInfo.cb          := SizeOf(TStartupInfo);
      AStartupInfo.wShowWindow := SW_HIDE;
      AStartupInfo.hStdOutput  := APipeInWrite;
      AStartupInfo.hStdError   := APipeInWrite;
      AStartupInfo.hStdInput   := APipeOutRead;
      AStartupInfo.dwFlags     := (STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW);

      if (FShell = skDefault) then begin
        SetLastError(0);
        AProgram := GetEnvironmentVariable('COMSPEC');
        if (GetLastError = ERROR_ENVVAR_NOT_FOUND) then
          FShell := skCmd;
      end;

      case FShell of
        skCmd : begin
          AProgram := UntFunctions.GetSystemDirectory() + 'cmd.exe';
        end;

        skPowershell : begin
          AProgram := 'powershell.exe';
        end;
      end;

      if (FDomainName = '') then
        FDomainName := GetEnvironmentVariable('USERDOMAIN');

      UniqueString(AProgram);
      UniqueString(FUserName);
      UniqueString(FPassword);
      UniqueString(FDomainName);

      b := CreateProcessWithLogonW(
                                     PWideChar(FUserName),
                                     PWideChar(FDomainName),
                                     PWideChar(FPassword),
                                     0,
                                     nil,
                                     PWideChar(AProgram),
                                     0,
                                     nil,
                                     nil,
                                     AStartupInfo,
                                     AProcessInfo
      );

      if (NOT b) then begin
        DumpLastError('CreateProcessWithLogonW');

        Exit();
      end;
      try
        FShellProcId := AProcessInfo.dwProcessId;

        AConsoleOutput := GetStdHandle(STD_OUTPUT_HANDLE);
        if (AConsoleOutput = 0) or (AConsoleOutput = INVALID_HANDLE_VALUE) then begin
          DumpLastError('GetStdHandle(STD_OUTPUT_HANDLE)');

          Exit();
        end;

        while NOT Terminated do begin
          case WaitForSingleObject(AProcessInfo.hProcess, 10) of
            WAIT_OBJECT_0 :
              break;
          end;

          {
            Receive Commands from main thread and write to stdin.
          }
          if PeekMessage(AMessage, 0, 0, 0, PM_REMOVE) then begin
            case AMessage.message of
              {
                Write command to attached console.
              }
              WM_COMMAND : begin
                WriteStdin(Pointer(AMessage.wParam), AMessage.lParam);
              end;
            end;
          end;

          {
            Check for stdout, stderr content
          }
          while NOT Terminated do begin
            if NOT PeekNamedPipe(APipeInRead, nil, 0, nil, @ABytesAvailable, nil) then
              Exit();
            ///

            if (ABytesAvailable = 0) then
              break;

            {
              Read stdout, stderr
            }
            SetLength(ABuffer, ABytesAvailable);
            try
              b := ReadFile(APipeInRead, ABuffer[0], ABytesAvailable, ABytesRead, nil);
              if (NOT b) then
                break;
              ///

              WriteFile(AConsoleOutput, ABuffer[0], ABytesRead, ABytesAvailable, nil);
            finally
              SetLength(ABuffer, 0);
            end;
          end;
        end;
      finally
        TerminateProcess(AProcessInfo.hProcess, 0);

        CloseHandle(AProcessInfo.hProcess);
      end;
    finally
      CloseHandle(APipeInWrite);
      CloseHandle(APipeInRead);
      CloseHandle(FPipeOutWrite);
      CloseHandle(APipeOutRead);

      FPipeOutWrite := 0;
    end;
  finally
    FShellProcId := 0;

    ///
    ExitThread(0);
  end;
end;

{-------------------------------------------------------------------------------
  ___constructor
-------------------------------------------------------------------------------}
constructor TStdoutHandler.Create(AUserName, APassword : String; ADomainName : String = '');
begin
  inherited Create(True);
  ///

  FUserName   := AUserName;
  FPassword   := APassword;
  FDomainName := ADomainName;

  self.FreeOnTerminate := True;
  self.Priority        := tpHighest;

  FPipeOutWrite  := 0;
  FShellProcId   := 0;
end;

end.
