' ===========================================================================
'  run_daily_hidden.vbs — launch run_daily.bat with NO visible window.
'
'  Point Windows Task Scheduler at this .vbs (via wscript.exe) instead of the
'  .bat so the daily pipeline runs silently in the background — no black
'  console window flashing on screen.
'
'  It finds run_daily.bat in the SAME folder as this script, so the two must
'  stay together. It waits for the batch to finish, so Task Scheduler records
'  an accurate Last Run Result.
' ===========================================================================
Option Explicit

Dim shell, fso, scriptDir, batPath

Set shell = CreateObject("WScript.Shell")
Set fso   = CreateObject("Scripting.FileSystemObject")

' Folder this .vbs lives in (handles spaces in the path, e.g. "website data")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
batPath   = fso.BuildPath(scriptDir, "run_daily.bat")

' Run the batch from its own directory so relative paths (sources.yaml,
' intel.db, .env, leads.xlsx) resolve correctly.
shell.CurrentDirectory = scriptDir

' Run( command, windowStyle, waitOnReturn )
'   windowStyle = 0  -> hidden window
'   waitOnReturn = True -> block until the batch completes
' The doubled quotes wrap the full path so the space in the folder name is safe.
shell.Run """" & batPath & """", 0, True
