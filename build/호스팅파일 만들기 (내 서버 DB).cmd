@echo off
rem 자료까지 내 서버(MySQL)에 두는 판을 만듭니다.
rem  - 클라우드(Supabase)로 나가는 길이 사라지고, api/db.php 를 봅니다.
rem  - 가격 자료는 가립니다. 가격까지 보이게 하려면 아래 줄 끝에 -WithPrice 를 붙이세요.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0buildhost.ps1" -OwnDb
echo.
pause
