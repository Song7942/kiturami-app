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

# 1d) 주석 줄과 들여쓰기를 걷어낸다(자체 서버판만. 원본은 그대로 읽기 좋게 둔다).
#   · '//' 로만 시작하는 줄을 버린다
#   · 줄 앞 빈칸을 없앤다
#   백틱(`) 템플릿 안쪽과 /* */ 주석 안쪽은 건드리지 않는다 —
#   거기서는 그 글자들이 '글'이지 주석이 아니기 때문이다.
$lines = $html -split "`r`n|`n"
$sb = New-Object Text.StringBuilder
$inTpl = $false      # 백틱 템플릿 안인가
$inBlk = $false      # /* */ 안인가
$cut = 0
foreach($ln in $lines){
  $keep = $ln
  if(-not $inTpl -and -not $inBlk){
    $t = $ln.TrimStart()
    if($t.StartsWith('//')){ $cut++; continue }      # 주석 줄은 버린다
    $keep = $t                                        # 들여쓰기를 없앤다
  }
  [void]$sb.AppendLine($keep)
  # 이 줄을 지나면서 상태가 어떻게 바뀌는지 센다(따옴표 안의 백틱까지 세지는 않지만
  #   이 파일에는 그런 것이 없다 — 전체 백틱 수가 짝수인 것으로 확인했다)
  for($i=0; $i -lt $ln.Length; $i++){
    $c = $ln[$i]
    $prev = if($i -gt 0){ $ln[$i-1] } else { [char]0 }
    if($inBlk){
      if($c -eq '/' -and $prev -eq '*'){ $inBlk = $false }
      continue
    }
    if($inTpl){
      if($c -eq '`' -and $prev -ne '\'){ $inTpl = $false }
      continue
    }
    if($c -eq '`' -and $prev -ne '\'){ $inTpl = $true; continue }
    if($c -eq '*' -and $prev -eq '/'){ $inBlk = $true; continue }
    if($c -eq '/' -and $prev -eq '/'){ break }        # 줄 끝 주석 — 이 줄은 여기서 그만 본다
  }
}
$before = $html.Length
$html = $sb.ToString()
Write-Output ('strip  : 주석 {0}줄 걷어 {1:N0} -> {2:N0} bytes' -f $cut, $before, $html.Length)

# 3) the offline-app button needs a snapshot build, so hide it here
$html=$html.Replace('<button class="dl-btn" id="pnOfflineBtn"','<button class="dl-btn" id="pnOfflineBtn" hidden')

[IO.File]::WriteAllText($OUT,$html,$U8)
Write-Output ('output : ' + $OUT)
Write-Output ('size   : {0:N2} MB' -f ((Get-Item $OUT).Length/1MB))
if($WithPrice){ Write-Output 'price  : shown' } else { Write-Output 'price  : hidden (tables served empty)' }
if($OwnDb){ Write-Output 'data   : my own server (api/db.php + MySQL)' }
else      { Write-Output 'data   : Supabase cloud' }
