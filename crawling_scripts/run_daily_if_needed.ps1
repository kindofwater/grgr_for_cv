$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot
$Root = Resolve-Path -LiteralPath (Join-Path $ScriptDir '..')
$LogFile = Join-Path $ScriptDir 'daily_log.txt'
$SuccessMarker = Join-Path $ScriptDir 'daily_success_date.txt'
$Today = Get-Date -Format 'yyyy-MM-dd'

# 절전 복귀 이벤트로 작업이 뜨면 노트북이 몇 초 뒤 다시 잠드는 일이 잦다(2026-10-04·05:
# 시작 12~40초 뒤 재잠듦 → 깨어났을 때 네트워크가 없어 SSO·DNS 실패). KUPID 연결이
# 이 시간 동안 살아 있어야 파이프라인을 띄운다.
$SettleSeconds = 60

function Write-GuardLog {
  param([string]$Message)
  $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Add-Content -LiteralPath $LogFile -Encoding utf8 -Value "[guard] $stamp $Message"
}

function Test-SuccessToday {
  if (Test-Path -LiteralPath $SuccessMarker) {
    $lastSuccess = (Get-Content -LiteralPath $SuccessMarker -TotalCount 1 -ErrorAction SilentlyContinue).Trim()
    if ($lastSuccess -eq $Today) {
      return $true
    }
  }

  if (Test-Path -LiteralPath $LogFile) {
    $okLine = Select-String -LiteralPath $LogFile -SimpleMatch "[OK] daily pipeline done $Today" -Quiet
    if ($okLine) {
      Set-Content -LiteralPath $SuccessMarker -Encoding ascii -Value $Today
      return $true
    }
  }

  return $false
}

function Test-KupidReachable {
  [System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable() -and
    (Test-NetConnection -ComputerName 'portal.korea.ac.kr' -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue)
}

function Test-NetworkSettled {
  # 'settled'     : 두 번 다 응답 — 실행해도 된다
  # 'unstable'    : 처음엔 됐는데 기다리는 동안 끊김 — 재잠듦으로 보고 건너뛴다
  # 'unreachable' : 처음부터 안 됨 — 기다리지 않고 건너뛴다
  param(
    [scriptblock]$Probe,
    [scriptblock]$Wait = { param($seconds) Start-Sleep -Seconds $seconds },
    [int]$SettleSeconds = 60
  )
  if (-not (& $Probe)) { return 'unreachable' }
  & $Wait $SettleSeconds
  if (-not (& $Probe)) { return 'unstable' }
  return 'settled'
}

function Invoke-DailyGuard {
  if (Test-SuccessToday) {
    Write-GuardLog "skip: daily pipeline already succeeded today"
    return 0
  }

  if (-not [System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()) {
    Write-GuardLog "skip: network is not available"
    return 0
  }

  $network = Test-NetworkSettled -Probe { Test-KupidReachable } -SettleSeconds $SettleSeconds
  if ($network -eq 'unreachable') {
    Write-GuardLog "skip: KUPID is not reachable"
    return 0
  }
  if ($network -eq 'unstable') {
    Write-GuardLog "skip: network dropped within ${SettleSeconds}s of resume, will retry on the next trigger"
    return 0
  }

  $mutex = New-Object System.Threading.Mutex($false, 'Local\WorksiteDailyCrawlerCatchUp')
  $hasLock = $mutex.WaitOne(0)
  if (-not $hasLock) {
    Write-GuardLog "skip: catch-up run is already active"
    return 0
  }

  try {
    $BatchFile = Join-Path $ScriptDir 'run_daily.bat'
    Write-GuardLog "start: no success marker for today, running daily pipeline"
    $proc = Start-Process -FilePath $BatchFile -WorkingDirectory $Root -Wait -PassThru -WindowStyle Hidden
    if ($proc.ExitCode -ne 0) {
      Write-GuardLog "fail: daily pipeline exited with code $($proc.ExitCode)"
      return $proc.ExitCode
    }

    Set-Content -LiteralPath $SuccessMarker -Encoding ascii -Value $Today
    Write-GuardLog "done: catch-up run completed"
    return 0
  } finally {
    if ($hasLock) {
      [void]$mutex.ReleaseMutex()
    }
    $mutex.Dispose()
  }
}

# dot-source(". .\run_daily_if_needed.ps1")하면 함수만 정의된다 — Pester 테스트용.
if ($MyInvocation.InvocationName -ne '.') {
  exit (Invoke-DailyGuard)
}
