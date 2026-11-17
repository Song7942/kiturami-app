$ErrorActionPreference = 'Stop'
# 사이트(kituramiparts.com)의 발주현황을 클라우드(Supabase)에 '그대로' 맞춘다.
#   · 사이트에 있는 줄은 덮어쓰고,
#   · 사이트에 없는데 클라우드에만 남은 줄은 지운다(발주코드를 고치면 옛 코드 줄이 남으므로).
#   · 발주현황에 매달린 설정(수기 표시·변경코드(공급)·인보이스 기록)도 함께 옮긴다.
#   지우기 전에 클라우드 발주현황을 한 벌 떠 둔다 — 잘못되면 그 파일로 되돌릴 수 있다.

$SITE   = 'https://kituramiparts.com'
$ROOT   = Split-Path -Parent $PSScriptRoot
$U8     = New-Object Text.UTF8Encoding $false
$html   = [IO.File]::ReadAllText((Join-Path $ROOT 'index.html'), $U8)
$URL    = [regex]::Match($html, "const SUPABASE_URL='([^']+)'").Groups[1].Value
$KEY    = [regex]::Match($html, "const SUPABASE_KEY='([^']+)'").Groups[1].Value
if(-not $URL -or -not $KEY){ throw 'index.html 에서 클라우드 주소를 못 찾았습니다' }
$CH = @{ apikey=$KEY; Authorization=('Bearer '+$KEY) }

Write-Output ('가져올 곳 : ' + $SITE)
Write-Output ('맞출 곳   : ' + $URL)
Write-Output ''
$id = Read-Host '사이트 아이디 (MASTER 등)'
$ps = Read-Host '비밀번호' -AsSecureString
$b  = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ps)
try { $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
$sess = $null
try{
  $r = Invoke-WebRequest -Uri ($SITE + '/api/auth.php') -Method Post -ContentType 'application/json' `
        -Body (@{ op='login'; id=$id; pw=$pw } | ConvertTo-Json -Compress) `
        -SessionVariable sess -UseBasicParsing -TimeoutSec 60
  $pw = $null
  $j = $r.Content | ConvertFrom-Json
  if(-not $j.ok){ throw '아이디 또는 비밀번호가 맞지 않습니다' }
}catch{ Write-Output ('!! 로그인 실패 — ' + $_.Exception.Message.Split([char]10)[0]); Read-Host '엔터를 누르면 닫습니다'; exit 1 }
Write-Output ('로그인 되었습니다 — ' + $j.user.id)
Write-Output ''

function Host-Rows($t){
  $all=New-Object Collections.ArrayList; $from=0; $page=1000
  while($true){
    $q = @{ t=$t; op='select'; cols='*'; filters=@(); order=@(); limit=$page; offset=$from } | ConvertTo-Json -Depth 5 -Compress
    $rr = Invoke-RestMethod -Uri ($SITE+'/api/db.php') -Method Post -ContentType 'application/json' -Body $q -WebSession $sess -TimeoutSec 300
    if($rr.error){ throw $rr.error.message }
    $n=0; if($null -ne $rr.data){ foreach($x in $rr.data){ [void]$all.Add($x); $n++ } }
    if($n -lt $page){ break }
    $from += $page
  }
  # ',$all' 로 돌려주면 받는 쪽에서 '한 덩어리' 로 잡혀 줄 수가 1 이 된다 — 풀어서 돌려준다
  return $all.ToArray()
}
function Cloud-Up($t, $rows, $conflict){
  $H = @{ apikey=$KEY; Authorization=('Bearer '+$KEY); 'Content-Type'='application/json';
          Prefer='resolution=merge-duplicates,return=minimal' }
  $uri = $URL + '/rest/v1/' + $t + '?on_conflict=' + $conflict
  for($i=0; $i -lt $rows.Count; $i+=300){
    $chunk = $rows[$i..([Math]::Min($i+299, $rows.Count-1))]
    $body  = ConvertTo-Json -InputObject @($chunk) -Depth 20 -Compress
    [void](Invoke-WebRequest -Uri $uri -Method Post -Headers $H -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing -TimeoutSec 300)
  }
}

# ── 사이트 발주현황 ──
$po = @(Host-Rows 'kt_po')
Write-Output ('사이트 발주현황 : ' + $po.Count + '줄')
if($po.Count -lt 50){
  Write-Output '!! 사이트에서 제대로 못 받았습니다 — 그만둡니다(잘못 지우지 않게).'
  Read-Host '엔터를 누르면 닫습니다'; exit 1
}
if(-not $po[0].PSObject.Properties['cha']){
  Write-Output '!! 받은 자료 모양이 이상합니다(차수 칸이 없습니다) — 그만둡니다.'
  Read-Host '엔터를 누르면 닫습니다'; exit 1
}

# ── 지금 클라우드 것을 먼저 떠 둔다 ──
$clRaw = Invoke-RestMethod -Uri ($URL+'/rest/v1/kt_po?select=*&limit=10000') -Headers $CH -TimeoutSec 300
$cl = @($clRaw)                      # 먼저 받아 두고 풀어야 줄 수가 맞는다
$safe = Join-Path 'D:\kiturami_백업' ('클라우드_발주현황_맞추기전_' + (Get-Date -Format 'yyyy-MM-dd_HHmm') + '.json')
[IO.File]::WriteAllText($safe, (ConvertTo-Json -InputObject @($cl) -Depth 20 -Compress), $U8)
Write-Output ('클라우드 발주현황 : ' + $cl.Count + '줄  (되돌릴 사본 : ' + $safe + ')')

$hk=@{}; foreach($r in $po){ $hk[([string]$r.cha + '|' + ([string]$r.pn).ToUpper().Replace(' ',''))]=1 }
$gone=@($cl | Where-Object { -not $hk.ContainsKey([string]$_.cha + '|' + ([string]$_.pn).ToUpper().Replace(' ','')) })
Write-Output ''
Write-Output ('덮어쓸 줄 : ' + $po.Count + '   ·   클라우드에만 남아 지울 줄 : ' + $gone.Count)
if($gone.Count){ $gone | Sort-Object cha,pn | Select-Object -First 20 | ForEach-Object { '    지움  {0,-14} {1}' -f $_.cha,$_.pn } }
if($cl.Count -gt 0 -and ($gone.Count / $cl.Count) -gt 0.2){
  Write-Output ''
  Write-Output ('!! 지울 줄이 너무 많습니다(' + $gone.Count + '/' + $cl.Count + ') — 뭔가 잘못된 것으로 보여 그만둡니다.')
  Write-Output '   사이트 자료를 제대로 못 받았을 수 있습니다. 그대로 두었습니다.'
  Read-Host '엔터를 누르면 닫습니다'; exit 1
}
Write-Output ''
if((Read-Host '이대로 맞출까요? (y/n)') -ne 'y'){ Write-Output '그만두었습니다.'; Read-Host '엔터'; exit 0 }

Cloud-Up 'kt_po' $po 'cha,pn'
Write-Output ('덮어썼습니다 : ' + $po.Count + '줄')
foreach($g in $gone){
  $u2 = '{0}/rest/v1/kt_po?cha=eq.{1}&pn=eq.{2}' -f $URL, [Uri]::EscapeDataString([string]$g.cha), [Uri]::EscapeDataString([string]$g.pn)
  [void](Invoke-WebRequest -Uri $u2 -Method Delete -Headers $CH -UseBasicParsing -TimeoutSec 120)
}
if($gone.Count){ Write-Output ('지웠습니다 : ' + $gone.Count + '줄') }

# ── 발주현황에 매달린 설정(수기 표시·변경코드·인보이스 기록)도 옮긴다 ──
try{
  $cfgRaw = Host-Rows 'kt_psi_cfg'
  $cfg = @($cfgRaw)
  Cloud-Up 'kt_psi_cfg' $cfg 'id'
  Write-Output ('설정 옮김 : ' + $cfg.Count + '칸')
}catch{ Write-Output ('※ 설정은 못 옮겼습니다 — ' + $_.Exception.Message.Split([char]10)[0]) }

$chkRaw = Invoke-RestMethod -Uri ($URL+'/rest/v1/kt_po?select=cha,qty,supplied&limit=10000') -Headers $CH -TimeoutSec 300
$chk = @($chkRaw)
$q=($chk|Measure-Object qty -Sum).Sum; $s=($chk|Measure-Object supplied -Sum).Sum
Write-Output ''
Write-Output ('끝났습니다 — 클라우드 발주현황 {0}줄 · 수주 {1:N0} · 공급 {2:N0} · 미공급 {3:N0}' -f $chk.Count,$q,$s,($q-$s))
Write-Output ''
Read-Host '엔터를 누르면 닫습니다'
