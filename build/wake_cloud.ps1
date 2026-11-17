param([switch]$NoBackup)
# 클라우드(Supabase)가 쉬지 않게 가볍게 두드린다.
#   무료 플랜은 일주일만 아무도 안 쓰면 Paused 가 되고, 그대로 오래 두면 지워진다.
#   하루 한 번 자료를 한 줄만 읽어 오면 '쓰는 중' 으로 쳐 준다.
#   덤으로, 떠 둔 백업이 7일보다 오래됐으면 그때 한 번 통째로 받아 둔다.
#   작업 스케줄러가 이 파일을 부른다(사람이 볼 필요 없다). 한 일은 아래 기록에 쌓인다.
#     기록 : D:\kiturami_백업\_깨우기기록.txt

$ErrorActionPreference = 'Stop'
$ROOT   = Split-Path -Parent $PSScriptRoot
$U8     = New-Object Text.UTF8Encoding $false
$LOGDIR = 'D:\kiturami_백업'
$LOG    = Join-Path $LOGDIR '_깨우기기록.txt'
if(-not (Test-Path $LOGDIR)){ [void](New-Item -ItemType Directory -Path $LOGDIR -Force) }
function Say($m){
  $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $m
  Write-Output $line
  try{ Add-Content -Path $LOG -Value $line -Encoding UTF8 }catch{}
}

try{
  $html = [IO.File]::ReadAllText((Join-Path $ROOT 'index.html'), $U8)
  $URL  = [regex]::Match($html, "const SUPABASE_URL='([^']+)'").Groups[1].Value
  $KEY  = [regex]::Match($html, "const SUPABASE_KEY='([^']+)'").Groups[1].Value
  if(-not $URL -or -not $KEY){ throw 'index.html 에서 클라우드 주소를 못 찾았습니다' }

  $H = @{ apikey = $KEY; Authorization = ('Bearer ' + $KEY) }
  $r = Invoke-RestMethod -Uri ($URL + '/rest/v1/kt_psi_cfg?select=id&limit=1') -Headers $H -TimeoutSec 90
  Say ('깨움 — 응답 받음 (줄 ' + (@($r).Count) + ')')
}catch{
  # 쉬고 있으면 주소가 아예 안 잡힌다 — 그때는 사람이 Resume 를 눌러야 한다
  Say ('!! 못 깨웠습니다 — ' + $_.Exception.Message.Split([char]10)[0])
  Say ('   supabase.com 에서 프로젝트가 Paused 인지 보고 Resume 를 눌러 주세요')
  exit 1
}

if($NoBackup){ exit 0 }

# 떠 둔 백업이 7일보다 오래됐으면 한 번 받아 둔다
try{
  $last = Get-ChildItem $LOGDIR -Directory -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{4}$' } |
          Sort-Object Name -Descending | Select-Object -First 1
  $old = (-not $last) -or ((Get-Date) - $last.LastWriteTime).TotalDays -ge 7
  if($old){
    Say '백업이 오래됐습니다 — 통째로 받습니다'
    & (Join-Path $PSScriptRoot 'backup_cloud.ps1') | Out-Null
    $new = Get-ChildItem $LOGDIR -Directory | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{4}$' } |
           Sort-Object Name -Descending | Select-Object -First 1
    if($new){ Say ('백업 끝 — ' + $new.FullName) }
  }else{
    Say ('백업은 그대로 둡니다 (가장 새 것 ' + $last.Name + ')')
  }
}catch{
  Say ('!! 백업 못 받음 — ' + $_.Exception.Message.Split([char]10)[0])
}
