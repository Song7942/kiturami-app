@echo off
rem kituramiparts.com 에 올릴 판을 만듭니다.
rem  - 클라우드(Supabase)로 나가는 길이 사라지고, api/db.php 를 봅니다.
rem  - 가격정보는 보이되, 원가 열만 뺍니다(-NoCost).
rem  - 가격 자료를 통째로 가리려면 -WithPrice 를 빼세요.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0buildhost.ps1" -OwnDb -WithPrice -NoCost
echo.
pause
