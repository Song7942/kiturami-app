param(
  [switch]$BuildOnly,          # 만들기만 하고 올리지는 않는다
  [switch]$NoBuild,            # 이미 만들어 둔 것을 올리기만 한다
  [string[]]$Api = @(),        # 함께 올릴 api 파일 이름들 (예: -Api _lib.php,db.php)
  [string]$Remote = '/public_html/index.html'
)
$ErrorActionPreference = 'Stop'
# kituramiparts.com 에 index.html 을 올린다.
#   비밀번호는 이 컴퓨터(윈도우 계정)에만 암호로 묶어 담아 두고 쓴다.
#   처음 한 번 'ftp 암호 저장.cmd' 를 눌러 넣어 두면, 그 뒤로는 이 파일만 돌리면 된다.
#   ※ 이 호스팅은 암호화 FTP(FTPS)를 받지 않는다 — 비밀번호가 가려지지 않은 채 지나간다.
#     업체에 FTPS/SFTP 를 열어 달라고 해 두는 편이 좋다.

$ROOT   = Split-Path -Parent $PSScriptRoot                 # ...\kiturami-app
$HOSTDIR= Join-Path (Split-Path -Parent $ROOT) 'kiturami-host'
$SRC    = Join-Path $HOSTDIR 'index.html'
$CFGDIR = Join-Path $env:APPDATA 'kiturami'
$CFG    = Join-Path $CFGDIR 'ftp.json'

function Fail($m){ Write-Output ''; Write-Output ('!! ' + $m); exit 1 }

# ── 1) 올릴 파일 만들기 ──────────────────────────────────
if(-not $NoBuild){
  Write-Output 'building ...'
  & (Join-Path $PSScriptRoot 'buildhost.ps1') -OwnDb -WithPrice | Out-Null
}
if(-not (Test-Path $SRC)){ Fail ('올릴 파일이 없습니다: ' + $SRC) }
$len = (Get-Item $SRC).Length
Write-Output ('file   : {0}  ({1:N0} bytes)' -f $SRC, $len)
if($BuildOnly){ Write-Output 'build only — 올리지 않았습니다.'; exit 0 }

# ── 2) 접속 정보 ────────────────────────────────────────
if(-not (Test-Path $CFG)){
  Write-Output ''
  Write-Output '접속 정보가 없습니다. 먼저 아래 파일을 한 번 눌러 FTP 아이디·비밀번호를 넣어 주세요.'
  Write-Output ('  ' + (Join-Path $PSScriptRoot 'ftp 암호 저장.cmd'))
  exit 1
}
$c = Get-Content $CFG -Raw | ConvertFrom-Json
$ftpHost = $c.host; $ftpUser = $c.user
$sec = ConvertTo-SecureString $c.pw                        # 이 윈도우 계정에서만 풀린다
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
try { $ftpPass = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }

# ── 3) 올리기 ───────────────────────────────────────────
$cred = New-Object Net.NetworkCredential($ftpUser, $ftpPass)
function Ftp-MakeDir($path){
  try{
    $r=[Net.FtpWebRequest]::Create('ftp://'+$ftpHost+$path)
    $r.Method=[Net.WebRequestMethods+Ftp]::MakeDirectory
    $r.Credentials=$cred; $r.UsePassive=$true; $r.KeepAlive=$false
    $r.GetResponse().Close()
  }catch{}            # 이미 있으면 그만
}
function Ftp-Put($local, $path, $quiet){
  $size=(Get-Item $local).Length
  $r=[Net.FtpWebRequest]::Create('ftp://'+$ftpHost+$path)
  $r.Method=[Net.WebRequestMethods+Ftp]::UploadFile
  $r.Credentials=$cred; $r.UseBinary=$true; $r.UsePassive=$true; $r.KeepAlive=$false
  $r.Timeout=600000; $r.ReadWriteTimeout=600000; $r.ContentLength=$size
  $in=[IO.File]::OpenRead($local); $out=$r.GetRequestStream()
  try{
    $buf=New-Object byte[] 262144; $done=0; $tick=0
    while(($n=$in.Read($buf,0,$buf.Length)) -gt 0){
      $out.Write($buf,0,$n); $done+=$n
      if(-not $quiet -and (++$tick % 8) -eq 0){ Write-Output ('  {0,3:N0}%  {1:N0} / {2:N0}' -f (100*$done/$size), $done, $size) }
    }
  } finally { $out.Close(); $in.Close() }
  $res=$r.GetResponse(); $st=$res.StatusDescription.Trim(); $res.Close()
  return $st
}
$t0 = Get-Date
try {
  Write-Output ('upload : ftp://' + $ftpHost + $Remote)
  Write-Output ('server : ' + (Ftp-Put $SRC $Remote $false))
  $dirBase = ($Remote -replace '/[^/]+$','')
  function Ftp-Same($local, $path){
    try{
      $q=[Net.FtpWebRequest]::Create('ftp://'+$ftpHost+$path)
      $q.Method=[Net.WebRequestMethods+Ftp]::GetFileSize
      $q.Credentials=$cred; $q.UsePassive=$true; $q.KeepAlive=$false; $q.Timeout=60000
      $rr=$q.GetResponse(); $same=($rr.ContentLength -eq (Get-Item $local).Length); $rr.Close()
      return $same
    }catch{ return $false }
  }
  # 엑셀 판·품번 자료는 옆에 따로 둔다 — 바뀌었을 때만 올린다
  foreach($extra in 'xlsx.bundle.js','pndata.js'){
    $ef = Join-Path $HOSTDIR $extra
    if(-not (Test-Path $ef)){ continue }
    if(Ftp-Same $ef ($dirBase + '/' + $extra)){ Write-Output ('{0,-15} 그대로 (건너뜀)' -f $extra) }
    else { [void](Ftp-Put $ef ($dirBase + '/' + $extra) $true); Write-Output ('{0,-15} 올렸습니다' -f $extra) }
  }
  # 서버 쪽 php 는 말할 때만 올린다 (-Api _lib.php 처럼)
  if($Api.Count){
    Ftp-MakeDir ($dirBase + '/api')
    foreach($a in $Api){
      $af = Join-Path $HOSTDIR ('api/' + $a)
      if(-not (Test-Path $af)){ Write-Output ('{0,-15} 그런 파일이 없습니다' -f $a); continue }
      [void](Ftp-Put $af ($dirBase + '/api/' + $a) $true)
      Write-Output ('api/{0,-11} 올렸습니다 ({1:N0} bytes)' -f $a, (Get-Item $af).Length)
    }
  }
  # 분해도 그림은 따로 떼어 두었다 — 바뀐 것만 올린다
  $imgLocal = Join-Path $HOSTDIR 'img'
  if(Test-Path $imgLocal){
    $base = ($Remote -replace '/[^/]+$','') + '/img'
    Ftp-MakeDir $base
    $pngs = Get-ChildItem $imgLocal -Filter '*.png' | Sort-Object Name
    $sent = 0
    foreach($p in $pngs){
      if(Ftp-Same $p.FullName ($base + '/' + $p.Name)){ continue }
      [void](Ftp-Put $p.FullName ($base + '/' + $p.Name) $true)
      $sent++
    }
    Write-Output ('images : {0}장 중 {1}장을 올렸습니다 (크기가 같은 것은 건너뜀)' -f $pngs.Count, $sent)
  }
} catch {
  Fail ('올리지 못했습니다 — ' + $_.Exception.Message)
} finally { $ftpPass = $null }
Write-Output ('took   : {0:N1}s' -f ((Get-Date)-$t0).TotalSeconds)

# ── 4) 올라갔는지 확인 ──────────────────────────────────
$url = 'https://' + $c.site + '/'
try {
  $r = [Net.WebRequest]::Create($url)
  $r.Method = 'HEAD'; $r.Timeout = 120000
  $resp = $r.GetResponse()
  $srv = [int]$resp.Headers['Content-Length']
  $resp.Close()
  Write-Output ''
  if($srv -eq $len){ Write-Output ('확인   : {0} — {1:N0} bytes 로 올라갔습니다 ✓' -f $url, $srv) }
  else            { Write-Output ('확인   : 크기가 다릅니다 — 서버 {0:N0} / 올린 것 {1:N0}' -f $srv, $len) }
} catch {
  Write-Output ('확인   : 서버 응답을 못 받았습니다 — ' + $_.Exception.Message)
}
