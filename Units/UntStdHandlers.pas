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
  TStdinHandler = class(TThread)
  private
    FStdoutThreadId : Cardinal;
  protected
    {@M}
    procedure Execute(); override;
  public
    {@C}
    constructor Create(AStdoutThreadId : Cardinal); overload;
  end;

  TStdoutHandler = class(TThread)
  private
    FPipeOutWrite  : THandle;
    FShellProcId   : Cardinal;
    FShell         : TShellKind;

    FStdinThreadId : Cardinal;

    FUserName      : String;
    FPassword      : String;
    FDomainName    : String;

    function WriteStdin(pData : PVOID; ADataSize : DWORD) : Boolean;
    function WriteStdinLn(AStr : AnsiString = '') : Boolean;
  protected
    {@M}
    procedure Execute(); override;
  public
    {@C}
    constructor Create(AUserName, APassword : String; ADomainName : String = ''); overload;

    {@S}
    property StdinThreadId : Cardinal write FStdinThreadId;
  end;

implementation

uses UntApiDefs, UntFunctions, UntGlobalDefs;

{+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

  TStdoutIn

  Notice: It would be possible to use ReadLn() but it will prevent doing some
          synchronization between threads.

          Using technique works as an alternative to ReadLn() with Critical Section
          support for thread synchronization.

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++}

{-------------------------------------------------------------------------------
  ___process
-------------------------------------------------------------------------------}
procedure TStdinHandler.Execute();
var ACommand            : AnsiString;
    AInputRecord        : TInputRecord;
    ANumberOfEventsRead : Cardinal;
    AChar               : AnsiChar;
    AOldAttributes      : Word;
    ACoord              : TCoord;
    AOutputConsole      : THandle;
    AInputConsole       : THandle;
    AMessage            : tagMsg;

    {---------------------------------------------------------------------------
      Retrieve cursor position of read console.
    ---------------------------------------------------------------------------}
    function GetConsoleCursorPosition() : TCoord;
    var AConsoleScreenBufferInfo : TConsoleScreenBufferInfo;
    begin
      result.X := -1;
      result.Y := -1;
      ///

      if NOT GetConsoleScreenBufferInfo(AOutputConsole, AConsoleScreenBufferInfo) then
        DumpLastError('GetConsoleScreenBufferInfo')
      else
        result := AConsoleScreenBufferInfo.dwCursorPosition;
    end;

    {---------------------------------------------------------------------------
      Simulate BACKSPACE visually.
    ---------------------------------------------------------------------------}
    procedure SetBackDelta(ADelta : Integer);
    begin
      if (ADelta = 0) then
        Exit();
      ///

      {
        Fix console buffer
      }
      ACoord := GetConsoleCursorPosition();
      if (ACoord.X >= 0) and (ACoord.Y >= 0) then begin
        Dec(ACoord.X, ADelta);

        if NOT SetConsoleCursorPosition(AOutputConsole, ACoord) then
          DumpLastError('SetConsoleCursorPosition');
      end;
    end;

begin
  try
    AInputConsole := GetStdHandle(STD_INPUT_HANDLE);
    if (AInputConsole <= 0) then begin
      DumpLastError('GetStdHandle(STD_INPUT_HANDLE)');

      Exit();
    end;

    AOutputConsole := GetStdHandle(STD_OUTPUT_HANDLE);
    if (AInputConsole <= 0) then begin
      DumpLastError('GetStdHandle(STD_OUTPUT_HANDLE)');

      Exit();
    end;

    ACommand := '';
    while NOT Terminated do begin
      ANumberOfEventsRead := 0;
      if NOT ReadConsoleInput(AInputConsole, AInputRecord, 1, ANumberOfEventsRead) then begin
        DumpLastError('PeekConsoleInput');

        break;
      end;

      if (ANumberOfEventsRead = 0) then
        continue;

      if (AInputRecord.EventType = KEY_EVENT) and AInputRecord.Event.KeyEvent.bKeyDown then begin
        case AInputRecord.Event.KeyEvent.wVirtualKeyCode of
          {---------------------------------------------------------------------
            ENTER
          ---------------------------------------------------------------------}
          VK_RETURN : begin
            ACommand := Trim(ACommand);
            ///

            SetBackDelta(Length(ACommand));
            ///

            ACommand := (ACommand + #13#10);

            {
              Post Command to TStdout Thread.
            }
            PostThreadMessage(
                                FStdoutThreadId,
                                WM_COMMAND,
                                NativeUInt(ACommand),
                                (Length(ACommand) * SizeOf(AnsiChar))
            );

            G_Lock.Enter();
            try
              {
                Wait for ACK
              }
              while NOT Terminated do begin
                if PeekMessage(AMessage, 0, 0, 0, PM_REMOVE) then begin
                  if (AMessage.message = WM_ACK) then
                    break;
                end;

                ///
                Sleep(10);
              end;
            finally
              G_Lock.Leave();
            end;

            ACommand := '';
          end;

          {---------------------------------------------------------------------
            BACKSPACE
          ---------------------------------------------------------------------}
          VK_BACK : begin
            if Length(ACommand) > 0 then begin
              ACommand := Copy(ACommand, 1, Length(ACommand) - 1);

              ///
              G_Lock.Enter();
              try
                SetBackDelta(1);
                write(' ');
                SetBackDelta(1);
              finally
                G_Lock.Leave();
              end;
            end;
            ///
          end;

          else begin
            {-------------------------------------------------------------------
              Any characters
            -------------------------------------------------------------------}
            AChar := AInputRecord.Event.KeyEvent.AsciiChar;
            ACommand := (ACommand + AChar);

            G_Lock.Enter();
            try
              AOldAttributes := UpdateConsoleAttributes(FOREGROUND_INTENSITY or FOREGROUND_GREEN);

              write(AChar);

              UpdateConsoleAttributes(AOldAttributes);
            finally
              G_Lock.Leave();
            end;
          end;
        end;
      end;
    end;
  finally
    ExitThread(0);
  end;
end;

{-------------------------------------------------------------------------------
  ___constructor
-------------------------------------------------------------------------------}
constructor TStdinHandler.Create(AStdoutThreadId : Cardinal);
begin
  inherited Create(True);
  ///

  self.FreeOnTerminate := True;
  self.Priority        := tpNormal;

  FStdOutThreadId := AStdoutThreadid;

  self.Resume();
end;

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

function TStdoutHandler.WriteStdinLn(AStr : AnsiString = '') : Boolean;
begin
  AStr := (AStr + #13#10);

  result := WriteStdin(@AStr[1], Length(AStr));
end;

{-------------------------------------------------------------------------------
  ___process
-------------------------------------------------------------------------------}
procedure TStdoutHandler.Execute();
var AStartupInfo    : TStartupInfo;
    AProcessInfo    : TProcessInformation;
    ASecAttribs     : TSecurityAttributes;
    APipeInRead     : THandle;
    APipeInWrite    : THandle;
    APipeOutRead    : THandle;
    AProgram        : String;
    ABytesAvailable : DWORD;
    ABuffer         : array of byte;
    ABytesRead      : DWORD;
    b               : Boolean;
    AMessage        : tagMsg;
    AData           : AnsiString;

begin
  try
    ZeroMemory(@AStartupInfo, SizeOf(TStartupInfo));
    ZeroMemory(@AProcessInfo, SizeOf(TProcessInformation));
    ZeroMemory(@ASecAttribs, SizeOf(TSecurityAttributes));
    ///

    ASecAttribs.nLength := SizeOf(TSecurityAttributes);
    ASecAttribs.lpSecurityDescriptor := nil;
    ASecAttribs.bInheritHandle := True;

    if NOT CreatePipe(APipeInRead, APipeInWrite, @ASecAttribs, 0) then begin
      DumpLastError('CreatePipe(1)');

      Exit();
    end;

    if NOT CreatePipe(APipeOutRead, FPipeOutWrite, @ASecAttribs, 0) then begin
      DumpLastError('CreatePipe(2)');

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
        ///

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

                {
                  Tells Stdin thread, we finished our synchronized task
                }
                PostThreadMessage(self.FStdinThreadId, WM_ACK, 0, 0);
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

              SetString(AData, PAnsiChar(ABuffer), ABytesRead);

              G_Lock.Enter();
              try
                Write(AData);
              finally
                G_Lock.Leave();
              end;
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

  FStdinThreadId := 0;
  FPipeOutWrite  := 0;
  FShellProcId   := 0;
end;

end.
