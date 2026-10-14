param([string]$Out)
$ErrorActionPreference='Stop'
# Dump every kt_ table from the cloud into MySQL INSERT files.
#   in  : ..\index.html (for the url/key)  +  ..\..\kiturami-host\db\01_schema.sql (for the column list)
#   out : ..\..\kiturami-host\db\02_<table>.sql
# Column order follows the schema file, so the INSERT always matches the table.

$ROOT = Split-Path -Parent $PSScriptRoot                     # ...\kiturami-app
$HOSTDIR = Join-Path (Split-Path -Parent $ROOT) 'kiturami-host'
if(-not $Out){ $Out = Join-Path $HOSTDIR 'db' }
$U8 = New-Object Text.UTF8Encoding $false

$html = [IO.File]::ReadAllText((Join-Path $ROOT 'index.html'), $U8)
$m = [regex]::Match($html, "const SUPABASE_URL='([^']+)'")
$k = [regex]::Match($html, "const SUPABASE_KEY='([^']+)'")
if(-not ($m.Success -and $k.Success)){ throw 'supabase url/key not found' }
$BASE = $m.Groups[1].Value + '/rest/v1/'
$HDR  = @{ apikey = $k.Groups[1].Value; Authorization = 'Bearer ' + $k.Groups[1].Value }

# ── column list per table, straight from the schema we ship ──
$schema = [IO.File]::ReadAllText((Join-Path $Out '01_schema.sql'), $U8)
$cols = @{}
foreach($blk in [regex]::Matches($schema, 'CREATE TABLE `([a-z_]+)` \(([\s\S]*?)\n\) ENGINE')){
  $t = $blk.Groups[1].Value
  $list = New-Object Collections.ArrayList
  foreach($line in $blk.Groups[2].Value -split "`n"){
    $c = [regex]::Match($line.Trim(), '^`([a-zA-Z0-9_]+)`\s')
    if($c.Success){ [void]$list.Add($c.Groups[1].Value) }
  }
  $cols[$t] = $list
}

Add-Type -AssemblyName System.Web.Extensions
$ser = New-Object Web.Script.Serialization.JavaScriptSerializer
$ser.MaxJsonLength = [int]::MaxValue

# MySQL 홑따옴표 문자열로. 역슬래시·따옴표·줄바꿈·NUL 을 모두 피해 적는다.
function Esc([string]$s){
  $s = $s.Replace('\','\\').Replace("'","\'")
  $s = $s.Replace("`r",'\r').Replace("`n",'\n').Replace("`t",'\t')
  $s = $s -replace "`0", ''
  return "'" + $s + "'"
}
function Val($v){
  if($null -eq $v){ return 'NULL' }
  if($v -is [bool]){ if($v){ return '1' } else { return '0' } }
  if($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]){
    return ([string]$v)
  }
  if($v -is [string]){ return (Esc $v) }
  # 배열·객체는 JSON 글자로 담는다(앱이 그대로 읽는다)
  #   ConvertTo-Json 은 빈 배열에 '' 를 내놓으므로 따로 처리한다.
  if($v -is [Array] -and $v.Count -eq 0){ return "'[]'" }
  $j = $v | ConvertTo-Json -Depth 30 -Compress
  if([string]::IsNullOrEmpty($j)){ $j = '{}' }
  return (Esc $j)
}

function Get-Rows([string]$t){
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

$total = 0
foreach($t in ($cols.Keys | Sort-Object)){
  $rows = Get-Rows $t
  $cl = $cols[$t]
  $sb = New-Object Text.StringBuilder
  [void]$sb.AppendLine('-- ' + $t + ' : ' + $rows.Count + ' rows')
  [void]$sb.AppendLine('SET NAMES utf8mb4;')
  [void]$sb.AppendLine('DELETE FROM `' + $t + '`;')
  if($rows.Count){
    $head = 'INSERT INTO `' + $t + '` (`' + ($cl -join '`,`') + '`) VALUES'
    $i = 0
    foreach($r in $rows){
      if($i % 200 -eq 0){
        if($i -gt 0){ [void]$sb.AppendLine(';') }
        [void]$sb.AppendLine($head)
      } else { [void]$sb.AppendLine(',') }
      $vals = @()
      foreach($c in $cl){
        $p = $r.PSObject.Properties[$c]
        if($null -eq $p){ $vals += 'NULL' } else { $vals += (Val $p.Value) }
      }
      [void]$sb.Append('(' + ($vals -join ',') + ')')
      $i++
    }
    [void]$sb.AppendLine(';')
  }
  $f = Join-Path $Out ('02_' + $t + '.sql')
  [IO.File]::WriteAllText($f, $sb.ToString(), $U8)
  $total += $rows.Count
  Write-Output ('{0,-28} {1,8} rows  {2,8:N0} KB' -f $t, $rows.Count, ((Get-Item $f).Length/1KB))
}
Write-Output ''
Write-Output ('tables : ' + $cols.Count)
Write-Output ('rows   : {0:N0}' -f $total)
