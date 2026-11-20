# made by DoZ
# LU4 한글패치: 게임 폴더에 한글패치가 있는지 확인하고, 없으면(런처 파일 확인으로 지워졌으면) 다시 넣은 뒤 런처를 켬
#  -Watch : 윈도우 시작 때 뒤에서 켜 두는 모드. LU4 게임이 실행 중일 때만 사용 현황 신호를 보내고, 패치가 지워졌으면 알려 줌
param([switch]$Watch)
$Ver = '20261120.1347'
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
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', ('"' + $PSCommandPath + '"')); if ($Watch) { $a += '-Watch' }
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
  $t = Get-Text ($Raw + 'patch/manifest.txt')
  $m = @{ ver = ''; game = 0; files = @() }   # game: 이 패치가 맞는 게임 버전
  foreach ($ln in ($t -split "`n")) {
    $ln = $ln.Trim()
    if ($ln -match '^ver=(.+)$') { $m.ver = $Matches[1] }
    elseif ($ln -match '^game=(\d+)$') { $m.game = [int]$Matches[1] }
    elseif ($ln -match '^file=([^|]+)\|(\d+)\|(\d+)\|([0-9A-Fa-f]{64})$') { $m.files += @{ name = $Matches[1]; size = [int64]$Matches[2]; parts = [int]$Matches[3]; sha = $Matches[4].ToUpper() } }
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
            $wc.DownloadFileAsync([Uri]($Raw + 'patch/' + $f.name + ('.part{0:D2}' -f $i)), $pp)
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
    $nm = ''; try { $nf = Join-Path $Data 'char_name.txt'; if (Test-Path $nf) { $nm = ([string](Get-Content $nf -TotalCount 1 -Encoding UTF8)).Trim(); if ($nm -notmatch '^[A-Za-z0-9_가-힣]{2,24}$') { $nm = '' } } } catch {}
    $wc = New-Object System.Net.WebClient
    try { [void]$wc.DownloadString(($LiveUrl + '?id=' + $id + '&app=patch&v=' + $Ver + '&g=' + $gv + '&pg=' + [int]$script:PG + '&n=' + [Uri]::EscapeDataString($nm) + '&t=' + [DateTime]::UtcNow.Ticks)) } finally { $wc.Dispose() }
  } catch {}
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
# 뒤에서 기다리는 모드: 30초마다 게임이 켜졌는지만 확인. 게임 중일 때만 신호(5분마다)
# =====================================================================
if ($Watch) {
  $created = $false
  $script:Mutex = New-Object System.Threading.Mutex($true, 'LU4_KoreanPatch_Watch', [ref]$created)
  if (-not $created) { exit }
  Log ('기다리기 시작 ' + $Ver)
  Self-Update
  $was = $false; $lastPing = [DateTime]::MinValue; $lastUpd = [DateTime]::Now
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
          $was = $true; $lastPing = [DateTime]::MinValue; Log ('게임 켜짐: ' + ((Game-Procs | ForEach-Object { $_.ProcessName }) -join ', '))
          # 게임이 켜졌는데 한글패치가 없으면(런처 파일 확인으로 지워진 경우) 알려 줌
          if ($root) {
            $missing = $false
            try { $missing = -not (Test-Installed $root (Get-Manifest)) } catch { $missing = -not (Has-AnyPatch $root) }
            if ($missing -and -not (Is-Blocked)) { Log '게임 켜짐: 패치 없음'; Msg "한글패치가 없거나 새 패치가 나왔어요.`n(런처에서 파일 확인을 하면 지워져요)`n`n게임을 끄고 바탕화면의 'LU4 한글패치' 아이콘을 누르면 다시 넣어 줘요." 'OK' 'Warning' | Out-Null }
          }
        }
        # 한글패치가 들어 있는 사람만 집계
        if ($root -and (Has-AnyPatch $root) -and ([DateTime]::Now - $lastPing).TotalSeconds -ge 300) { Send-Live $root; $lastPing = [DateTime]::Now }
      } else {
        $was = $false
        if (([DateTime]::Now - $lastUpd).TotalHours -ge 3) { $lastUpd = [DateTime]::Now; Self-Update }
      }
    } catch { Log ('기다리기 오류: ' + $_.Exception.Message) }
    Start-Sleep -Seconds 30
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
