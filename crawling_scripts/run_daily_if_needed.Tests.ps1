# Pester 3.x (Windows 기본 탑재) 테스트.
#   Invoke-Pester -Script crawling_scripts\run_daily_if_needed.Tests.ps1
# 가드 스크립트를 dot-source하면 함수만 정의되고 본문은 실행되지 않는다.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'run_daily_if_needed.ps1')

Describe 'Test-NetworkSettled' {
  It 'reports settled when the network answers before and after the wait' {
    $waits = New-Object System.Collections.ArrayList
    $status = Test-NetworkSettled -Probe { $true } `
      -Wait { param($seconds) [void]$waits.Add($seconds) } -SettleSeconds 60
    $status | Should Be 'settled'
    $waits.Count | Should Be 1
    $waits[0] | Should Be 60
  }

  It 'reports unstable when the network drops during the wait' {
    # 실제 사례(2026-10-05): 절전 복귀 직후 작업이 시작됐고 12초 뒤 다시 잠들어
    # 79분 뒤 깨어났을 때 네트워크가 없어 SSO·DNS가 실패했다.
    $script:answers = New-Object System.Collections.Queue
    $script:answers.Enqueue($true)
    $script:answers.Enqueue($false)
    $status = Test-NetworkSettled -Probe { $script:answers.Dequeue() } `
      -Wait { param($seconds) } -SettleSeconds 60
    $status | Should Be 'unstable'
  }

  It 'reports unreachable without waiting when the first probe fails' {
    $waits = New-Object System.Collections.ArrayList
    $status = Test-NetworkSettled -Probe { $false } `
      -Wait { param($seconds) [void]$waits.Add($seconds) } -SettleSeconds 60
    $status | Should Be 'unreachable'
    $waits.Count | Should Be 0
  }
}
