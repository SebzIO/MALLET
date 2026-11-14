@echo off
rem Launch the MALLET editor from source. Needs Godot 4.5.1: set GODOT to its .exe, or have godot.exe on your PATH.
if "%GODOT%"=="" set GODOT=godot
start "" "%GODOT%" --path "%~dp0."
