(*******************************************************************************

  Jean-Pierre LESUEUR (@DarkCoderSc)
  https://www.phrozen.io/
  jplesueur@phrozen.io

  License : MIT

*******************************************************************************)

unit UntFunctions;

interface

uses Windows, SysUtils;

type
  TDebugLevel = (
                  dlInfo,
                  dlSuccess,
                  dlWarning,
                  dlError
  );

procedure DumpLastError(APrefix : String = '');
procedure Debug(AMessage : String; ADebugLevel : TDebugLevel = dlInfo);
function GetSystemDirectory() : string;
function UpdateConsoleAttributes(AConsoleAttributes : Word) : Word;
function GetCommandLineOption(AOption : String; var AValue : String; ACommandLine : String = '') : Boolean; overload;
function GetCommandLineOption(AOption : String; var AValue : String; var AOptionExists : Boolean; ACommandLine : String = '') : Boolean; overload;
procedure WriteColoredWord(AString : String);

implementation

uses UntGlobalDefs, UntApiDefs;

{-------------------------------------------------------------------------------
  Write colored word(s) on current console
-------------------------------------------------------------------------------}
procedure WriteColoredWord(AString : String);
var AOldAttributes : Word;
begin
  AOldAttributes := UpdateConsoleAttributes(FOREGROUND_INTENSITY or FOREGROUND_GREEN);

  Write(AString);

  UpdateConsoleAttributes(AOldAttributes);
end;

{-------------------------------------------------------------------------------
  Command Line Parser

  AOption       : Search for specific option Ex: -c.
  AValue        : Next argument string if option is found.
  AOptionExists : Set to true if option is found in command line string.
  ACommandLine  : Command Line String to parse, by default, actual program command line.
-------------------------------------------------------------------------------}
function GetCommandLineOption(AOption : String; var AValue : String; var AOptionExists : Boolean; ACommandLine : String = '') : Boolean;
var ACount    : Integer;
    pElements : Pointer;
    I         : Integer;
    ACurArg   : String;
type
  TArgv = array[0..0] of PWideChar;
begin
  result := False;
  ///

  AOptionExists := False;

  if NOT Assigned(CommandLineToArgvW) then
    Exit();

  if (ACommandLine = '') then begin
    ACommandLine := GetCommandLineW();
  end;

  pElements := CommandLineToArgvW(PWideChar(ACommandLine), ACount);

  if NOT Assigned(pElements) then
    Exit();

  AOption := '-' + AOption;

  if (Length(AOption) > 2) then
    AOption := '-' + AOption;

  for I := 0 to ACount -1 do begin
    ACurArg := UnicodeString((TArgv(pElements^)[I]));
    ///

    if (ACurArg <> AOption) then
      continue;

    AOptionExists := True;

    // Retrieve Next Arg
    if I <> (ACount -1) then begin
      AValue := UnicodeString((TArgv(pElements^)[I+1]));

      ///
      result := True;
    end;
  end;
end;

function GetCommandLineOption(AOption : String; var AValue : String; ACommandLine : String = '') : Boolean;
var AExists : Boolean;
begin
  result := GetCommandLineOption(AOption, AValue, AExists, ACommandLine);
end;

{-------------------------------------------------------------------------------
   Retrieve \Windows\System32\ Location
-------------------------------------------------------------------------------}
function GetSystemDirectory() : string;
var ALen  : Cardinal;
begin
  SetLength(result, MAX_PATH);

  ALen := Windows.GetSystemDirectory(@result[1], MAX_PATH);

  if (ALen > 0) then begin
    SetLength(result, ALen);

    result := IncludeTrailingPathDelimiter(result);
  end else
    result := '';
end;

{-------------------------------------------------------------------------------
  Update Console Attributes (Changing color for example)

  Returns previous attributes.
-------------------------------------------------------------------------------}
function UpdateConsoleAttributes(AConsoleAttributes : Word) : Word;
var AConsoleHandle        : THandle;
    AConsoleScreenBufInfo : TConsoleScreenBufferInfo;
    b                     : Boolean;
begin
  result := 0;
  ///

  AConsoleHandle := GetStdHandle(STD_OUTPUT_HANDLE);
  if (AConsoleHandle = INVALID_HANDLE_VALUE) then
    Exit();
  ///

  b := GetConsoleScreenBufferInfo(AConsoleHandle, AConsoleScreenBufInfo);

  if b then begin
    SetConsoleTextAttribute(AConsoleHandle, AConsoleAttributes);

    ///
    result := AConsoleScreenBufInfo.wAttributes;
  end;
end;

{-------------------------------------------------------------------------------
  Debug Defs
-------------------------------------------------------------------------------}
procedure Debug(AMessage : String; ADebugLevel : TDebugLevel = dlInfo);
var AConsoleHandle        : THandle;
    AConsoleScreenBufInfo : TConsoleScreenBufferInfo;
    b                     : Boolean;
    AStatus               : String;
    AColor                : Integer;
begin
  if (NOT G_Debug) then
    Exit();
  ///

  AConsoleHandle := GetStdHandle(STD_OUTPUT_HANDLE);
  if (AConsoleHandle = INVALID_HANDLE_VALUE) then
    Exit();
  ///

  b := GetConsoleScreenBufferInfo(AConsoleHandle, AConsoleScreenBufInfo);

  case ADebugLevel of
    dlSuccess : begin
      AStatus := #32 + 'OK' + #32;
      AColor  := FOREGROUND_GREEN;
    end;

    dlWarning : begin
      AStatus := #32 + '!!' + #32;
      AColor  := (FOREGROUND_RED or FOREGROUND_GREEN);
    end;

    dlError : begin
      AStatus := #32 + 'KO' + #32;
      AColor  := FOREGROUND_RED;
    end;

    else begin
      AStatus := 'INFO';
      AColor  := FOREGROUND_BLUE;
    end;
  end;

  Write('[');
  if b then
    b := SetConsoleTextAttribute(AConsoleHandle, FOREGROUND_INTENSITY or (AColor));
  try
    Write(AStatus);
  finally
    if b then
      SetConsoleTextAttribute(AConsoleHandle, AConsoleScreenBufInfo.wAttributes);
  end;
  Write(']' + #32);

  ///
  WriteLn(AMessage);
end;

procedure DumpLastError(APrefix : String = '');
var ACode         : Integer;
    AFinalMessage : String;
begin
  ACode := GetLastError();

  AFinalMessage := '';

  if (ACode <> 0) then begin
    AFinalMessage := Format('Error_Msg=[%s], Error_Code=[%d]', [SysErrorMessage(ACode), ACode]);

    if (APrefix <> '') then
      AFinalMessage := Format('%s: %s', [APrefix, AFinalMessage]);

    ///
    Debug(AFinalMessage, dlError);
  end;
end;

end.
