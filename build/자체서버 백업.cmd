@echo off
rem kituramiparts.com(자체 서버)의 자료를 통째로 내 컴퓨터에 떠 둡니다.
rem 사이트 아이디·비밀번호를 한 번 넣어야 합니다(담아 두지 않습니다).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0backup_host.ps1"