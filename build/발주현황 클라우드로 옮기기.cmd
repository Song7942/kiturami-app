@echo off
rem 사이트(kituramiparts.com)의 발주현황을 클라우드에 그대로 맞춥니다.
rem 사이트 아이디·비밀번호를 한 번 넣어야 합니다(담아 두지 않습니다).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync_po_to_cloud.ps1"