# kiturami-app 로컬 정적 서버 (설치 불필요 - Windows 내장 .NET HttpListener 사용)
#
#   실행:  powershell -ExecutionPolicy Bypass -NoProfile -File .\serve.ps1
#   포트 변경:  ... -File .\serve.ps1 -Port 9000
#   중지:  Ctrl+C
#
# 참고: /api/fxrate 는 Cloudflare Pages Function 이라 여기선 404 입니다.
#       앱이 시장환율(open.er-api.com)로 자동 폴백하므로 가격정보 탭은 동작합니다.
#       하나은행 고시환율까지 재현하려면 Node 설치 후 `npx wrangler pages dev .` 를 쓰세요.

param(
  [int]$Port = 8788
)

$ErrorActionPreference = 'Stop'

# 스크립트가 있는 폴더를 문서 루트로 사용 (어느 위치에서 실행해도 동작)
$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$rootFull = [System.IO.Path]::GetFullPath($root)

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")

try {
  $listener.Start()
} catch {
  Write-Host "포트 $Port 바인딩 실패: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "이미 서버가 떠 있거나 포트가 사용 중일 수 있습니다. -Port 로 다른 포트를 지정하세요." -ForegroundColor Yellow
  exit 1
}

Write-Host "kiturami-app 서빙 중" -ForegroundColor Green
Write-Host "  루트: $rootFull"
Write-Host "  주소: http://localhost:$Port/"
Write-Host "  중지: Ctrl+C"
Write-Host ""

$mimeTypes = @{
  '.html' = 'text/html; charset=utf-8'
  '.htm'  = 'text/html; charset=utf-8'
  '.js'   = 'application/javascript; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'
  '.png'  = 'image/png'
  '.jpg'  = 'image/jpeg'
  '.jpeg' = 'image/jpeg'
  '.gif'  = 'image/gif'
  '.svg'  = 'image/svg+xml'
  '.ico'  = 'image/x-icon'
  '.woff' = 'font/woff'
  '.woff2'= 'font/woff2'
}

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $req = $ctx.Request
  $res = $ctx.Response

  try {
    $rel = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath)
    if ($rel -eq '/') { $rel = '/index.html' }

    # .git 등 숨김 경로 차단 (로컬 전용이지만 .git/config 노출 방지)
    if ($rel -split '/' | Where-Object { $_.StartsWith('.') }) {
      $res.StatusCode = 403
      $b = [System.Text.Encoding]::UTF8.GetBytes('Forbidden')
      $res.ContentLength64 = $b.Length
      $res.OutputStream.Write($b, 0, $b.Length)
      Write-Host ("403 {0}" -f $rel) -ForegroundColor Yellow
      continue
    }

    $path = Join-Path $rootFull $rel.TrimStart('/')
    $full = [System.IO.Path]::GetFullPath($path)

    # 경로 탈출(../) 차단
    if (-not $full.StartsWith($rootFull)) {
      $res.StatusCode = 403
      $res.OutputStream.Close()
      Write-Host ("403 {0} (경로 탈출)" -f $rel) -ForegroundColor Yellow
      continue
    }

    if (Test-Path -LiteralPath $full -PathType Leaf) {
      $ext = [System.IO.Path]::GetExtension($full).ToLower()
      $mime = $mimeTypes[$ext]
      if (-not $mime) { $mime = 'application/octet-stream' }

      $bytes = [System.IO.File]::ReadAllBytes($full)
      $res.ContentType = $mime
      $res.ContentLength64 = $bytes.Length
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
      Write-Host ("200 {0} ({1:N0} bytes)" -f $rel, $bytes.Length)
    } else {
      $res.StatusCode = 404
      $b = [System.Text.Encoding]::UTF8.GetBytes('Not Found')
      $res.ContentLength64 = $b.Length
      $res.OutputStream.Write($b, 0, $b.Length)
      Write-Host ("404 {0}" -f $rel) -ForegroundColor DarkGray
    }
  } catch {
    Write-Host ("ERR {0}" -f $_.Exception.Message) -ForegroundColor Red
    try { $res.StatusCode = 500 } catch {}
  } finally {
    try { $res.OutputStream.Close() } catch {}
  }
}
