(*******************************************************************************

  Jean-Pierre LESUEUR (@DarkCoderSc)
  https://www.phrozen.io/
  jplesueur@phrozen.io

  License : MIT

*******************************************************************************)

unit UntGlobalDefs;

interface

uses Windows, Messages, SyncObjs, SysUtils;

const WM_COMMAND       = (WM_USER + 1403);
      WM_TERMINATE     = (WM_USER + 1404);

var G_Debug : Boolean = True;

implementation

end.
