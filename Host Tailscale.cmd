@echo off
call "%~dp0Play.cmd" res://main.tscn -- --delve-host --delve-port 7777 --delve-name "%USERNAME%"
