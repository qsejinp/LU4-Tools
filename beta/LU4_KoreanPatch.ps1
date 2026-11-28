# made by DoZ
# LU4 한글패치: 게임 폴더에 한글패치가 있는지 확인하고, 없으면(런처 파일 확인으로 지워졌으면) 다시 넣은 뒤 런처를 켬
#  -Bc    : 방송용 아이콘으로 켠 경우. 대미지 표시·지도·피로시스템 변경을 뺀 패치를 넣음
#  -Watch : 윈도우 시작 때 뒤에서 켜 두는 모드. LU4 게임이 실행 중일 때만 사용 현황 신호를 보내고, 패치가 지워졌으면 알려 줌
param([switch]$Watch, [switch]$Bc)
$Ver = '20261128.2030'
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$Title = 'LU4 한글패치'
$Data = Join-Path $env:LOCALAPPDATA 'LU4_Tools'
$CfgPath = Join-Path $Data 'korean_patch.json'
$Cache = Join-Path $Data 'patch_cache'
$LogPath = Join-Path $Data 'korean_patch.log'
$Raw = 'https://raw.githubusercontent.com/qsejinp/LU4-Tools/main/'
$Chan = $(if (Test-Path (Join-Path $Data 'beta.txt')) { 'beta/' } else { '' })   # 시험판 받는 PC
# 패치 종류: 방송용(patch_channel.txt 에 bc)이면 대미지 표시·지도·피로시스템 변경을 뺀 패치를 받음
#  아이콘으로 켤 때: 방송용 아이콘이면 bc, 일반 아이콘이면 일반. 마지막에 켠 종류를 patch_channel.txt 에 적어 둠
#  뒤에서 기다리는 모드: 적어 둔 종류를 따라감 (패치 확인 때마다 다시 읽음)
$PDir = 'patch/'; $ChanFile = Join-Path $Data 'patch_channel.txt'
function Set-PatchKind($bc) { if ($bc) { $script:PDir = 'patch_bc/'; $script:Title = 'LU4 한글패치(방송용)' } else { $script:PDir = 'patch/'; $script:Title = 'LU4 한글패치' } }
function Read-PatchKind { try { return ((Test-Path $ChanFile) -and (([string](Get-Content $ChanFile -Raw -ErrorAction Stop)).Trim() -eq 'bc')) } catch { return $false } }
if ($Watch) { Set-PatchKind (Read-PatchKind) }
else {
  Set-PatchKind ([bool]$Bc)
  try { if ($Bc) { [System.IO.File]::WriteAllText($ChanFile, 'bc') } elseif (Test-Path $ChanFile) { Remove-Item $ChanFile -Force } } catch {}
}
$GameProc = 'lu4-win64-shipping'
$LiveUrl = 'https://lu4-live.lsj9351.workers.dev/ping'
if (-not (Test-Path $Data)) { New-Item -ItemType Directory -Path $Data -Force | Out-Null }

function Log($t) { try { if ((Test-Path $LogPath) -and (Get-Item $LogPath).Length -gt 300000) { Remove-Item $LogPath -Force }; Add-Content -Path $LogPath -Encoding UTF8 -Value ('[' + (Get-Date).ToString('MM-dd HH:mm:ss') + '] ' + $t) } catch {} }
function Msg($t, $b = 'OK', $i = 'Information') {
  $o = New-Object System.Windows.Forms.Form; $o.TopMost = $true; $o.ShowInTaskbar = $false; $o.Opacity = 0; $o.StartPosition = 'CenterScreen'; $o.Show()
  try { return [System.Windows.Forms.MessageBox]::Show($o, $t, ($Title + ' (made by DoZ)'), $b, $i) } finally { $o.Close() }
}
function Get-Text($url) {
  $wc = New-Object System.Net.WebClient; $wc.Encoding = [System.Text.Encoding]::UTF8
  try { return $wc.DownloadString(($url + '?t=' + [DateTime]::UtcNow.Ticks)) } finally { $wc.Dispose() }
}
$cfg = @{ game = '' ; files = @() }
try { if (Test-Path $CfgPath) { $j = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json; if ($j.game) { $cfg.game = [string]$j.game }; if ($j.files) { $cfg.files = @($j.files | ForEach-Object { [string]$_ }) } } } catch {}
function Save-Cfg { try { @{ game = $cfg.game; files = @($cfg.files) } | ConvertTo-Json | Set-Content -Path $CfgPath -Encoding UTF8 } catch {} }

# ---------- 프로그램 자체 업데이트(파일 하나라서 받아서 바꾸고 다시 켬) ----------
function Self-Update {
  try {
    $rv = (Get-Text ($Raw + $Chan + 'LU4_KoreanPatch_version.txt')).Trim()
    if ($rv -notmatch '^\d{8}\.\d{4}$' -or $rv -le $Ver) { return }
    $new = Get-Text ($Raw + $Chan + 'LU4_KoreanPatch.ps1')
    if ($new.Length -lt 5000 -or $new -notmatch 'made by DoZ' -or $new -notmatch [regex]::Escape($rv)) { return }
    $new = $new.TrimStart([char]0xFEFF)
    # 숨김 파일은 바로 덮어쓸 수 없어서, 속성을 잠깐 풀고 쓴 뒤 다시 숨김
    $fi = Get-Item $PSCommandPath -Force; $oldAttr = $fi.Attributes; $fi.Attributes = 'Normal'
    try { [System.IO.File]::WriteAllText($PSCommandPath, $new, (New-Object System.Text.UTF8Encoding $true)) } finally { try { (Get-Item $PSCommandPath -Force).Attributes = $oldAttr } catch {} }
    Log ('프로그램 업데이트 ' + $Ver + ' -> ' + $rv)
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', ('"' + $PSCommandPath + '"')); if ($Watch) { $a += '-Watch' }; if ($Bc) { $a += '-Bc' }
    if ($script:Mutex) { try { $script:Mutex.ReleaseMutex() } catch {}; try { $script:Mutex.Dispose() } catch {} }
    Start-Process powershell -WindowStyle Hidden -ArgumentList $a
    [Environment]::Exit(0)
  } catch { Log ('업데이트 확인 실패: ' + $_.Exception.Message) }
}

# ---------- 게임 폴더 찾기 ----------
function Paks-Of($root) { return (Join-Path $root 'lu4\content\paks') }
function Valid-Root($root) { return ($root -and (Test-Path (Paks-Of $root))) }
function Root-From($p) {
  # 고른 폴더가 런처 폴더/게임 폴더/그 안쪽 어디든 게임 폴더(Liberta Ultimata 4)를 찾아 줌
  if (-not $p) { return $null }
  $d = $p
  for ($i = 0; $i -lt 6 -and $d; $i++) { if (Valid-Root $d) { return $d }; $d = Split-Path $d -Parent }
  $c = Join-Path $p 'Liberta Ultimata 4'; if (Valid-Root $c) { return $c }
  return $null
}
function Find-Game([switch]$Ask) {
  if (Valid-Root $cfg.game) { return $cfg.game }
  $found = $null
  # 1) 켜져 있는 게임/런처의 위치
  foreach ($pn in @('game', 'EGlobalLauncher')) {
    try { foreach ($p in $(if ($pn -eq 'game') { Game-Procs } else { @(Get-Process -Name $pn -ErrorAction SilentlyContinue) })) { $r = Root-From (Split-Path $p.Path -Parent); if ($r) { $found = $r; break } } } catch {}
    if ($found) { break }
  }
  # 2) 바탕화면/시작 메뉴 바로가기
  if (-not $found) {
    try {
      $sh = New-Object -ComObject WScript.Shell
      $dirs = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'), [Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('CommonPrograms'))
      foreach ($d in $dirs) {
        if (-not $d -or -not (Test-Path $d)) { continue }
        foreach ($l in @(Get-ChildItem $d -Filter *.lnk -Recurse -ErrorAction SilentlyContinue)) {
          try { $t = $sh.CreateShortcut($l.FullName).TargetPath; if ($t -match 'EGlobalLauncher|lu4') { $r = Root-From (Split-Path $t -Parent); if ($r) { $found = $r; break } } } catch {}
        }
        if ($found) { break }
      }
    } catch {}
  }
  # 3) 드라이브마다 흔한 위치
  if (-not $found) {
    foreach ($dr in @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady })) {
      $cands = @((Join-Path $dr.Name 'EGlobalLauncher'), (Join-Path $dr.Name 'Liberta Ultimata 4'))
      try { foreach ($t in @(Get-ChildItem $dr.Name -Directory -ErrorAction SilentlyContinue)) { $cands += (Join-Path $t.FullName 'EGlobalLauncher'); $cands += (Join-Path $t.FullName 'Liberta Ultimata 4') } } catch {}
      foreach ($c in $cands) { if (Test-Path $c) { $r = Root-From $c; if ($r) { $found = $r; break } } }
      if ($found) { break }
    }
  }
  # 4) 직접 고르기
  if (-not $found -and $Ask) {
    Msg "게임 폴더를 자동으로 찾지 못했어요.`n`n다음 창에서 게임이 설치된 폴더(EGlobalLauncher 폴더)를 골라 주세요." | Out-Null
    while (-not $found) {
      $fb = New-Object System.Windows.Forms.FolderBrowserDialog; $fb.Description = 'LU4 게임이 설치된 폴더(EGlobalLauncher)를 골라 주세요'; $fb.ShowNewFolderButton = $false
      if ($fb.ShowDialog() -ne 'OK') { return $null }
      $found = Root-From $fb.SelectedPath
      if (-not $found) { if ((Msg "이 폴더에서 게임을 찾지 못했어요. 다시 고를까요?`n`n(안에 'Liberta Ultimata 4' 폴더가 있는 EGlobalLauncher 폴더를 골라 주세요)" 'YesNo' 'Warning') -ne 'Yes') { return $null } }
    }
  }
  if ($found) { $cfg.game = $found; Save-Cfg; Log ('게임 폴더: ' + $found) }
  return $found
}
function Game-Ver($root) { try { $j = Get-Content (Join-Path $root 'UpdateVersion.json') -Raw -Encoding UTF8 | ConvertFrom-Json; return [int]$j.version } catch { return 0 } }   # 런처가 적어 두는 게임 버전
# 게임 프로세스: 이름이 lu4 로 시작(lu4, lu4-win64-shipping 등). 'LU4 채팅 번역'처럼 띄어쓰기가 있는 우리 프로그램은 제외
function Game-Procs { return @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(?i)lu4[\w.\-]*$' }) }
function Game-Running { return [bool](Game-Procs).Count }

# ---------- 패치 목록(manifest) / 설치 여부 ----------
function Get-Manifest {
  if ($Watch) { Set-PatchKind (Read-PatchKind) }
  $t = Get-Text ($Raw + $PDir + 'manifest.txt')
  $m = @{ ver = ''; game = 0; files = @() }   # game: 이 패치가 맞는 게임 버전
  foreach ($ln in ($t -split "`n")) {
    $ln = $ln.Trim()
    if ($ln -match '^ver=(.+)$') { $m.ver = $Matches[1] }
    elseif ($ln -match '^game=(\d+)$') { $m.game = [int]$Matches[1] }
    elseif ($ln -match '^file=([^|]+)\|(\d+)\|(\d+)\|([0-9A-Fa-f]{64})(?:\|(patch|patch_bc))?$') { $fd = $PDir; if ($Matches[5]) { $fd = $Matches[5] + '/' }; $m.files += @{ name = $Matches[1]; size = [int64]$Matches[2]; parts = [int]$Matches[3]; sha = $Matches[4].ToUpper(); dir = $fd } }
  }
  if (-not $m.files.Count) { throw '패치 목록을 읽지 못했어요.' }
  foreach ($f in $m.files) { if ($f.name -notmatch '^LU4-Korean[A-Za-z0-9_\-]*\.(pak|ucas|utoc)$') { throw '패치 목록이 이상해요.' } }
  $script:PG = $m.game
  return $m
}
$script:PG = 0
function Test-Installed($root, $m) {
  $pk = Paks-Of $root
  foreach ($f in $m.files) { $p = Join-Path $pk $f.name; if (-not (Test-Path $p) -or (Get-Item $p).Length -ne $f.size) { return $false } }
  return $true
}
function Has-AnyPatch($root) { try { return [bool]@(Get-ChildItem (Paks-Of $root) -Filter 'LU4-Korean*.pak' -ErrorAction SilentlyContinue).Count } catch { return $false } }
function Sha256($path) { $s = [System.IO.File]::OpenRead($path); try { $h = [System.Security.Cryptography.SHA256]::Create(); return ([BitConverter]::ToString($h.ComputeHash($s)) -replace '-', '') } finally { $s.Dispose() } }

# ---------- 진행 창 ----------
$script:pf = $null
function Show-Progress($text, $pct) {
  if (-not $script:pf) {
    $f = New-Object System.Windows.Forms.Form; $f.Text = $Title; $f.FormBorderStyle = 'FixedDialog'; $f.ControlBox = $false; $f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.ClientSize = New-Object System.Drawing.Size 420, 96
    try { $ic = Join-Path $PSScriptRoot 'LU4_KoreanPatch.ico'; if (Test-Path $ic) { $f.Icon = New-Object System.Drawing.Icon $ic } } catch {}
    $l = New-Object System.Windows.Forms.Label; $l.Location = New-Object System.Drawing.Point 16, 14; $l.Size = New-Object System.Drawing.Size 388, 36; $l.Font = New-Object System.Drawing.Font '맑은 고딕', 10
    $b = New-Object System.Windows.Forms.ProgressBar; $b.Location = New-Object System.Drawing.Point 16, 56; $b.Size = New-Object System.Drawing.Size 388, 20; $b.Maximum = 100
    $f.Controls.Add($l); $f.Controls.Add($b); $script:pf = $f; $script:pl = $l; $script:pb = $b; $f.Show()
  }
  $script:pl.Text = $text; $v = [int][Math]::Max(0, [Math]::Min(100, $pct)); $script:pb.Value = $v
  [System.Windows.Forms.Application]::DoEvents()
}
function Close-Progress { if ($script:pf) { $script:pf.Close(); $script:pf = $null } }

# ---------- 패치 받아서 넣기 ----------
function Install-Patch($root, $m) {
  $pk = Paks-Of $root
  if (-not (Test-Path $Cache)) { New-Item -ItemType Directory -Path $Cache -Force | Out-Null }
  $total = [int64]0; foreach ($f in $m.files) { $total += $f.size }
  $done = [int64]0
  foreach ($f in $m.files) {
    $cf = Join-Path $Cache $f.name
    $ok = (Test-Path $cf) -and ((Get-Item $cf).Length -eq $f.size) -and ((Sha256 $cf) -eq $f.sha)
    if (-not $ok) {
      if (Test-Path $cf) { Remove-Item $cf -Force }
      $tmp = $cf + '.tmp'; if (Test-Path $tmp) { Remove-Item $tmp -Force }
      $out = [System.IO.File]::Create($tmp)
      try {
        for ($i = 1; $i -le $f.parts; $i++) {
          $pp = $cf + ('.part{0:D2}' -f $i); if (Test-Path $pp) { Remove-Item $pp -Force }
          $wc = New-Object System.Net.WebClient
          try {
            $wc.DownloadFileAsync([Uri]($Raw + $f.dir + $f.name + ('.part{0:D2}' -f $i)), $pp)
            while ($wc.IsBusy) {
              $cur = [int64]0; try { if (Test-Path $pp) { $cur = (Get-Item $pp).Length } } catch {}
              $got = $done + $out.Length + $cur
              Show-Progress ('한글패치를 받는 중이에요...  ' + [int]($got / 1MB) + ' / ' + [int]($total / 1MB) + ' MB') (100.0 * $got / $total)
              Start-Sleep -Milliseconds 120
            }
          } finally { $wc.Dispose() }
          if (-not (Test-Path $pp) -or (Get-Item $pp).Length -le 0) { throw ('받기 실패: ' + $f.name + ' (' + $i + '/' + $f.parts + ') 인터넷 연결을 확인해 주세요.') }
          $in = [System.IO.File]::OpenRead($pp); try { $in.CopyTo($out) } finally { $in.Dispose() }
          Remove-Item $pp -Force
        }
      } finally { $out.Dispose() }
      if ((Get-Item $tmp).Length -ne $f.size -or (Sha256 $tmp) -ne $f.sha) { Remove-Item $tmp -Force; throw ('받은 파일이 올바르지 않아요: ' + $f.name + ' (다시 눌러 주세요)') }
      Move-Item $tmp $cf -Force
    }
    $done += $f.size
    Show-Progress '한글패치를 받는 중이에요...' (100.0 * $done / $total)
  }
  Show-Progress '게임 폴더에 넣는 중이에요...' 100
  # 예전 한글패치 파일(이름이 LU4-Korean… 인 것만) 정리 후 새 파일 넣기
  $names = @($m.files | ForEach-Object { $_.name })
  foreach ($old in @(Get-ChildItem $pk -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^LU4-Korean[A-Za-z0-9_\-]*\.(pak|ucas|utoc)$' -and ($names -notcontains $_.Name) })) { Remove-Item $old.FullName -Force; Log ('예전 패치 지움: ' + $old.Name) }
  foreach ($f in $m.files) {
    $to = Join-Path $pk $f.name; $tt = $to + '.tmp'
    Copy-Item (Join-Path $Cache $f.name) $tt -Force
    if (Test-Path $to) { Remove-Item $to -Force }
    Move-Item $tt $to -Force
  }
  $cfg.files = $names; Save-Cfg
  Log ('패치 넣음: ' + $m.ver + ' -> ' + $pk)
}

# ---------- 사용 현황 신호 ----------
function Get-Id {
  $idf = Join-Path $Data 'client_id.txt'; $id = ''
  if (Test-Path $idf) { $id = ([string](Get-Content $idf -TotalCount 1)).Trim() }
  if ($id -notmatch '^[a-f0-9]{32}$') { $id = [Guid]::NewGuid().ToString('N'); Set-Content -Path $idf -Value $id -Encoding ASCII }
  return $id
}
# 제작자가 이 PC를 차단했는지(서버에 못 물어보면 차단 아님으로 봄)
function Is-Blocked {
  try { $wc = New-Object System.Net.WebClient; try { return ($wc.DownloadString((($LiveUrl -replace '/ping$', '/check') + '?id=' + (Get-Id) + '&t=' + [DateTime]::UtcNow.Ticks)).Trim() -eq 'blocked') } finally { $wc.Dispose() } } catch { return $false }
}
function Send-Live($root) {
  try {
    $gv = $(if ($root) { Game-Ver $root } else { 0 })
    $id = Get-Id
    try { if (Get-Command Prune-Names -ErrorAction SilentlyContinue) { Prune-Names } } catch {}
    $nm = ''; try { $nf = Join-Path $Data 'char_name.txt'; if (Test-Path $nf) { $nm = ([string](Get-Content $nf -TotalCount 1 -Encoding UTF8)).Trim(); if ($nm -notmatch '^[A-Za-z0-9_]{2,24}$') { $nm = '' } } } catch {}
    $wc = New-Object System.Net.WebClient
    try { [void]$wc.DownloadString(($LiveUrl + '?id=' + $id + '&app=patch&v=' + $Ver + '&g=' + $gv + '&pg=' + [int]$script:PG + '&n=' + [Uri]::EscapeDataString($nm) + $(if (@($script:AllNames).Count -gt 1) { '&ns=' + [Uri]::EscapeDataString((@($script:AllNames | Select-Object -First 4) -join ',')) } else { '' }) + '&t=' + [DateTime]::UtcNow.Ticks)) } finally { $wc.Dispose() }
  } catch {}
}
# ---------- 캐릭터 이름 확인(사용 현황용): 채팅번역·사냥지표를 안 쓰는 PC에서, 게임 창 왼쪽 위 상태창의 이름을 읽음 ----------
$script:OcrEng = $null; $script:OcrKo = $null; $script:OcrTried = $false; $script:Clan = $null; $script:Own = @(); $script:NameSeen = @(); $script:TestSkipTop = $false; $script:NameTile = -1; $script:NameScan = 0; $script:NameDbg = ''
function Known-Name { try { $nf = Join-Path $Data 'char_name.txt'; if (Test-Path $nf) { $n = ([string](Get-Content $nf -TotalCount 1 -Encoding UTF8)).Trim(); if ($n -match '^[A-Za-z0-9_]{2,24}$') { return $n } } } catch {}; return '' }
function Init-Ocr {
  if ($script:OcrTried) { return }; $script:OcrTried = $true
  try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    Add-Type 'using System; using System.Runtime.InteropServices; public static class LU4K { [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; } [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L; public int T; public int R; public int B; } [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r); [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p); [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h); [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid); }'
    [void][LU4K]::SetProcessDPIAware()
    [void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
    [void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
    [void][Windows.Graphics.Imaging.SoftwareBitmap, Windows.Foundation, ContentType = WindowsRuntime]
    [void][Windows.Globalization.Language, Windows.Foundation, ContentType = WindowsRuntime]
    $script:AsTaskG = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
    $e = $null
    try { $e = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new('en-US')) } catch {}
    if (-not $e) { try { foreach ($lg in [Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages) { if ($lg.LanguageTag -like 'en*') { $e = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lg); if ($e) { break } } } } catch {} }
    if (-not $e) { $e = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
    $script:OcrEng = $e
    # 한글 글자 인식(있으면): 시스템 창의 "이름이(가) … 대미지" 줄을 읽는 데 씀
    try { $script:OcrKo = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new('ko')) } catch {}
    # 이 PC에서 접속했던 캐릭터 이름: 게임 저장 폴더의 PartyBuffs_<이름>.sav 파일 이름(내용은 읽지 않음). 최근에 쓴 것부터
    try { $script:Own = @(Get-ChildItem (Join-Path $env:LOCALAPPDATA 'LU4\Saved\SaveGames') -Filter 'PartyBuffs_*.sav' -File -ErrorAction Stop | Sort-Object LastWriteTime -Descending | ForEach-Object { $_.BaseName.Substring(11) } | Where-Object { $_ -match '^[A-Za-z0-9_]{3,24}$' }) } catch { $script:Own = @() }
    # 혈맹원 명단(있으면 이름을 훨씬 정확히 고름)
    try { $script:Clan = @((Get-Text ($Raw + 'clan_members.txt')) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') -and $_ -match '^[A-Za-z0-9_]{2,24}$' }) } catch { $script:Clan = @() }
    Log ('이름 읽기 준비: ' + $(if ($e) { '됨' } else { '글자 인식 없음' }) + ', 명단 ' + @($script:Clan).Count + '명, 이 PC 캐릭터 ' + @($script:Own).Count + '개' + $(if ($script:OcrKo) { ', 한글 인식 있음' } else { '' }))
  } catch { Log ('이름 읽기 준비 실패: ' + $_.Exception.Message) }
}
function Aw($op, [Type]$t) { $task = $script:AsTaskG.MakeGenericMethod($t).Invoke($null, @($op)); [void]$task.Wait(15000); $task.Result }
# 그림을 글자 인식해서 줄 목록으로
function Ocr-Lines($bmp, $eng) {
  $ms = New-Object System.IO.MemoryStream; $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $ms.Position = 0
  try {
    $ras = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($ms)
    $dec = Aw ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($ras)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $sb = Aw ($dec.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $res = Aw ($eng.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
    return @($res.Lines | ForEach-Object { [string]$_.Text })
  } finally { $ms.Dispose() }
}
function Read-Name {
  # 반환: @(이름, 확실한지, 어떻게 알았는지, 믿을 만한 정도 0~2)   2 = 두 곳이 같거나, 시스템 창에 5번 이상, 또는 상태창에서 이 PC 캐릭터 이름
  # 두 군데를 읽어서 맞춰 봄: 1) 화면 왼쪽 위 상태창의 이름 줄  2) 시스템 창의 사냥 줄에 여러 번 나오는 내 이름
  # 둘이 같으면 바로 확정. 하나만 읽히거나 서로 다르면 더 믿을 만한 쪽을 후보로(같은 이름이 다시 읽혀야 확정)
  Init-Ocr; if (-not $script:OcrEng) { return $null }
  $h = [LU4K]::GetForegroundWindow(); if ($h -eq [IntPtr]::Zero -or [LU4K]::IsIconic($h)) { return $null }
  $procId = [uint32]0; [void][LU4K]::GetWindowThreadProcessId($h, [ref]$procId)
  try { if ((Get-Process -Id $procId -ErrorAction Stop).ProcessName -notmatch '^(?i)lu4[\w.\-]*$') { return $null } } catch { return $null }
  $script:NamePid = [int]$procId
  $cr = New-Object LU4K+RECT; [void][LU4K]::GetClientRect($h, [ref]$cr); $p = New-Object LU4K+POINT; [void][LU4K]::ClientToScreen($h, [ref]$p)
  if ($cr.R -lt 200 -or $cr.B -lt 150) { return $null }
  $fold = { param($x) (($x -replace '[^A-Za-z0-9_]', '').ToLower() -replace '[il1|]', 'l' -replace '0', 'o') }
  $ownK = @{}; foreach ($c in @($script:Own)) { $k = & $fold $c; if ($k.Length -ge 3 -and -not $ownK.ContainsKey($k)) { $ownK[$k] = $c } }
  $sureK = @{}; foreach ($c in @($script:Clan)) { $k = & $fold $c; if ($k.Length -ge 3) { $sureK[$k] = $c } }
  foreach ($k in $ownK.Keys) { $sureK[$k] = $ownK[$k] }   # 이 PC 캐릭터 이름이 명단보다 먼저
  $script:NameDbg = ''
  $a = $null; $aKind = ''; $cand = $null   # aKind: own(이 PC 캐릭터) / clan(명단) / guess(글자 모양으로 짐작)
  if (-not $script:TestSkipTop) {
    $w = [int]($cr.R * 0.25); $hh = [int]($cr.B * 0.06)
    $bmp = New-Object System.Drawing.Bitmap $w, $hh
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($p.X, $p.Y, 0, 0, $bmp.Size); $g.Dispose()
    try {
      # 이름 줄만 좁게 자르면 잘 읽힘(게임 창의 가로 20%·세로 4%). 안 읽히면 더 좁게, 색을 뒤집어서, 마지막으로 예전 범위로
      foreach ($v in @(@(0.20, 0.04, $false), @(0.15, 0.03, $false), @(0.20, 0.04, $true), @(0.25, 0.06, $true))) {
        $cw = [Math]::Min($w, [int]($cr.R * $v[0])); $ch = [Math]::Min($hh, [int]($cr.B * $v[1])); if ($cw -lt 20 -or $ch -lt 8) { continue }
        $sc = [Math]::Max(1.0, [Math]::Min(4.0, 2400.0 / [Math]::Max($cw, $ch)))
        $big = New-Object System.Drawing.Bitmap ([int]($cw * $sc)), ([int]($ch * $sc))
        $g = [System.Drawing.Graphics]::FromImage($big); $g.InterpolationMode = 'HighQualityBicubic'
        $dst = New-Object System.Drawing.Rectangle 0, 0, $big.Width, $big.Height
        if ($v[2]) {
          # 흑백으로 바꾸고 뒤집음 (밝은 글자 -> 흰 바탕의 검은 글자)
          $cm = New-Object System.Drawing.Imaging.ColorMatrix
          $mx = @(@(-0.45, -0.45, -0.45, 0, 0), @(-0.9, -0.9, -0.9, 0, 0), @(-0.15, -0.15, -0.15, 0, 0), @(0, 0, 0, 1, 0), @(1.25, 1.25, 1.25, 0, 1))
          for ($i = 0; $i -lt 5; $i++) { for ($j = 0; $j -lt 5; $j++) { $cm[$i, $j] = [single]$mx[$i][$j] } }
          $ia = New-Object System.Drawing.Imaging.ImageAttributes; $ia.SetColorMatrix($cm)
          $g.DrawImage($bmp, $dst, 0, 0, $cw, $ch, [System.Drawing.GraphicsUnit]::Pixel, $ia); $ia.Dispose()
        } else { $g.DrawImage($bmp, $dst, 0, 0, $cw, $ch, [System.Drawing.GraphicsUnit]::Pixel) }
        $g.Dispose()
        $lines = @(); try { $lines = Ocr-Lines $big $script:OcrEng } finally { $big.Dispose() }
        foreach ($ln in $lines) { foreach ($wd in ($ln -split '\s+')) { $k = & $fold $wd; if (-not $a -and $k.Length -ge 3 -and $sureK.ContainsKey($k)) { $a = $sureK[$k]; $aKind = $(if ($ownK.ContainsKey($k)) { 'own' } else { 'clan' }) } } }
        if ($a) { break }
        if ($cand) { continue }
        foreach ($ln in $lines) {
          $t = ($ln -replace '[\[\]\(\)|]', '').Trim()
          if ($t.Length -lt 3 -or $t.Length -gt 16 -or $t -match '\s' -or $t -match '[/%:.,+]' -or $t -match '^(?i)(HP|MP|CP|Lv|EXP|SP)\d*$') { continue }
          $lt = ([regex]::Matches($t, '[A-Za-z]')).Count
          if ($lt -ge 3 -and $lt -ge ([double]$t.Length) / 2) { $nm = ($t -replace '[^A-Za-z0-9_]', ''); if ($nm.Length -ge 3) { $cand = $nm; break } }
        }
      }
    } finally { $bmp.Dispose() }
    if (-not $a -and $cand) { $a = $cand; $aKind = 'guess' }
  }
  # 2) 화면 전체: 9칸으로 나눠 크게 키워서 읽음(통째로 읽으면 글자가 작아 안 읽힘)
  #    시스템 창의 사냥 줄에는 내 이름이 한 낱말로 여러 번 나옴 -> 혼자 한 줄로 읽힌 영문 낱말 중 3번 이상 나온 것
  #    지난번에 찾은 칸 먼저, 그다음 왼쪽 세 칸(기본 위치). 나머지 칸은 6번에 한 번만
  $b = $null; $bKind = ''; $bN = 0; $bOnly = $false   # bKind: own(이 PC 캐릭터 이름이 화면에 보임) / sys(시스템 창의 사냥 줄)
  $full = New-Object System.Drawing.Bitmap ([int]$cr.R), ([int]$cr.B)
  $g = [System.Drawing.Graphics]::FromImage($full); $g.CopyFromScreen($p.X, $p.Y, 0, 0, $full.Size); $g.Dispose()
  try {
    $script:NameScan++
    $order = @(0, 3, 6); if ($script:NameTile -ge 0) { $order = @($script:NameTile) + @($order | Where-Object { $_ -ne $script:NameTile }) }
    # 시스템 창을 오른쪽 등 다른 곳으로 옮긴 사람: 아직 어느 칸인지 모르면 두 번에 한 번은 나머지 칸도 모두 읽음(찾은 뒤에는 6번에 한 번)
    $allTiles = ($script:NameScan % 6 -eq 1) -or ($script:NameTile -lt 0 -and $script:NameScan % 2 -eq 1)
    if ($allTiles) { $order += @(1, 4, 7, 2, 5, 8 | Where-Object { $order -notcontains $_ }) }
    $tw = [int]($cr.R * 0.38); $th = [int]($cr.B * 0.38); $sc = [Math]::Max(1.0, [Math]::Min(3.0, 2600.0 / $tw))
    foreach ($ti in $order) {
      $rx = $ti % 3; $ry = [int][Math]::Floor($ti / 3)
      $x0 = [int][Math]::Min($cr.R - $tw, [Math]::Max(0, $cr.R * (0.31 * $rx))); $y0 = [int][Math]::Min($cr.B - $th, [Math]::Max(0, $cr.B * (0.31 * $ry)))
      $big = New-Object System.Drawing.Bitmap ([int]($tw * $sc)), ([int]($th * $sc)); $g = [System.Drawing.Graphics]::FromImage($big); $g.InterpolationMode = 'HighQualityBicubic'
      $g.DrawImage($full, (New-Object System.Drawing.Rectangle 0, 0, $big.Width, $big.Height), $x0, $y0, $tw, $th, [System.Drawing.GraphicsUnit]::Pixel); $g.Dispose()
      $lines = @(); try { $lines = Ocr-Lines $big $script:OcrEng } finally { $big.Dispose() }
      $cnt = @{}; $raw = @{}
      foreach ($ln in $lines) {
        $t = $ln.Trim()
        if ($t -notmatch '^[A-Za-z][A-Za-z0-9_]{2,15}$' -or $t -match '^(?i)(HP|MP|CP|EXP|SP|Lv|DeepL|Chain|Compact|Always|Off)$') { continue }
        $k = & $fold $t; $cnt[$k] = 1 + [int]$cnt[$k]; if (-not $raw.ContainsKey($k)) { $raw[$k] = @() }; $raw[$k] += $t
      }
      if (-not $cnt.Count) { $script:NameDbg += ' 칸' + $ti + ':없음'; continue }
      $rank = @($cnt.GetEnumerator() | Sort-Object Value -Descending); $best = $rank[0]
      $script:NameDbg += ' 칸' + $ti + ':' + (@($rank | Select-Object -First 3 | ForEach-Object { [string]$raw[$_.Key][0] + 'x' + $_.Value }) -join ',')
      if ($best.Value -lt 3 -or ($rank.Count -gt 1 -and $rank[1].Value * 2 -gt $best.Value)) { continue }
      $bN = [int]$best.Value; $bOnly = $true; $script:NameTile = $ti
      if ($sureK.ContainsKey($best.Key)) { $b = $sureK[$best.Key]; $bKind = $(if ($ownK.ContainsKey($best.Key)) { 'own' } else { 'sys' }) }
      else { $b = [string](@($raw[$best.Key] | Group-Object -CaseSensitive | Sort-Object Count -Descending)[0].Name); $bKind = 'sys' }
      break
    }
  } finally { $full.Dispose() }
  # 이 게임 창에서 화면 전체(9칸)를 다 읽고도 시스템 창 이름을 못 찾은 횟수
  if ($allTiles -and -not $b) { $script:NameFullMiss[[string]$procId] = 1 + [int]$script:NameFullMiss[[string]$procId] }
  $script:NameDbg = '상태창=' + $(if ($a) { $a + '(' + $aKind + ')' } else { '없음' }) + ' /' + $script:NameDbg
  # 3) 두 결과를 맞춰 봄
  $nmA = @{ own = '상태창(이 PC 캐릭터)'; clan = '상태창(명단)'; guess = '상태창' }; $nmB = @{ own = '시스템 창(이 PC 캐릭터)'; sys = '시스템 창 사냥 줄' }
  if ($a -and $b) {
    if ((& $fold $a) -eq (& $fold $b)) { return @($(if ($aKind -eq 'guess' -and $bKind -eq 'own') { $b } else { $a }), $true, ($nmA[$aKind] + ' = ' + $nmB[$bKind]), 2) }
    if ($aKind -eq 'own') { return @($a, $true, ($nmA[$aKind] + ' (화면 쪽은 ' + $b + ')'), 2) }
    return @($b, ($bN -ge 5), ($nmB[$bKind] + ' ' + $bN + '번 (상태창 쪽은 ' + $a + ')'), $(if ($bN -ge 5) { 2 } else { 0 }))
  }
  # 왼쪽 위에서 글자 모양만 보고 짐작한 이름은, 화면 전체를 두 번 훑고도 시스템 창에서 이름을 못 찾았을 때만 후보로 씀
  # (상태창을 옮겼거나 가린 사람은 왼쪽 위에 다른 글자가 있어 틀린 이름이 먼저 올라가던 것 방지)
  if ($a -and $aKind -eq 'guess' -and [int]$script:NameFullMiss[[string]$procId] -lt 2) { $script:NameDbg += ' / 짐작 이름 보류'; return $null }
  if ($a) { return @($a, ($aKind -ne 'guess'), $nmA[$aKind], $(if ($aKind -eq 'own') { 2 } elseif ($aKind -eq 'clan') { 1 } else { 0 })) }
  # 상태창을 못 읽어도, 시스템 창에 같은 이름이 5번 이상 나오면 그것만으로 바로 확정
  if ($b) { return @($b, ($bN -ge 5), ($nmB[$bKind] + ' ' + $bN + '번'), $(if ($bN -ge 5) { 2 } else { 0 })) }
  return $null
}
# 게임 창마다(프로세스 번호별로) 이름을 따로 기억함: 게임을 다시 켜면 새 창이라 다시 확인하고, 창을 두 개 켜면 둘 다 알 수 있음
$script:NamePid = 0; $script:NameFullMiss = @{}; $script:WinName = @{}; $script:WinCand = @{}; $script:WinTick = @{}; $script:AllNames = @()
function Game-WinPids { return @(Game-Procs | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | ForEach-Object { [string]$_.Id }) }
# 맨 앞 창이 게임이면 그 프로세스 번호, 아니면 0
function Fg-GamePid {
  try {
    Init-Ocr; if (-not $script:OcrEng) { return 0 }
    $h = [LU4K]::GetForegroundWindow(); if ($h -eq [IntPtr]::Zero -or [LU4K]::IsIconic($h)) { return 0 }
    $fp = [uint32]0; [void][LU4K]::GetWindowThreadProcessId($h, [ref]$fp)
    if ((Get-Process -Id $fp -ErrorAction Stop).ProcessName -match '^(?i)lu4[\w.\-]*$') { return [int]$fp }
  } catch {}
  return 0
}
# 이름을 아직 모르는 게임 창이 있는지(있으면 처음 10분은 5초마다 읽어 봄)
function Need-Name { try { foreach ($k in (Game-WinPids)) { if (-not $script:WinName.ContainsKey($k)) { return $true } } } catch {}; return $false }
# 확정된 이름을 저장하고 알림: char_name.txt = 지금 맨 앞 창의 이름, 모든 창의 이름은 함께 보냄
function Publish-Name($root, $key, $nm, $src, $why) {
  $script:WinName[$key] = $nm; [void]$script:WinCand.Remove($key)
  Set-Content -Path (Join-Path $Data 'char_name.txt') -Value @($nm, $src) -Encoding UTF8
  Prune-Names
  Log ($why + $(if ($script:AllNames.Count -gt 1) { ' / 켜 둔 캐릭터: ' + ($script:AllNames -join ', ') } else { '' }))
  Send-Live $root
}
# 꺼진 게임 창의 이름은 지움
function Prune-Names {
  try {
    $live = @(Game-WinPids)
    foreach ($k in @($script:WinName.Keys)) { if ($live -notcontains $k) { [void]$script:WinName.Remove($k); [void]$script:WinTick.Remove($k); [void]$script:WinCand.Remove($k) } }
    $first = Known-Name; $vals = @($script:WinName.Values)
    # 저장된 이름(char_name.txt)이 방금 끈 창의 캐릭터면, 아직 켜져 있는 창의 이름으로 바꿔 둠
    if ($vals.Count -and $vals -cnotcontains $first) {
      $first = [string]$vals[0]
      Set-Content -Path (Join-Path $Data 'char_name.txt') -Value @($first, 'sure') -Encoding UTF8
      Log ('끈 창의 이름을 지움 -> 남은 캐릭터: ' + ($vals -join ', '))
    }
    $script:AllNames = @(@($vals | Where-Object { $_ -ceq $first }) + @($vals | Where-Object { $_ -cne $first }) | Select-Object -Unique)
  } catch {}
}
function Try-Name($root) {
  try {
    $fp = Fg-GamePid; if (-not $fp) { return }
    $key = [string]$fp
    $fk = { param($x) ((([string]$x) -replace '[^A-Za-z0-9_]', '').ToLower() -replace '[il1|]', 'l' -replace '0', 'o') }
    $known = [string]$script:WinName[$key]
    if ($known) {
      # 이 창의 이름을 이미 아는 경우: 게임 안에서 다른 캐릭터로 바꿨는지 2분에 한 번 확인
      # 믿을 만하게(두 곳이 같거나 시스템 창에 5번 이상) 다른 이름이 두 번 이어서 읽히면 그 이름으로 바꿈
      $script:WinTick[$key] = 1 + [int]$script:WinTick[$key]; if ($script:WinTick[$key] % 4 -ne 0) { return }
      $r = Read-Name; if (-not $r -or -not $r[0] -or $script:NamePid -ne $fp) { return }
      if ((& $fk $r[0]) -eq (& $fk $known)) { [void]$script:WinCand.Remove($key); return }
      if ([int]$r[3] -lt 2) { return }
      $c = $script:WinCand[$key]
      if ($c -and (& $fk $c.c) -eq (& $fk $r[0])) { $c.n++ } else { $c = @{ c = [string]$r[0]; n = 1; seen = @() }; $script:WinCand[$key] = $c }
      if ($c.n -lt 2) { return }
      Publish-Name $root $key ([string]$r[0]) 'sure' ('캐릭터 바뀜: ' + $known + ' -> ' + [string]$r[0] + ' / ' + [string]$r[2])
      return
    }
    # 이 창의 이름을 아직 모름(게임을 새로 켰거나, 두 번째 창)
    $r = Read-Name; if (-not $r -or -not $r[0] -or $script:NamePid -ne $fp) { return }
    $nm = [string]$r[0]; $hint = Known-Name
    $used = @($script:WinName.Values | ForEach-Object { & $fk $_ })   # 다른 창이 이미 쓰는 이름
    if ($hint -and (& $fk $nm) -eq (& $fk $hint) -and $used -notcontains (& $fk $hint)) {
      # 지난번에 저장된 이름과 같음 -> 바로 확정(저장된 표기 그대로)
      Publish-Name $root $key $hint 'sure' ('이름 확인: ' + $hint + ' / 지난번과 같음, ' + [string]$r[2]); return
    }
    if (-not $r[1]) {
      # 확실하지 않으면: 이 창에서 최근 6번 읽은 것 중 같은 이름(대소문자 무시)이 2번 나오면 확정. 대소문자는 더 많이 읽힌 쪽으로
      $c = $script:WinCand[$key]; if (-not $c) { $c = @{ c = ''; n = 0; seen = @() }; $script:WinCand[$key] = $c }
      $c.seen = @(@($c.seen) + $nm | Select-Object -Last 6)
      $same = @($c.seen | Where-Object { $_ -ieq $nm }); if ($same.Count -lt 2) { return }
      $nm = [string](@($same | Group-Object -CaseSensitive | Sort-Object Count -Descending)[0].Name)
    }
    Publish-Name $root $key $nm $(if ($r[1]) { 'sure' } else { 'ocr' }) ('이름 확인: ' + $nm + ' / ' + [string]$r[2] + $(if ($r[1]) { '' } else { ' (두 번 읽힘)' }))
  } catch { Log ('이름 읽기 오류: ' + $_.Exception.Message) }
}
function Start-Watcher {
  # 뒤에서 기다리는 모드가 꺼져 있으면 켬
  try {
    $w = Join-Path $PSScriptRoot 'LU4_KoreanPatch_watch.vbs'; $ws = Join-Path $env:WINDIR 'System32\wscript.exe'
    if ((Test-Path $w) -and (Test-Path $ws)) { Start-Process -FilePath $ws -ArgumentList ('"' + $w + '"') -WorkingDirectory $PSScriptRoot }
    else { Start-Process powershell -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', ('"' + $PSCommandPath + '"'), '-Watch') }
  } catch {}
}

# =====================================================================
# 뒤에서 기다리는 모드: 30초마다(이름을 모르는 처음 10분은 5초마다) 게임이 켜졌는지만 확인. 게임 중일 때만 신호(5분마다)
# =====================================================================
if ($Watch) {
  $created = $false
  $script:Mutex = New-Object System.Threading.Mutex($true, 'LU4_KoreanPatch_Watch', [ref]$created)
  if (-not $created) { exit }
  Log ('기다리기 시작 ' + $Ver)
  Self-Update
  $was = $false; $lastPing = [DateTime]::MinValue; $lastUpd = [DateTime]::Now; $nameTries = 0; $winN = 0
  trap { Log ('기다리기 중단: ' + $_.Exception.Message); break }
  $myTime = (Get-Item $PSCommandPath -Force).LastWriteTimeUtc
  while ($true) {
    try {
      # 프로그램 파일이 새로 바뀌었으면(아이콘을 눌러 업데이트된 경우) 새 버전으로 다시 켬
      if ((Get-Item $PSCommandPath -Force).LastWriteTimeUtc -ne $myTime) {
        Log '프로그램이 바뀌어서 다시 켬'; try { $script:Mutex.ReleaseMutex() } catch {}; try { $script:Mutex.Dispose() } catch {}
        Start-Process powershell -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', ('"' + $PSCommandPath + '"'), '-Watch'); [Environment]::Exit(0)
      }
      if (Game-Running) {
        $root = Find-Game
        if (-not $was) {
          $was = $true; $nameTries = 0; $lastPing = [DateTime]::MinValue; Log ('게임 켜짐: ' + ((Game-Procs | ForEach-Object { $_.ProcessName }) -join ', '))
          # 게임이 켜졌는데 한글패치가 없으면(런처 파일 확인으로 지워진 경우) 알려 줌
          if ($root) {
            $missing = $false
            try { $missing = -not (Test-Installed $root (Get-Manifest)) } catch { $missing = -not (Has-AnyPatch $root) }
            if ($missing -and -not (Is-Blocked)) { Log '게임 켜짐: 패치 없음'; Msg "한글패치가 없거나 새 패치가 나왔어요.`n(런처에서 파일 확인을 하면 지워져요)`n`n게임을 끄고 바탕화면의 'LU4 한글패치' 아이콘을 누르면 다시 넣어 줘요." 'OK' 'Warning' | Out-Null }
          }
        }
        if ($root -and (Has-AnyPatch $root)) { Try-Name $root }   # 이름을 아직 모르면 상태창에서 읽어 봄
        # 시험 기록: name_debug.txt 가 있으면(만든 사람만 해당) 읽은 결과를 저장하지 않고 기록만 남김
        $ndf = Join-Path $Data 'name_debug.txt'
        if ((Test-Path $ndf) -and ([string](Get-Content $ndf -TotalCount 1)).Trim() -eq 'on') { try { $tr = Read-Name; Log ('이름 시험: ' + $(if ($tr) { [string]$tr[0] + $(if ($tr[1]) { ' [바로 확정]' } else { ' [후보]' }) + ' <- ' + [string]$tr[2] } else { '못 읽음' }) + ' | ' + $script:NameDbg) } catch { Log ('이름 시험 오류: ' + $_.Exception.Message) } }
        # 한글패치가 들어 있는 사람만 집계
        # 켜 둔 게임 창 수가 바뀌면(하나를 껐거나 더 켰으면) 바로 다시 알림
        $wn = 0; try { $wn = @(Game-WinPids).Count } catch {}
        if ($wn -ne $winN) { $winN = $wn; $lastPing = [DateTime]::MinValue }
        if ($root -and (Has-AnyPatch $root) -and ([DateTime]::Now - $lastPing).TotalSeconds -ge 300) { Send-Live $root; $lastPing = [DateTime]::Now }
      } else {
        $was = $false
        if (([DateTime]::Now - $lastUpd).TotalHours -ge 3) { $lastUpd = [DateTime]::Now; Self-Update }
      }
    } catch { Log ('기다리기 오류: ' + $_.Exception.Message) }
    # 게임이 켜져 있고 이름을 아직 모르면 처음 10분은 5초마다 읽어 봄. 그 밖에는 30초마다
    $fast = $false; try { $fast = $was -and $nameTries -lt 120 -and (Need-Name) } catch {}
    if ($fast) { $nameTries++; Start-Sleep -Seconds 5 } else { Start-Sleep -Seconds 30 }
  }
}

# =====================================================================
# 아이콘을 눌렀을 때: 확인 -> (없으면) 넣기 -> 런처 켜기
# =====================================================================
try {
  Self-Update
  if (Is-Blocked) { Log '차단된 PC'; Msg '이 PC에서는 한글패치를 사용할 수 없어요.' 'OK' 'Warning' | Out-Null; exit }
  $root = Find-Game -Ask
  if (-not $root) { Msg '게임 폴더를 찾지 못해서 끝낼게요.' 'OK' 'Warning' | Out-Null; exit }
  $man = $null; $note = ''
  try { $man = Get-Manifest } catch { Log ('패치 목록 받기 실패: ' + $_.Exception.Message) }
  if (-not $man) {
    if (Has-AnyPatch $root) { $note = '한글패치가 들어 있어요. (인터넷 연결이 안 돼서 최신인지는 확인 못 했어요)' }
    else { Msg "한글패치가 없는데, 인터넷 연결이 안 돼서 받지 못했어요.`n연결을 확인하고 다시 눌러 주세요." 'OK' 'Warning' | Out-Null; exit }
  } elseif (Test-Installed $root $man) { $note = '한글패치가 들어 있어요.' }
  else {
    if (Game-Running) { Msg "게임이 켜져 있어요.`n게임을 끄고 다시 눌러 주세요. (켜져 있을 때는 패치를 넣을 수 없어요)" 'OK' 'Warning' | Out-Null; exit }
    # 게임이 업데이트돼서 올려 둔 패치와 게임 버전이 다르면 먼저 물어봄
    $gv = Game-Ver $root; $go = $true
    if ($man.game -gt 0 -and $gv -gt 0 -and $gv -ne $man.game) {
      Log ('게임 버전 ' + $gv + ' / 패치는 ' + $man.game + '용')
      $go = ((Msg "게임이 업데이트됐어요. 새 한글패치 작업 진행 중 입니다.`n그래도 예전 패치를 넣을까요?`n`n혹시 에러가 뜬다면 게임런처의 [파일확인] 누르시고 초기화하세요" 'YesNo' 'Warning') -eq 'Yes')
    }
    if ($go) { try { Install-Patch $root $man } finally { Close-Progress }; $note = '한글패치를 넣었어요.' }
    else { $note = '한글패치를 넣지 않았어요. (새 패치 작업 중)' }
  }
  Start-Watcher
  Send-Live $root
  # 런처 켜기(게임/런처가 이미 켜져 있으면 그대로 둠)
  $lch = Join-Path (Split-Path $root -Parent) 'EGlobalLauncher.exe'
  $started = $false
  if (-not (Game-Running) -and -not @(Get-Process -Name 'EGlobalLauncher' -ErrorAction SilentlyContinue).Count -and (Test-Path $lch)) { Start-Process -FilePath $lch -WorkingDirectory (Split-Path $lch -Parent); $started = $true }
  # 잠깐 보였다 사라지는 안내
  $t = New-Object System.Windows.Forms.Form; $t.FormBorderStyle = 'None'; $t.StartPosition = 'CenterScreen'; $t.TopMost = $true; $t.ShowInTaskbar = $false; $t.BackColor = [System.Drawing.Color]::FromArgb(28, 30, 36); $t.ClientSize = New-Object System.Drawing.Size 380, 74
  $l = New-Object System.Windows.Forms.Label; $l.Dock = 'Fill'; $l.TextAlign = 'MiddleCenter'; $l.ForeColor = [System.Drawing.Color]::White; $l.Font = New-Object System.Drawing.Font '맑은 고딕', 11
  $l.Text = $note + $(if ($started) { "`n게임 런처를 켜요." } else { '' }); $t.Controls.Add($l)
  $tm = New-Object System.Windows.Forms.Timer; $tm.Interval = 2500; $tm.Add_Tick({ $tm.Stop(); $t.Close() }); $tm.Start()
  [System.Windows.Forms.Application]::Run($t)
} catch {
  Close-Progress
  Log ('오류: ' + $_.Exception.Message)
  $m = $_.Exception.Message
  if ($m -match 'denied|거부|UnauthorizedAccess') { $m += "`n`n게임 폴더에 쓸 권한이 없어요. 게임과 런처를 모두 끄고 다시 눌러 주세요." }
  Msg ("문제가 생겼어요:`n" + $m) 'OK' 'Error' | Out-Null
}
