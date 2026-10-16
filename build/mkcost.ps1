param([string]$OutDir = '',
      [string]$HostUrl = "http://kituramiparts.com/api/supply.php")
# 원가관리 폴더는 D:\원가관리 를 먼저 본다(옮겨 두었으면 그 쪽).
#   둘 다 있으면 D: 를 쓴다 — 어느 것이 최신인지 헷갈리지 않게 한 군데만 쓴다.
if($OutDir -eq ''){
  $OutDir = if(Test-Path 'D:\원가관리'){ 'D:\원가관리' } else { "$env:USERPROFILE\Documents\원가관리" }
}
$ErrorActionPreference='Stop'
# 원가관리 HTML 을 만든다.
#   원가·환율·기준GP·계산식은 이 파일(내 컴퓨터)에만 두고,
#   웹에는 공급가 RUB 만 보낸다.
#   자료는 지금 클라우드에 있는 것을 처음 한 번 넣어 준다(그 뒤로는 이 파일이 원본).

$ROOT = Split-Path -Parent $PSScriptRoot
$U8   = New-Object Text.UTF8Encoding $false
if(-not (Test-Path $OutDir)){ [void](New-Item -ItemType Directory -Path $OutDir) }

$html = [IO.File]::ReadAllText((Join-Path $ROOT 'index.html'), $U8)
$m = [regex]::Match($html, "const SUPABASE_URL='([^']+)'")
$k = [regex]::Match($html, "const SUPABASE_KEY='([^']+)'")
if(-not ($m.Success -and $k.Success)){ throw 'supabase url/key not found' }
$URL = $m.Groups[1].Value
$KEY = $k.Groups[1].Value
$HDR = @{ apikey = $KEY; Authorization = 'Bearer ' + $KEY }

function Get-All($t){
  $rows = New-Object Collections.ArrayList
  $from = 0
  while($true){
    $pg = Invoke-RestMethod -Uri ($URL + '/rest/v1/' + $t + '?select=*&limit=1000&offset=' + $from) -Headers $HDR
    $n = 0
    foreach($r in $pg){ [void]$rows.Add($r); $n++ }
    if($n -lt 1000){ break }
    $from += 1000
  }
  return ,$rows
}

# ── 씨앗(처음 열 때 쓸 자료) ────────────────────────────────
#   쓰는 차례:
#     1) 내보내 둔 .json 이 OutDir 에 있으면 그 중 가장 새 것
#     2) 이미 만들어 둔 원가관리.html 안의 씨앗  ← 원가는 이제 서버에 없으므로 이쪽이 중요하다
#     3) 그래도 없으면 클라우드의 kt_price_calc (품번 줄만 — 원가는 비어 있다)
#   ※ 화면을 열면 자료는 브라우저(localStorage)에 담기고 그것이 먼저다.
#     이 씨앗은 그 자리가 비어 있을 때만 쓰인다.
$F = Join-Path $OutDir '원가관리.html'
$seedJson = ''
$src = ''

$ex = Get-ChildItem -Path $OutDir -Filter '원가관리_*.json' -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
if($ex){
  $seedJson = [IO.File]::ReadAllText($ex.FullName, $U8).Trim()
  $src = '내보낸 파일 ' + $ex.Name
}
if($seedJson -eq '' -and (Test-Path $F)){
  $old = [IO.File]::ReadAllText($F, $U8)
  $om = [regex]::Match($old, "(?m)^const SEED = (.*);$")
  if($om.Success -and $om.Groups[1].Value -ne 'null'){
    $seedJson = $om.Groups[1].Value
    $src = '이미 있는 원가관리.html'
  }
}
if($seedJson -eq ''){
  Write-Output 'reading price data from cloud ...'
  $calc = (Get-All 'kt_price_calc').ToArray()
  $set  = (Get-All 'kt_price_settings').ToArray()
  $rows = foreach($r in $calc){
    [ordered]@{
      n = $r.row_no; nm = $r.name_ko; sp = $r.spec; rep = $r.rep
      cmp = $r.compat; fin = $r.final
      cost = $r.ru_cost; sup = $r.ru_supply_krw
    }
  }
  $rub = 0; $usd = 0; $gp = 0.4; $month = ''
  if($set.Count){
    $cfg = $set[0]
    $rub = $cfg.rub_rate; $usd = $cfg.usd_rate; $gp = $cfg.ru_gp; $month = $cfg.rate_month
  }
  $seed = [ordered]@{
    rows = @($rows); rub = $rub; usd = $usd; gp = $gp; month = $month
    made = (Get-Date -Format 'yyyy-MM-dd HH:mm')
  }
  $seedJson = ($seed | ConvertTo-Json -Depth 8 -Compress)
  $src = '클라우드 kt_price_calc'
}
$nrows = ([regex]::Matches($seedJson, '"cmp"\s*:')).Count
Write-Output ('  seed    : ' + $src + ' (' + $nrows + ' rows)')

# 품번조회 바탕 자료는 웹 파일에 박혀 있는 것을 그대로 가져다 쓴다
#   (웹에서 고친 것·새 품번은 kt_pn_overrides 라서, 열 때마다 화면이 스스로 맞춘다)
$pnm = [regex]::Match($html, "(?m)^const PN_DATA=(\[.*\]);$")
if(-not $pnm.Success){ throw "PN_DATA not found" }
$PNB = $pnm.Groups[1].Value
Write-Output ("  pn base : {0:N0} bytes" -f $PNB.Length)

# 자체 서버(kituramiparts.com)에도 같이 보내려면 그 열쇠가 필요하다.
#   api/config.php 의 SUPPLY_KEY 를 읽어 온다. 비어 있으면 그쪽으로는 안 보낸다.
$HKEY = ''
$hcfg = Join-Path (Join-Path (Split-Path -Parent $ROOT) 'kiturami-host') 'api\config.php'
if(Test-Path $hcfg){
  $hm = [regex]::Match([IO.File]::ReadAllText($hcfg, $U8), "'SUPPLY_KEY'\s*=>\s*'([^']*)'")
  if($hm.Success){ $HKEY = $hm.Groups[1].Value }
}
if($HKEY -eq ''){ $HostUrl = '' }
Write-Output ('  host    : ' + $(if($HostUrl -ne ''){ $HostUrl } else { '(안 보냄)' }))

$tpl = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "cost.template.html"), $U8)
$out = $tpl.Replace("/*__SEED__*/null", $seedJson).Replace("/*__PNBASE__*/null", $PNB).Replace("__SB_URL__", $URL).Replace("__SB_KEY__", $KEY).Replace("__HOST_URL__", $HostUrl).Replace("__HOST_KEY__", $HKEY)
$f = Join-Path $OutDir '원가관리.html'
[IO.File]::WriteAllText($f, $out, $U8)
Write-Output ''
Write-Output ('output : ' + $f)
Write-Output ('size   : {0:N2} MB' -f ((Get-Item $f).Length/1MB))
