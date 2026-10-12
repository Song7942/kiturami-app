param([string]$Out, [switch]$NoPrice)
$ErrorActionPreference='Stop'
# Make a stand-alone HTML of the whole site for the MASTER account.
#   in  : ..\index.html  +  offline_boot.js   (the fake sb client)
#   out : -Out, or ..\..\KITURAMI_MASTER_<date>.html
# The file opens straight into the MASTER view with a snapshot of every table.
# Nothing leaves the machine: the Supabase and XLSX script tags are taken out
# and the Excel library is baked in, so downloads still work offline.
#   -NoPrice : serve the price tables empty (for handing the file to someone else)

$ROOT  = Split-Path -Parent $PSScriptRoot            # ...\kiturami-app
$SRC   = Join-Path $ROOT 'index.html'
$BOOT  = Join-Path $PSScriptRoot 'offline_boot.js'
$U8    = New-Object Text.UTF8Encoding $false
$today = Get-Date -Format 'yyyy-MM-dd'
if(-not $Out){ $Out = Join-Path (Split-Path -Parent $ROOT) ("KITURAMI_MASTER_$today.html") }

$html = [IO.File]::ReadAllText($SRC, $U8)
$m = [regex]::Match($html, "const SUPABASE_URL='([^']+)'")
$k = [regex]::Match($html, "const SUPABASE_KEY='([^']+)'")
if(-not ($m.Success -and $k.Success)){ throw 'supabase url/key not found' }
$BASE = $m.Groups[1].Value + '/rest/v1/'
$HDR  = @{ apikey = $k.Groups[1].Value; Authorization = 'Bearer ' + $k.Groups[1].Value }

$TABLES = @('kt_company_prices','kt_export_ctrl','kt_group_change_requests','kt_inventory',
            'kt_names_en','kt_news_posts','kt_news_replies','kt_order_allocations',
            'kt_order_requests','kt_orders','kt_pn_overrides','kt_pn_specs','kt_po',
            'kt_price_calc','kt_price_settings','kt_prices','kt_psi','kt_psi_cfg',
            'kt_ship','kt_shipments','kt_user_prefs','kt_users')
$PRICE_TABLES = @('kt_price_calc','kt_price_settings','kt_prices','kt_company_prices')

# PostgREST hands back at most 1,000 rows, so walk the table a page at a time.
#   Invoke-RestMethod nests arrays when you let it, so collect into a list by hand.
function Get-Table([string]$t){
  $rows = New-Object Collections.ArrayList
  $from = 0
  while($true){
    $url = $BASE + $t + '?select=*&limit=1000&offset=' + $from
    $page = Invoke-RestMethod -Uri $url -Headers $HDR -Method Get
    $n = 0
    foreach($r in $page){ [void]$rows.Add($r); $n++ }
    if($n -lt 1000){ break }
    $from += 1000
  }
  return ,$rows
}

# kt_pn_specs is the whole item master (130k rows, 20MB). The site only ever looks up
# part numbers it already knows, so keep those rows and drop the rest — the file goes
# from 25MB to about 6MB and opens in a second instead of ten.
function Get-KeepPNs(){
  $keep = New-Object 'System.Collections.Generic.HashSet[string]'
  $add = { param($v) if($v){ $s=([string]$v).Trim().ToUpper() -replace '\s',''; if($s){ [void]$keep.Add($s) } } }
  foreach($r in (Get-Table 'kt_pn_overrides')){
    & $add $r.rep; & $add $r.final
    foreach($c in @($r.compats)){ & $add $c }
  }
  foreach($t in @('kt_psi','kt_po','kt_ship','kt_prices')){
    foreach($r in (Get-Table $t)){ & $add $r.pn; & $add $r.rep }
  }
  foreach($r in (Get-Table 'kt_price_calc')){ & $add $r.compat; & $add $r.rep; & $add $r.final }
  # 대체품목 (kt_psi_cfg id=100) — 그 품번들의 품명도 화면에 나온다
  foreach($r in (Get-Table 'kt_psi_cfg')){
    if([string]$r.id -ne '100'){ continue }
    $alt = $r.cfg.alt
    if(-not $alt){ continue }
    foreach($p in $alt.PSObject.Properties){
      & $add $p.Name
      foreach($e in @($p.Value)){ if($e -is [string]){ & $add $e } else { & $add $e.p } }
    }
  }
  return ,$keep
}
$keepPN = Get-KeepPNs
Write-Output ('{0,-28} {1,8} kept' -f 'pn filter', $keepPN.Count)

$parts = New-Object Collections.ArrayList
$total = 0
foreach($t in $TABLES){
  if($NoPrice -and ($PRICE_TABLES -contains $t)){
    [void]$parts.Add('"' + $t + '":[]')
    Write-Output ('{0,-28} skipped (price)' -f $t)
    continue
  }
  $rows = Get-Table $t
  if($t -eq 'kt_pn_specs'){
    $all = $rows.Count
    $cut = New-Object Collections.ArrayList
    foreach($r in $rows){
      $s = ([string]$r.pn).Trim().ToUpper() -replace '\s',''
      if($keepPN.Contains($s)){ [void]$cut.Add($r) }
    }
    Write-Output ('{0,-28} {1,8} of {2} kept' -f $t, $cut.Count, $all)
    $rows = $cut
  }
  $json = if($rows.Count -eq 0){ '[]' } else { ConvertTo-Json -InputObject @($rows) -Depth 12 -Compress }
  [void]$parts.Add('"' + $t + '":' + $json)
  $total += $rows.Count
  Write-Output ('{0,-28} {1,8} rows' -f $t, $rows.Count)
}
$db = '{' + ($parts -join ',') + '}'

# The Excel library is baked in so the download buttons keep working with no internet.
$xlsxTag = [regex]::Match($html, '<script src="https://[^"]*xlsx[^"]*"></script>')
$xlsxJs = ''
if($xlsxTag.Success){
  $u = [regex]::Match($xlsxTag.Value, 'src="([^"]+)"').Groups[1].Value
  Write-Output ('xlsx                         fetching ' + $u)
  $xlsxJs = (Invoke-WebRequest -Uri $u -UseBasicParsing).Content
}

$boot = [IO.File]::ReadAllText($BOOT, $U8)
$dbJs = 'window.__DB__=' + ($db -replace '</(script)', '<\/$1') + ';'
$inject = '<script>' + $xlsxJs + "`r`n</script>`r`n" + '<script>' + $dbJs + "`r`n" + $boot + "`r`n</script>"

# the cloud client and the cdn library are replaced by what we just baked in
$html = [regex]::Replace($html, '<script src="https://[^"]*xlsx[^"]*"></script>\s*', '')
$sb = [regex]::Match($html, '<script src="https://cdn\.jsdelivr\.net/npm/@supabase[^"]*"></script>')
if(-not $sb.Success){ throw 'supabase cdn tag not found' }
$html = $html.Replace($sb.Value, $inject)

[IO.File]::WriteAllText($Out, $html, $U8)
Write-Output ''
Write-Output ('output : ' + $Out)
Write-Output ('rows   : {0:N0}' -f $total)
Write-Output ('size   : {0:N1} MB' -f ((Get-Item $Out).Length/1MB))
if($NoPrice){ Write-Output 'price  : hidden (tables served empty)' } else { Write-Output 'price  : included' }
