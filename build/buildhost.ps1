param([switch]$WithPrice, [switch]$OwnDb)
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
$html=$html.Replace($stag, $repl)
if($OwnDb){
  # the cloud address is no longer used
  $html=[regex]::Replace($html, "const SUPABASE_URL\s*=\s*'[^']*'", "const SUPABASE_URL=''")
  $html=[regex]::Replace($html, "const SUPABASE_KEY\s*=\s*'[^']*'", "const SUPABASE_KEY=''")
}

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
