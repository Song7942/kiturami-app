@echo off
rem kituramiparts.com 에 올릴 때 쓸 FTP 아이디·비밀번호를 이 컴퓨터에만 담아 둡니다.
rem 한 번만 하면 됩니다. 비밀번호는 윈도우 계정에 묶여 암호로 담깁니다.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0save_ftp.ps1"
