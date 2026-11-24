param(
  [switch]$EnableAfterValidation,
  [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Runner = Join-Path $ScriptDir 'run_daily_if_needed.ps1'
# Windows 11 기본 터미널이 Windows Terminal이면 작업 스케줄러가 띄운 콘솔이 OpenConsole로
# 위임되다 멈춰 PowerShell이 시작도 못 하고 30분 뒤 강제 종료된다(2026-09-09~11 무실행).
# headless conhost가 콘솔을 직접 소유하게 해 위임을 피한다.
$ConsoleHost = Join-Path $env:SystemRoot 'System32\conhost.exe'
$TaskName = 'WorksiteDailyCrawler'
$UserId = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$Enabled = if ($EnableAfterValidation) { 'true' } else { 'false' }
$escapedRunner = [System.Security.SecurityElement]::Escape($Runner)
$escapedUser = [System.Security.SecurityElement]::Escape($UserId)
$StartBoundary = (Get-Date).Date.AddHours(10).AddMinutes(15).ToString('s')

$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>근로고래: 오늘 미실행이면 연결 가능한 시점에 SSC/KUPID 신규 공고 수집</Description></RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>$StartBoundary</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>
    </CalendarTrigger>
    <LogonTrigger><Enabled>true</Enabled><UserId>$escapedUser</UserId></LogonTrigger>
    <SessionStateChangeTrigger><Enabled>true</Enabled><StateChange>SessionUnlock</StateChange><UserId>$escapedUser</UserId></SessionStateChangeTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational"&gt;&lt;Select Path="Microsoft-Windows-NetworkProfile/Operational"&gt;*[System[EventID=10000]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author"><UserId>$escapedUser</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable>
    <ExecutionTimeLimit>PT30M</ExecutionTimeLimit>
    <Enabled>$Enabled</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$([System.Security.SecurityElement]::Escape($ConsoleHost))</Command>
      <Arguments>--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$escapedRunner"</Arguments>
      <WorkingDirectory>$([System.Security.SecurityElement]::Escape((Split-Path -Parent $ScriptDir)))</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

[xml]$parsedXml = $xml
if ($ValidateOnly) {
  Write-Output 'Scheduled-task XML validation passed; no task was registered.'
  exit 0
}

Register-ScheduledTask -TaskName $TaskName -Xml $xml -Force | Out-Null
if ($EnableAfterValidation) {
  Write-Output "$TaskName registered and enabled."
} else {
  Write-Output "$TaskName registered but remains disabled until validation approval."
}
