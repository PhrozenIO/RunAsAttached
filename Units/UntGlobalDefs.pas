(*******************************************************************************

  Jean-Pierre LESUEUR (@DarkCoderSc)
  https://www.phrozen.io/
  jplesueur@phrozen.io

  License : MIT

*******************************************************************************)

unit UntGlobalDefs;

interface

uses Windows, Messages, SyncObjs, SysUtils;

const WM_COMMAND   = (WM_USER + 1403);
      WM_TERMINATE = (WM_USER + 1404);
      WM_ACK       = (WM_USER + 1405);

var G_Debug : Boolean = True;
    G_Lock  : TCriticalSection;

implementation

initialization
  G_Lock := TCriticalSection.Create();

finalization
  if Assigned(G_Lock) then
    FreeAndNil(G_Lock);

end.
