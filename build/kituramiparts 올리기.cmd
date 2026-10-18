@echo off
rem index.html 을 새로 만들어 kituramiparts.com 에 올립니다.
rem 처음 한 번은 [ftp 암호 저장.cmd] 를 눌러 접속 정보를 넣어 두세요.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy_host.ps1"
echo.
pause
