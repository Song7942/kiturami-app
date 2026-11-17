param([string]$OutRoot = 'D:\kiturami_백업')
$ErrorActionPreference = 'Stop'
# kituramiparts.com(자체 서버)의 MySQL 자료를 통째로 내 컴퓨터에 떠 둔다.
#   api/db.php 는 로그인한 사람만 받으므로, 먼저 api/auth.php 로 로그인한다.
#   아이디·비밀번호는 묻기만 하고 담지 않는다(화면에도 안 찍힌다).
#   쓰는 법 : 탐색기에서 '자체서버 백업.cmd' 를 눌러 쓴다(글자를 넣어야 해서 창이 필요하다).

$SITE = 'https://kituramiparts.com'
$TABLES = @('kt_po','kt_ship','kt_psi','kt_psi_cfg','kt_pn_overrides','kt_pn_specs',
            'kt_users','kt_orders','kt_inventory','kt_shipments','kt_company_prices',
            'kt_price_calc','kt_price_settings','kt_prices','kt_names_en','kt_export_ctrl',
            'kt_user_prefs','kt_order_requests','kt_order_allocations',
            'kt_news_posts','kt_news_replies','kt_group_change_requests')

$U8 = New-Object Text.UTF8Encoding $false
Write-Output ('자리 : ' + $SITE)
$id = Read-Host '사이트 아이디 (MASTER 등)'
$pwSec = Read-Host '비밀번호' -AsSecureString
$b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwSec)
try { $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }

# 화면이 하는 것과 같은 길로 로그인한다. 쿠키를 들고 다녀야 db.php 가 받아 준다.
$sess = $null
$body = @{ op = 'login'; id = $id; pw = $pw } | ConvertTo-Json -Compress
$pw = $null
try {
  $r = Invoke-WebRequest -Uri ($SITE + '/api/auth.php') -Method Post -ContentType 'application/json' `
        -Body $body -SessionVariable sess -UseBasicParsing -TimeoutSec 60
  $j = $r.Content | ConvertFrom-Json
  if (-not $j.ok) {
    $why = if ($j.reason) { $j.reason } else { 'error' }
    $msg = switch ($why) {
      'empty'    { '아이디·비밀번호를 넣어 주세요' }
      'pending'  { '가입 승인 대기 중인 아이디입니다' }
      'rejected' { '가입이 거부된 아이디입니다' }
      default    { '아이디 또는 비밀번호가 맞지 않습니다' }
    }
    throw ('로그인 실패 — ' + $msg)
  }
} catch { Write-Output ('!! ' + $_.Exception.Message.Split([char]10)[0]); Read-Host '엔터를 누르면 닫습니다'; exit 1 }
Write-Output ('로그인 되었습니다 — ' + $j.user.id)

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$dir = Join-Path (Join-Path $OutRoot 'kituramiparts') $stamp
[void](New-Item -ItemType Directory -Path $dir -Force)
Write-Output ('담는 곳 : ' + $dir)
Write-Output ''

# 중간에 끊겨도 다시 돌리면 이어받는다 — 이미 받아 둔 표는 건너뛴다.
#   같은 날 받다 만 자리가 있으면 그 자리에 이어 담는다.
$prev = Get-ChildItem (Split-Path $dir -Parent) -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne (Split-Path $dir -Leaf) } | Sort-Object Name -Descending | Select-Object -First 1
if ($prev -and -not (Get-ChildItem $prev.FullName -Filter '_백업정보.json' -ErrorAction SilentlyContinue)) {
  Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
  $dir = $prev.FullName
  Write-Output ('받다 만 자리에 이어 담습니다 : ' + $dir)
  Write-Output ''
}

$total = 0; $failed = @()
foreach ($t in $TABLES) {
  $out = Join-Path $dir ($t + '.json')
  if (Test-Path $out) {
    try { $old = (Get-Content $out -Raw | ConvertFrom-Json); $total += @($old).Count
          Write-Output ('  {0,-24} {1,8:N0} 줄  (이미 받아 둠)' -f $t, @($old).Count); continue }
    catch { Remove-Item $out -Force }      # 깨진 파일이면 다시 받는다
  }
  $rows = New-Object Collections.ArrayList
  $from = 0; $page = 1000; $try = 0
  try {
    while ($true) {
      $q = @{ t = $t; op = 'select'; cols = '*'; filters = @(); order = @(); limit = $page; offset = $from } | ConvertTo-Json -Depth 5 -Compress
      try {
        $rr = Invoke-RestMethod -Uri ($SITE + '/api/db.php') -Method Post -ContentType 'application/json' `
                -Body $q -WebSession $sess -TimeoutSec 300
        $try = 0
      } catch {
        $try++
        if ($try -ge 3) { throw }
        Write-Host ('    (' + $t + ' ' + $from + '줄째에서 걸려 다시 받습니다 ' + $try + '/3)')
        Start-Sleep -Seconds 5
        continue
      }
      if ($rr.error) { throw $rr.error.message }
      $n = 0
      if ($null -ne $rr.data) { foreach ($x in $rr.data) { [void]$rows.Add($x); $n++ } }
      if ($n -lt $page) { break }
      $from += $page
      if ($from % 10000 -eq 0) { Write-Host ('    ' + $t + ' ' + ('{0:N0}' -f $from) + '줄…') }
    }
    $json = if ($rows.Count -eq 0) { '[]' } else { $rows | ConvertTo-Json -Depth 20 -Compress }
    if ($rows.Count -eq 1 -and -not $json.StartsWith('[')) { $json = '[' + $json + ']' }
    [IO.File]::WriteAllText($out, $json, $U8)
    $total += $rows.Count
    Write-Output ('  {0,-24} {1,8:N0} 줄' -f $t, $rows.Count)
  } catch {
    $failed += $t
    Write-Output ('  {0,-24} 실패 — {1}' -f $t, $_.Exception.Message.Split([char]10)[0])
    Write-Output ('      (다시 돌리시면 받아 둔 것은 건너뛰고 이것부터 이어받습니다)')
  }
}
$note = [ordered]@{ at = (Get-Date).ToString('s'); site = $SITE; rows = $total; failed = $failed }
[IO.File]::WriteAllText((Join-Path $dir '_백업정보.json'), ($note | ConvertTo-Json -Depth 5), $U8)
$mb = ((Get-ChildItem $dir -File | Measure-Object Length -Sum).Sum / 1MB)
Write-Output ''
Write-Output ('끝났습니다 : {0:N0} 줄 · {1:N1} MB' -f $total, $mb)
if ($failed.Count) { Write-Output ('※ 못 받은 표 : ' + ($failed -join ', ')) }
Write-Output ('자리 : ' + $dir)
Write-Output ''
Write-Output '※ kt_users 에는 비밀번호 해시가 들어 있습니다 — 공유 폴더(Z:)에 두지 마세요.'
Write-Output ''
Read-Host '엔터를 누르면 닫습니다'
