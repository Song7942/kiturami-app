@echo off
rem kituramiparts.com 에 올릴 판을 만듭니다.
rem  - 클라우드(Supabase)로 나가는 길이 사라지고, api/db.php 를 봅니다.
rem  - 원가는 이제 본체에 아예 없으므로 -NoCost 는 쓰지 않습니다.
rem    (가격정보는 공급가 RUB 한 열뿐이고, 그 값은 내 컴퓨터의 원가관리.html 이 보냅니다)
rem  - 가격 자료를 통째로 가리려면 -WithPrice 를 빼세요.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0buildhost.ps1" -OwnDb -WithPrice
echo.
pause
