param(
  [ValidateSet('success', 'partial', 'fail')]
  [string]$Kind = 'success',
  [string]$StatusPath = ''
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$StatusPath = if ($StatusPath) { $StatusPath } else {
  Join-Path $RepoRoot 'data\crawl_status.json'
}
$pendingCount = 0
$deferredCount = 0
$exhaustedCount = 0

$title = switch ($Kind) {
  'success' { '근로고래 크롤링 완료' }
  'partial' { '근로고래 크롤링 일부 실패' }
  default   { '근로고래 크롤링 실패' }
}

$message = switch ($Kind) {
  'success' { '공고 수집과 DB 적재가 완료되었습니다.' }
  'partial' { '일부 출처 또는 후처리에 실패했습니다. 다음 인터넷 연결 시 다시 시도합니다.' }
  default   { '크롤러를 실행하지 못했습니다. 최신 로그를 확인해 주세요.' }
}

if ($StatusPath -and (Test-Path -LiteralPath $StatusPath)) {
  try {
    $status = Get-Content -LiteralPath $StatusPath -Raw -Encoding utf8 | ConvertFrom-Json
    $message += (' 신규 공고: {0}건.' -f $status.inserted)
    if ($status.pending -gt 0) {
      $pendingCount = [int]$status.pending
      $message += (' 근무지 검토 대기: {0}건.' -f $status.pending)
    }
    if ($status.deferred_total -gt 0) {
      $deferredCount = [int]$status.deferred_total
      $message += (' AI 확인 대기: {0}건.' -f $deferredCount)
    }
    if ($status.exhausted_total -gt 0) {
      $exhaustedCount = [int]$status.exhausted_total
      $message += (' 재시도 3회 초과: {0}건.' -f $exhaustedCount)
    }
    if ($status.new_worksites.Count -gt 0) {
      $message += ' 신규 근무지: ' + ($status.new_worksites -join ', ')
    }
    if ($status.errors.Count -gt 0) {
      $message += (' 오류: {0}건.' -f $status.errors.Count)
    }
  } catch {
    $message += ' (상태 파일을 읽지 못했습니다.)'
  }
}

function Start-WorksiteReview {
  $pythonPath = Join-Path $RepoRoot '.venv\Scripts\python.exe'
  $reviewPath = Join-Path $ScriptDir 'review_worksite_queue.py'
  if (-not (Test-Path -LiteralPath $pythonPath)) {
    throw "Python 실행 파일을 찾을 수 없습니다: $pythonPath"
  }
  $escapedRoot = $RepoRoot.Replace("'", "''")
  $escapedPython = $pythonPath.Replace("'", "''")
  $escapedReview = $reviewPath.Replace("'", "''")
  $command = (
    "Set-Location -LiteralPath '$escapedRoot'; " +
    "& '$escapedPython' '$escapedReview' --interactive"
  )
  $encoded = [Convert]::ToBase64String(
    [System.Text.Encoding]::Unicode.GetBytes($command)
  )
  Start-Process powershell.exe -WorkingDirectory $RepoRoot -ArgumentList @(
    '-NoProfile',
    '-EncodedCommand',
    $encoded
  )
}

function Start-QuotaGrant {
  $pythonPath = Join-Path $RepoRoot '.venv\Scripts\python.exe'
  $pipelinePath = Join-Path $ScriptDir 'crawler_pipeline\cli.py'
  $notificationPath = $PSCommandPath
  $escapedRoot = $RepoRoot.Replace("'", "''")
  $escapedPython = $pythonPath.Replace("'", "''")
  $escapedPipeline = $pipelinePath.Replace("'", "''")
  $escapedNotification = $notificationPath.Replace("'", "''")
  $command = (
    "Set-Location -LiteralPath '$escapedRoot'; " +
    "& '$escapedPython' '$escapedPipeline' --add-ai-quota 5; " +
    "if (`$LASTEXITCODE -eq 0) { & '$escapedPython' '$escapedPipeline' }; " +
    "`$notifyKind = if (`$LASTEXITCODE -eq 0) { 'success' } else { 'partial' }; " +
    "& powershell.exe -NoProfile -ExecutionPolicy Bypass " +
    "-File '$escapedNotification' -Kind `$notifyKind"
  )
  $encoded = [Convert]::ToBase64String(
    [System.Text.Encoding]::Unicode.GetBytes($command)
  )
  Start-Process powershell.exe -WorkingDirectory $RepoRoot -WindowStyle Hidden -ArgumentList @(
    '-NoProfile',
    '-EncodedCommand',
    $encoded
  )
}

function Open-CrawlerFolder {
  Start-Process explorer.exe -ArgumentList $ScriptDir
}

try {
  # WinRT silently discards notifications from an unregistered arbitrary app
  # ID. NotifyIcon works in the signed-in user's desktop session without an
  # installer, Start-menu shortcut, or third-party PowerShell module.
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing

  if ($pendingCount -gt 0 -or $deferredCount -gt 0 -or
      $exhaustedCount -gt 0 -or $Kind -ne 'success') {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $title
    $form.Size = New-Object System.Drawing.Size(440, 220)
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedToolWindow
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $false
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $form.TopMost = $true

    $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $form.Location = New-Object System.Drawing.Point(
      ($area.Right - $form.Width - 18),
      ($area.Bottom - $form.Height - 18)
    )

    $messageLabel = New-Object System.Windows.Forms.Label
    $messageLabel.Location = New-Object System.Drawing.Point(20, 20)
    $messageLabel.Size = New-Object System.Drawing.Size(395, 82)
    $messageLabel.Font = New-Object System.Drawing.Font('맑은 고딕', 10)
    $messageLabel.Text = $message
    $form.Controls.Add($messageLabel)

    $hintLabel = New-Object System.Windows.Forms.Label
    $hintLabel.Location = New-Object System.Drawing.Point(20, 105)
    $hintLabel.Size = New-Object System.Drawing.Size(395, 25)
    $hintLabel.ForeColor = [System.Drawing.Color]::DimGray
    $hintLabel.Text = if ($deferredCount -gt 0) {
      '추가 AI 요청을 승인하거나 내일 자동 처리되도록 둘 수 있습니다.'
    } elseif ($pendingCount -gt 0) {
      '검토할 준비가 되면 검토하기를 눌러 주세요.'
    } else {
      '로그를 확인하거나 창을 닫아 주세요.'
    }
    $form.Controls.Add($hintLabel)

    $reviewButton = New-Object System.Windows.Forms.Button
    $reviewButton.Location = New-Object System.Drawing.Point(95, 140)
    $reviewButton.Size = New-Object System.Drawing.Size(100, 32)
    $reviewButton.Text = if ($deferredCount -gt 0) {
      '5건 추가 실행'
    } elseif ($pendingCount -gt 0) {
      '검토하기'
    } else {
      '로그 열기'
    }
    $reviewButton.Add_Click({
      try {
        if ($deferredCount -gt 0) {
          Start-QuotaGrant
        } elseif ($pendingCount -gt 0) {
          Start-WorksiteReview
        } else {
          Open-CrawlerFolder
        }
        $form.Close()
      } catch {
        [System.Windows.Forms.MessageBox]::Show(
          $_.Exception.Message,
          '검토 창 실행 실패',
          [System.Windows.Forms.MessageBoxButtons]::OK,
          [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
      }
    })
    $form.Controls.Add($reviewButton)

    $laterButton = New-Object System.Windows.Forms.Button
    $listButton = New-Object System.Windows.Forms.Button
    $listButton.Location = New-Object System.Drawing.Point(205, 140)
    $listButton.Size = New-Object System.Drawing.Size(100, 32)
    $listButton.Text = if ($deferredCount -gt 0) { '목록 열기' } else { '닫기' }
    $listButton.Add_Click({
      if ($deferredCount -gt 0) {
        Open-CrawlerFolder
      }
      $form.Close()
    })
    $form.Controls.Add($listButton)

    $laterButton.Location = New-Object System.Drawing.Point(315, 140)
    $laterButton.Size = New-Object System.Drawing.Size(100, 32)
    $laterButton.Text = if ($deferredCount -gt 0) { '내일 처리' } else { '나중에' }
    $laterButton.Add_Click({ $form.Close() })
    $form.Controls.Add($laterButton)

    $form.Add_Shown({
      $form.Activate()
      $reviewButton.Focus()
    })
    [void]$form.ShowDialog()
    $form.Dispose()
    exit 0
  }

  $notification = New-Object System.Windows.Forms.NotifyIcon
  $notification.Icon = [System.Drawing.SystemIcons]::Information
  $notification.Text = '근로고래'
  $notification.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
  $notification.BalloonTipTitle = $title.Substring(0, [Math]::Min(63, $title.Length))
  $notification.BalloonTipText = $message.Substring(0, [Math]::Min(240, $message.Length))
  $notification.Visible = $true
  $notification.ShowBalloonTip(8000)
  [System.Windows.Forms.Application]::DoEvents()
  Start-Sleep -Milliseconds 6000
  $notification.Dispose()
} catch {
  if ($notification) {
    $notification.Dispose()
  }
  Write-Output "$title - $message"
  Write-Error "Windows 알림 표시 실패: $($_.Exception.Message)"
}
