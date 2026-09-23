@echo off
rem index.html 을 고친 뒤 이 파일을 두 번 누르면
rem ..\..\kiturami-host\index.html 이 새로 만들어집니다. (가격 자료는 가린 판)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0buildhost.ps1"
echo.
pause
