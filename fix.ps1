# LU4 긴급 수정: 멈추는 업데이터(WMI 프로세스 조회)를 고친 최신 파일로 교체합니다. (made by DoZ)
# 게임 파일/메모리는 건드리지 않고, 내 설정(키/명단/용어/위치)은 그대로 둡니다.
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem
$base = 'https://raw.githubusercontent.com/qsejinp/LU4-Tools/main/'
$keep = @('deepl_key.txt', 'clan_members.txt', 'chat_glossary.txt', 'loot_alert.wav', 'chat_alert.wav')
$keepPat = '(_cfg\.json|_error\.log|_debug\.log|update_log\.txt)$'
$done = 0
foreach ($prog in @('LU4_ChatTranslate', 'LU4_GrindMeter')) {
  # 1) 설치 폴더 찾기
  $roots = @('C:\LU4_Tools', (Join-Path $env:LOCALAPPDATA 'LU4_Tools'), (Join-Path $env:USERPROFILE 'Desktop'), (Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Documents'), $env:USERPROFILE)
  $dir = $null
  foreach ($r in $roots) {
    if ($r -and (Test-Path $r)) {
      $f = Get-ChildItem -Path $r -Recurse -Depth 3 -Filter ($prog + '.ps1') -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($f) { $dir = $f.Directory.FullName; break }
    }
  }
  if (-not $dir) { Write-Host ("[$prog] 설치 폴더를 못 찾았어요. 건너뜀.") -ForegroundColor Yellow; continue }
  Write-Host ("[$prog] 설치 폴더: " + $dir)
  # 2) 최신 압축 받기 (GitHub 캐시 피하기)
  $tmp = Join-Path $env:TEMP ($prog + '_fix.zip')
  try {
    $wc = New-Object System.Net.WebClient; $wc.Headers.Add('User-Agent', 'LU4-Fix')
    $wc.DownloadFile($base + $prog + '.zip?t=' + [DateTime]::UtcNow.Ticks, $tmp); $wc.Dispose()
  } catch { Write-Host ("[$prog] 다운로드 실패: " + $_.Exception.Message) -ForegroundColor Red; continue }
  # 3) 프로그램 파일 교체 (내 설정은 그대로)
  $z = [System.IO.Compression.ZipFile]::OpenRead($tmp); $n = 0
  try {
    foreach ($e in $z.Entries) {
      if (-not $e.Name) { continue }
      $leaf = $e.Name
      $dst = Join-Path $dir ($e.FullName -replace '/', '\')
      if (($keep -contains $leaf -or $leaf -match $keepPat) -and (Test-Path $dst)) { continue }
      $pdir = Split-Path $dst -Parent; if (-not (Test-Path $pdir)) { New-Item -ItemType Directory -Path $pdir -Force | Out-Null }
      [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dst, $true); $n++
    }
  } finally { $z.Dispose(); Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
  Write-Host ("[$prog] 완료! 파일 " + $n + "개 최신으로 교체 (설정 유지)") -ForegroundColor Green
  $done++
}
Write-Host ''
if ($done) { Write-Host '다 됐어요! 프로그램이 켜져 있으면 끄고, 바탕화면 아이콘으로 다시 켜세요. 다음부터는 업데이트(UP)가 멈추지 않습니다.' -ForegroundColor Cyan }
else { Write-Host '설치 폴더를 찾지 못했어요. 프로그램이 설치된 폴더 경로를 알려주세요.' -ForegroundColor Yellow }
