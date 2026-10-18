$ErrorActionPreference = 'Stop'
# kituramiparts.com 접속 정보를 이 컴퓨터에만 담아 둡니다.
#   비밀번호는 윈도우 계정에 묶어 암호로 바꿔 담습니다(DPAPI).
#   담긴 파일을 다른 컴퓨터나 다른 계정으로 가져가도 풀리지 않습니다.
#   ※ 이 호스팅은 암호화 FTP(FTPS)를 받지 않아, 올릴 때 비밀번호가
#     가려지지 않은 채 지나갑니다. 공용 와이파이에서는 하지 마세요.

$CFGDIR = Join-Path $env:APPDATA 'kiturami'
$CFG    = Join-Path $CFGDIR 'ftp.json'
if(-not (Test-Path $CFGDIR)){ [void](New-Item -ItemType Directory -Path $CFGDIR) }

Write-Host ''
Write-Host 'kituramiparts.com 올리기 — 접속 정보 담기' -ForegroundColor Cyan
Write-Host '----------------------------------------'
Write-Host '엔터만 치면 ( ) 안의 값을 씁니다.'
Write-Host ''

$h = Read-Host 'FTP 주소 (vh434.timeweb.ru)'
if([string]::IsNullOrWhiteSpace($h)){ $h = 'vh434.timeweb.ru' }
$u = Read-Host 'FTP 아이디 (cb24869_song)'
if([string]::IsNullOrWhiteSpace($u)){ $u = 'cb24869_song' }
$s = Read-Host 'FTP 비밀번호' -AsSecureString
if($s.Length -eq 0){ Write-Host '비밀번호를 넣지 않았습니다. 그만둡니다.' -ForegroundColor Yellow; Read-Host '엔터를 누르면 닫힙니다'; exit 1 }
$site = Read-Host '사이트 주소 (kituramiparts.com)'
if([string]::IsNullOrWhiteSpace($site)){ $site = 'kituramiparts.com' }

$obj = [ordered]@{ host = $h; user = $u; site = $site; pw = (ConvertFrom-SecureString $s) }
$obj | ConvertTo-Json | Set-Content -Path $CFG -Encoding UTF8

Write-Host ''
Write-Host ('담았습니다 : ' + $CFG) -ForegroundColor Green
Write-Host '비밀번호는 이 윈도우 계정에서만 풀립니다.'
Write-Host '이제부터 [kituramiparts 올리기.cmd] 만 누르면 됩니다.'
Write-Host ''
Read-Host '엔터를 누르면 닫힙니다'
