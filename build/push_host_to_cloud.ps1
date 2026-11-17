param(
  [string]$From = '',                 # 자체서버 백업 폴더(비우면 가장 새 것)
  [string[]]$Only = @(),              # 이 표들만 (비우면 아래 목록 전부)
  [switch]$WhatIf,                    # 보기만 하고 올리지는 않는다
  [switch]$DropNulls                  # 비어 있는 칸은 빼고 보낸다(표 구조가 조금 다를 때)
)
$ErrorActionPreference = 'Stop'
# 자체서버(kituramiparts.com)에서 떠 둔 자료를 클라우드(Supabase)로 옮겨 담는다.
#   · 덮어쓰기(upsert)만 한다 — 클라우드에만 있는 줄은 지우지 않는다.
#   · 열쇠가 같으면 자체서버 값이 이긴다(그쪽이 최신이라서).
#   먼저 build\backup_host.ps1 로 자체서버를 떠 두어야 한다.

$ROOT = Split-Path -Parent $PSScriptRoot
$U8   = New-Object Text.UTF8Encoding $false
$html = [IO.File]::ReadAllText((Join-Path $ROOT 'index.html'), $U8)
$URL  = [regex]::Match($html, "const SUPABASE_URL='([^']+)'").Groups[1].Value
$KEY  = [regex]::Match($html, "const SUPABASE_KEY='([^']+)'").Groups[1].Value
if(-not $URL -or -not $KEY){ throw 'index.html 에서 클라우드 주소를 못 찾았습니다' }

if(-not $From){
  $root='D:\kiturami_백업\kituramiparts'
  $d = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
       Where-Object { Test-Path (Join-Path $_.FullName '_백업정보.json') } |   # 끝까지 받은 것만
       Sort-Object Name -Descending | Select-Object -First 1
  if(-not $d){ throw ('끝까지 받아 둔 자체서버 백업이 없습니다 — ' + $root) }
  $From = $d.FullName
}
if(-not (Test-Path $From)){ throw ('그런 폴더가 없습니다 : ' + $From) }

# 옮길 표와 그 표의 열쇠(겹치면 덮어쓸 기준)
$PLAN = [ordered]@{
  'kt_po'                    = 'cha,pn'
  'kt_ship'                  = 'inv,pn'
  'kt_psi_cfg'               = 'id'
  'kt_pn_overrides'          = 'rep'
  'kt_pn_specs'              = 'pn'
  'kt_psi'                   = 'pn'
  'kt_users'                 = 'id'
  'kt_company_prices'        = 'company,rep'
  'kt_names_en'              = 'rep'
  'kt_export_ctrl'           = 'pn'
  'kt_price_calc'            = 'row_no'
  'kt_inventory'             = ''
  'kt_shipments'             = ''
  'kt_orders'                = ''
  'kt_order_allocations'     = ''
  'kt_order_requests'        = ''
  'kt_user_prefs'            = ''
  'kt_news_posts'            = ''
  'kt_news_replies'          = ''
  'kt_group_change_requests' = ''
}
$tables = if($Only.Count){ $Only } else { @($PLAN.Keys) }

Write-Output ('가져올 곳 : ' + $From)
Write-Output ('담을 곳   : ' + $URL)
if($WhatIf){ Write-Output '※ 보기만 합니다 — 올리지 않습니다' }
Write-Output ''

$okN = 0; $failed = @()
foreach($t in $tables){
  $p = Join-Path $From ($t + '.json')
  if(-not (Test-Path $p)){ Write-Output ('  {0,-24} 백업에 없습니다 — 건너뜀' -f $t); continue }
  try{
    # ConvertFrom-Json 은 배열을 '한 덩어리'로 내보낸다 — 먼저 받아 두고 나서 풀어야 줄 수가 맞는다
    $parsed = [IO.File]::ReadAllText($p, $U8) | ConvertFrom-Json
    $rows = @($parsed)
  }catch{
    $failed += $t; Write-Output ('  {0,-24} 읽지 못했습니다 — {1}' -f $t, $_.Exception.Message.Split([char]10)[0]); continue
  }
  if($rows.Count -eq 0){ Write-Output ('  {0,-24} 빈 표 — 건너뜀' -f $t); continue }
  if($WhatIf){ Write-Output ('  {0,-24} {1,8:N0} 줄 (올릴 예정)' -f $t, $rows.Count); continue }

  $H = @{ apikey=$KEY; Authorization=('Bearer '+$KEY); 'Content-Type'='application/json';
          Prefer='resolution=merge-duplicates,return=minimal' }
  $uri = $URL + '/rest/v1/' + $t
  if($PLAN[$t]){ $uri += ('?on_conflict=' + $PLAN[$t]) }
  $size = 300; $sent = 0; $bad = $null
  for($i=0; $i -lt $rows.Count; $i+=$size){
    $chunk = $rows[$i..([Math]::Min($i+$size-1, $rows.Count-1))]
    # 자체서버에 없는 칸은 빼고 보낸다 — 클라우드 쪽에 '비우면 안 되는 칸'이 있어도 걸리지 않게.
    #   (빠진 칸은 이미 있던 값이 그대로 남고, 새 줄이면 기본값이 들어간다)
    if($DropNulls){
      $chunk = @($chunk | ForEach-Object {
        $o=[ordered]@{}
        foreach($pp in $_.PSObject.Properties){ if($null -ne $pp.Value){ $o[$pp.Name]=$pp.Value } }
        [pscustomobject]$o })
    }
    $body  = ConvertTo-Json -InputObject @($chunk) -Depth 20 -Compress
    $try = 0
    while($true){
      try{
        [void](Invoke-WebRequest -Uri $uri -Method Post -Headers $H -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing -TimeoutSec 300)
        $sent += $chunk.Count
        break
      }catch{
        $try++
        if($try -ge 3){
          $msg = $_.Exception.Message
          try{ $sr=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $msg=$sr.ReadToEnd() }catch{}
          $bad = $msg.Split([char]10)[0]; break
        }
        Start-Sleep -Seconds 4
      }
    }
    if($bad){ break }
    if($rows.Count -gt 5000 -and ($i % 15000) -eq 0 -and $i -gt 0){ Write-Host ('    ' + $t + ' ' + ('{0:N0}' -f $i) + '줄…') }
  }
  if($bad){ $failed += $t; Write-Output ('  {0,-24} 실패 ({1:N0}/{2:N0}줄) — {3}' -f $t,$sent,$rows.Count,$bad) }
  else     { $okN++;       Write-Output ('  {0,-24} {1,8:N0} 줄 옮김' -f $t,$sent) }
}
Write-Output ''
if($WhatIf){ Write-Output '보기만 했습니다.'; return }
Write-Output ('끝났습니다 — 표 {0}개 옮김' -f $okN)
if($failed.Count){ Write-Output ('※ 못 옮긴 표 : ' + ($failed -join ', ')) }
Write-Output '※ 클라우드에만 있던 줄은 지우지 않았습니다(덮어쓰기만 했습니다).'
