# LU4 emergency fix: replaces the hanging updater (WMI process query) with the fixed version. (made by DoZ)
# Does NOT touch game files/memory. Keeps your settings (key/members/glossary/window position).
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem
$base = 'https://raw.githubusercontent.com/qsejinp/LU4-Tools/main/'
$keep = @('deepl_key.txt', 'clan_members.txt', 'chat_glossary.txt', 'loot_alert.wav', 'chat_alert.wav')
$keepPat = '(_cfg\.json|_error\.log|_debug\.log|update_log\.txt)$'
$sh = New-Object -ComObject WScript.Shell

function Find-Dir($prog) {
  # 1) read install folder from shortcuts (.lnk) - most reliable (works even with OneDrive desktop)
  $kDesk = -join ([char]0xBC14, [char]0xD0D5, [char]0x20, [char]0xD654, [char]0xBA74)  # "바탕 화면"
  $lnkRoots = @()
  $lnkRoots += (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\LU4 Tools')
  foreach ($dp in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('DesktopDirectory'), (Join-Path $env:USERPROFILE 'Desktop'), (Join-Path $env:USERPROFILE 'OneDrive\Desktop'), (Join-Path $env:USERPROFILE ('OneDrive\' + $kDesk)))) { if ($dp) { $lnkRoots += $dp } }
  try { $lnkRoots += (Get-ChildItem $env:USERPROFILE -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Desktop' -or $_.Name -eq $kDesk } | Select-Object -Expand FullName) } catch {}
  foreach ($lr in $lnkRoots) {
    if ($lr -and (Test-Path $lr)) {
      foreach ($lnk in (Get-ChildItem $lr -Filter *.lnk -ErrorAction SilentlyContinue)) {
        try {
          $s = $sh.CreateShortcut($lnk.FullName)
          if ($s.WorkingDirectory -and (Test-Path (Join-Path $s.WorkingDirectory ($prog + '.ps1')))) { return $s.WorkingDirectory }
          if ($s.Arguments -match [regex]::Escape($prog + '_run.vbs')) { $vb = ($s.Arguments -replace '"', '').Trim(); $pd = Split-Path $vb -Parent; if ($pd -and (Test-Path (Join-Path $pd ($prog + '.ps1')))) { return $pd } }
        } catch {}
      }
    }
  }
  # 2) broad search
  $roots = @('C:\LU4_Tools', (Join-Path $env:LOCALAPPDATA 'LU4_Tools'), $env:OneDrive, (Join-Path $env:USERPROFILE 'OneDrive'), $env:USERPROFILE)
  foreach ($r in $roots) {
    if ($r -and (Test-Path $r)) {
      $f = Get-ChildItem -Path $r -Recurse -Depth 4 -Filter ($prog + '.ps1') -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($f) { return $f.Directory.FullName }
    }
  }
  return $null
}

$done = 0
foreach ($prog in @('LU4_ChatTranslate', 'LU4_GrindMeter')) {
  $dir = Find-Dir $prog
  if (-not $dir) { Write-Host ("[" + $prog + "] install folder NOT found - skipped") -ForegroundColor Yellow; continue }
  Write-Host ("[" + $prog + "] folder: " + $dir)
  $tmp = Join-Path $env:TEMP ($prog + '_fix.zip')
  try {
    $wc = New-Object System.Net.WebClient; $wc.Headers.Add('User-Agent', 'LU4-Fix')
    $wc.DownloadFile($base + $prog + '.zip?t=' + [DateTime]::UtcNow.Ticks, $tmp); $wc.Dispose()
  } catch { Write-Host ("[" + $prog + "] download failed: " + $_.Exception.Message) -ForegroundColor Red; continue }
  $z = [System.IO.Compression.ZipFile]::OpenRead($tmp); $n = 0
  try {
    foreach ($e in $z.Entries) {
      if (-not $e.Name) { continue }
      $leaf = $e.Name
      $dst = Join-Path $dir ($e.FullName -replace '/', '\')
      if (($keep -contains $leaf -or $leaf -match $keepPat) -and (Test-Path $dst)) { continue }
      $pdir = Split-Path $dst -Parent; if (-not (Test-Path $pdir)) { New-Item -ItemType Directory -Path $pdir -Force | Out-Null }
      if (Test-Path $dst) { try { (Get-Item $dst -Force).Attributes = [System.IO.FileAttributes]::Normal } catch {} }
      try { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dst, $true); $n++ }
      catch { try { Remove-Item $dst -Force -ErrorAction Stop; [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dst, $true); $n++ } catch { Write-Host ("  ! " + $leaf + " failed (in use?): " + $_.Exception.Message) -ForegroundColor DarkYellow } }
    }
  } finally { $z.Dispose(); Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
  Write-Host ("[" + $prog + "] DONE - " + $n + " files updated (settings kept)") -ForegroundColor Green
  $done++
}
Write-Host ''
if ($done) { Write-Host 'ALL DONE! Close the program if open, then start it from the desktop icon. Update (UP) will no longer hang.' -ForegroundColor Cyan }
else { Write-Host 'Could not find the install folder. Please tell me the full path where the program is installed.' -ForegroundColor Yellow }
