param([switch]$WithPrice, [switch]$OwnDb, [switch]$NoCost)
$ErrorActionPreference='Stop'
# Make the self-hosting copy from index.html.
#   in  : ..\index.html            (the one you edit)
#   out : ..\..\kiturami-host\index.html
# What it changes:
#   1) price tables are served empty (the cloud keeps the data, this copy just does not show it)
#   2) /api/fxrate, /api/notify  ->  api/fxrate.php, api/notify.php  (plain php hosting)
#   3) the 'offline app' button is hidden (it needs a snapshot build)
# Keep the price data visible: run with  -WithPrice

$ROOT=Split-Path -Parent $PSScriptRoot           # ...\kiturami-app
$U8=New-Object Text.UTF8Encoding $false
$SRC=Join-Path $ROOT 'index.html'
$SHIM=Join-Path $PSScriptRoot 'noprice.js'
$DIR=Join-Path (Split-Path -Parent $ROOT) 'kiturami-host'
$OUT=Join-Path $DIR 'index.html'

if(-not (Test-Path $DIR)){ [void](New-Item -ItemType Directory -Path $DIR) }
if(-not (Test-Path (Join-Path $DIR 'api'))){ [void](New-Item -ItemType Directory -Path (Join-Path $DIR 'api')) }

$html=[IO.File]::ReadAllText($SRC,$U8)

# 1) the cloud client is replaced by our own connector (api/db.php), and the price shim rides along
$stag='<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>'
if($html.IndexOf($stag) -lt 0){ throw 'supabase cdn tag not found' }
$repl=''
if($OwnDb){
  $repl='<script id="ktDbClient">' + [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'dbclient.js'),$U8) + '</script>'
}else{
  $repl=$stag                                   # keep the cloud
}
if(-not $WithPrice){
  $repl=$repl + "`r`n" + '<script id="ktNoPrice">' + [IO.File]::ReadAllText($SHIM,$U8) + '</script>'
}
if($NoCost){
  $repl=$repl + "`r`n" + '<script id="ktNoCost">' + [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'nocost.js'),$U8) + '</script>'
}
$html=$html.Replace($stag, $repl)
if($OwnDb){
  # the cloud address is no longer used
  $html=[regex]::Replace($html, "const SUPABASE_URL\s*=\s*'[^']*'", "const SUPABASE_URL=''")
  $html=[regex]::Replace($html, "const SUPABASE_KEY\s*=\s*'[^']*'", "const SUPABASE_KEY=''")
}

# 1b) 엑셀 판은 옆에 따로 둔다 — 첫 화면에서 받지 않고, 엑셀을 쓸 때 받는다.
#   바깥(CDN)으로 나가지 않는 것은 종전과 같다.
$xtag=[regex]::Match($html, '<script src="https://[^"]*xlsx[^"]*"></script>')
if($xtag.Success){
  $u=[regex]::Match($xtag.Value,'src="([^"]+)"').Groups[1].Value
  $xf=Join-Path $DIR 'xlsx.bundle.js'
  if(-not (Test-Path $xf)){
    Write-Output ('xlsx   : fetching ' + $u)
    $xjs=(Invoke-WebRequest -Uri $u -UseBasicParsing).Content
    [IO.File]::WriteAllText($xf, $xjs, $U8)
  }
  Write-Output ('xlsx   : {0:N0} bytes -> xlsx.bundle.js (쓸 때 받는다)' -f (Get-Item $xf).Length)
  $html=$html.Replace($xtag.Value, '<script>window.KT_XLSX_SRC="xlsx.bundle.js";</script>')
}

# 1c) 분해도 그림은 따로 떼어 낸다.
#   index.html 안에 base64 로 박혀 있던 그림 18장이 2.7 MB 를 차지한다.
#   파일로 꺼내 두면 첫 화면이 그만큼 가벼워지고, 브라우저가 보는 그림만 받아
#   한 번 받은 것은 다음부터 다시 안 받는다.
$IMGDIR = Join-Path $DIR 'img'
if(Test-Path $IMGDIR){ Get-ChildItem $IMGDIR -Filter '*.png' | Remove-Item -Force }
else { [void](New-Item -ItemType Directory -Path $IMGDIR) }
$script:imgN = 0
$script:imgBytes = 0
$script:imgBad = 0
$evalImg = {
  param($m)
  $b64 = $m.Groups[1].Value
  $script:imgN++
  $name = 'd{0:D2}.png' -f $script:imgN
  try{
    $bytes = [Convert]::FromBase64String($b64)
    [IO.File]::WriteAllBytes((Join-Path $IMGDIR $name), $bytes)
    $script:imgBytes += $bytes.Length
    return 'img/' + $name
  }catch{
    # 자료 자체가 망가져 브라우저에서도 안 보이는 그림이다(ALPHA PLUS S·T 의 2번째 장).
    #   그대로 두면 180 KB 를 괜히 싣고 다니므로 '그림 없음' 자리표로 바꾼다.
    $script:imgBad++
    return 'img/missing.png'
  }
}
$html = [regex]::Replace($html, 'data:image/png;base64,([A-Za-z0-9+/=]+)', $evalImg)
if($script:imgBad){
  Copy-Item (Join-Path $PSScriptRoot 'missing.png') (Join-Path $IMGDIR 'missing.png') -Force
}
Write-Output ('images : {0} files, {1:N2} MB -> img\{2}' -f $script:imgN, ($script:imgBytes/1MB),
  $(if($script:imgBad){ ('  (망가진 그림 ' + $script:imgBad + '장은 자리표로 바꿈)') } else { '' }))

# 2) the two server paths are plain php files next to index.html
$html=$html.Replace("fetch('/api/fxrate')","fetch('api/fxrate.php')")
$html=$html.Replace("fetch('/api/notify'","fetch('api/notify.php'")

# 3) the offline-app button needs a snapshot build, so hide it here
$html=$html.Replace('<button class="dl-btn" id="pnOfflineBtn"','<button class="dl-btn" id="pnOfflineBtn" hidden')

[IO.File]::WriteAllText($OUT,$html,$U8)
Write-Output ('output : ' + $OUT)
Write-Output ('size   : {0:N2} MB' -f ((Get-Item $OUT).Length/1MB))
if($WithPrice){ Write-Output 'price  : shown' } else { Write-Output 'price  : hidden (tables served empty)' }
if($OwnDb){ Write-Output 'data   : my own server (api/db.php + MySQL)' }
else      { Write-Output 'data   : Supabase cloud' }
