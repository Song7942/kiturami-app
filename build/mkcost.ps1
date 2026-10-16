param([string]$OutDir = "C:\Users\admin\Documents\원가관리")
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

Write-Output 'reading price data ...'
$calc = (Get-All 'kt_price_calc').ToArray()
$set  = (Get-All 'kt_price_settings').ToArray()
Write-Output ('  rows : {0}' -f $calc.Count)

# 화면이 쓰는 칸만 추려 담는다(파일을 가볍게)
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
  rows = @($rows)
  rub  = $rub
  usd  = $usd
  gp   = $gp
  month= $month
  made = (Get-Date -Format 'yyyy-MM-dd HH:mm')
}
$seedJson = ($seed | ConvertTo-Json -Depth 8 -Compress)

$tpl = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'cost.template.html'), $U8)
$out = $tpl.Replace('/*__SEED__*/null', $seedJson).Replace('__SB_URL__', $URL).Replace('__SB_KEY__', $KEY)
$f = Join-Path $OutDir '원가관리.html'
[IO.File]::WriteAllText($f, $out, $U8)
Write-Output ''
Write-Output ('output : ' + $f)
Write-Output ('size   : {0:N2} MB' -f ((Get-Item $f).Length/1MB))
