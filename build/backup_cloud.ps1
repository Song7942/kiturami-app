param([string]$OutRoot = 'D:\kiturami_백업')
$ErrorActionPreference = 'Stop'
# 클라우드(Supabase) 자료를 통째로 내 컴퓨터에 떠 둔다.
#   표마다 .json 한 개. 1,000줄씩 나눠 받아 이어 붙인다(서버가 한 번에 그만큼만 준다).
#   ※ kt_users 에는 비밀번호 해시가 들어 있다 — 공유 폴더에 두지 말 것.
#   쓰는 법 :  powershell -ExecutionPolicy Bypass -File backup_cloud.ps1
#             powershell ... -File backup_cloud.ps1 -OutRoot "D:\다른곳"

$ROOT = Split-Path -Parent $PSScriptRoot                 # ...\kiturami-app
$U8   = New-Object Text.UTF8Encoding $false
$html = [IO.File]::ReadAllText((Join-Path $ROOT 'index.html'), $U8)
$URL  = [regex]::Match($html, "const SUPABASE_URL='([^']+)'").Groups[1].Value
$KEY  = [regex]::Match($html, "const SUPABASE_KEY='([^']+)'").Groups[1].Value
if(-not $URL -or -not $KEY){ throw 'index.html 에서 클라우드 주소를 못 찾았습니다' }

$TABLES = @('kt_po','kt_ship','kt_psi','kt_psi_cfg','kt_pn_overrides','kt_pn_specs',
            'kt_users','kt_orders','kt_inventory','kt_shipments','kt_company_prices',
            'kt_price_calc','kt_price_settings','kt_prices','kt_names_en','kt_export_ctrl',
            'kt_user_prefs','kt_order_requests','kt_order_allocations',
            'kt_news_posts','kt_news_replies','kt_group_change_requests')

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$dir   = Join-Path $OutRoot $stamp
[void](New-Item -ItemType Directory -Path $dir -Force)
$H = @{ apikey = $KEY; Authorization = ('Bearer ' + $KEY) }

Write-Output ('받는 곳 : ' + $URL)
Write-Output ('담는 곳 : ' + $dir)
Write-Output ''
$total = 0; $failed = @()
foreach($t in $TABLES){
  $rows = New-Object Collections.ArrayList
  $from = 0; $page = 1000
  try{
    while($true){
      # Range 머리글은 PowerShell 이 막아서, PostgREST 의 limit·offset 으로 나눠 받는다
      $uri = '{0}/rest/v1/{1}?select=*&limit={2}&offset={3}' -f $URL, $t, $page, $from
      $r = Invoke-RestMethod -Uri $uri -Headers $H -TimeoutSec 300
      $n = 0
      if($null -ne $r){ foreach($x in $r){ [void]$rows.Add($x); $n++ } }
      if($n -lt $page){ break }
      $from += $page
    }
    $json = $rows | ConvertTo-Json -Depth 20 -Compress
    if($rows.Count -eq 0){ $json = '[]' }
    elseif($rows.Count -eq 1 -and -not $json.StartsWith('[')){ $json = '[' + $json + ']' }
    [IO.File]::WriteAllText((Join-Path $dir ($t + '.json')), $json, $U8)
    $total += $rows.Count
    Write-Output ('  {0,-24} {1,8:N0} 줄  ({2:N0} bytes)' -f $t, $rows.Count, (Get-Item (Join-Path $dir ($t + '.json'))).Length)
  }catch{
    $failed += $t
    Write-Output ('  {0,-24} 실패 — {1}' -f $t, $_.Exception.Message.Split([char]10)[0])
  }
}
# 언제 어디서 떴는지 적어 둔다
$note = [ordered]@{ at = (Get-Date).ToString('s'); url = $URL; tables = $TABLES.Count; rows = $total; failed = $failed }
[IO.File]::WriteAllText((Join-Path $dir '_백업정보.json'), ($note | ConvertTo-Json -Depth 5), $U8)

$mb = ((Get-ChildItem $dir -File | Measure-Object Length -Sum).Sum / 1MB)
Write-Output ''
Write-Output ('끝났습니다 : 표 {0}개 · {1:N0} 줄 · {2:N1} MB' -f ($TABLES.Count - $failed.Count), $total, $mb)
if($failed.Count){ Write-Output ('※ 못 받은 표 : ' + ($failed -join ', ')) }
Write-Output ('자리 : ' + $dir)
Write-Output ''
Write-Output '※ kt_users 에는 비밀번호 해시가 들어 있습니다 — 공유 폴더(Z:)에 두지 마세요.'
