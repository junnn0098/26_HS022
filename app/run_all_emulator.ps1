$ErrorActionPreference = 'Stop'

Set-Location -LiteralPath $PSScriptRoot

$port = 8000
$serverUrl = "http://10.0.2.2:$port"

function Write-Step {
  param([string] $Message)
  Write-Host ''
  Write-Host $Message -ForegroundColor Cyan
}

function Test-LocalPortOpen {
  param([int] $Port)

  $client = $null
  try {
    $client = [System.Net.Sockets.TcpClient]::new()
    $task = $client.ConnectAsync('127.0.0.1', $Port)
    if (-not $task.Wait(450)) {
      return $false
    }
    return $client.Connected
  } catch {
    return $false
  } finally {
    if ($client) {
      $client.Dispose()
    }
  }
}

function Get-AndroidSdkDir {
  $candidates = @(
    $env:ANDROID_HOME,
    $env:ANDROID_SDK_ROOT,
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  throw 'Android SDK 폴더를 찾지 못했어요. ANDROID_HOME 또는 ANDROID_SDK_ROOT를 확인해 주세요.'
}

function Get-RunningEmulator {
  param([string] $AdbExe)

  $lines = & $AdbExe devices
  foreach ($line in $lines) {
    if ($line -match '^(emulator-\d+)\s+device$') {
      return $Matches[1]
    }
  }

  return $null
}

function Wait-EmulatorReady {
  param([string] $AdbExe)

  for ($i = 1; $i -le 120; $i++) {
    $deviceId = Get-RunningEmulator -AdbExe $AdbExe
    if ($deviceId) {
      $boot = (& $AdbExe -s $deviceId shell getprop sys.boot_completed 2>$null | Select-Object -First 1).Trim()
      if ($boot -eq '1') {
        return $deviceId
      }
    }

    Start-Sleep -Seconds 2
  }

  throw '에뮬레이터 부팅 대기 시간이 초과됐어요. 에뮬레이터 창이 정상적으로 켜졌는지 확인해 주세요.'
}

Write-Host ''
Write-Host '==================================================' -ForegroundColor DarkGray
Write-Host ' Hanium app all-in-one launcher' -ForegroundColor White
Write-Host '==================================================' -ForegroundColor DarkGray
Write-Host ''
Write-Host '1. Mock server starts in a separate window.'
Write-Host '2. Android emulator starts if it is not already running.'
Write-Host "3. Flutter app runs with SERVER_URL=$serverUrl"

Write-Step '[1/4] Mock server 확인'
$serverScript = Join-Path $PSScriptRoot 'server\run_mock_server_node.cmd'
if (-not (Test-Path -LiteralPath $serverScript)) {
  throw "서버 실행 파일을 찾지 못했어요: $serverScript"
}

if (Test-LocalPortOpen -Port $port) {
  Write-Host "이미 $port 포트에서 서버가 실행 중이에요. 새로 켜지 않고 이어서 진행합니다." -ForegroundColor Yellow
} else {
  Start-Process -FilePath 'cmd.exe' -ArgumentList @('/k', "`"$serverScript`"") -WorkingDirectory (Split-Path $serverScript)
  Start-Sleep -Seconds 3
}

Write-Step '[2/4] Android SDK / Flutter 확인'
$sdkDir = Get-AndroidSdkDir
$adbExe = Join-Path $sdkDir 'platform-tools\adb.exe'
$emulatorExe = Join-Path $sdkDir 'emulator\emulator.exe'

if (-not (Test-Path -LiteralPath $adbExe)) {
  throw "adb.exe를 찾지 못했어요: $adbExe"
}

if (-not (Test-Path -LiteralPath $emulatorExe)) {
  throw "emulator.exe를 찾지 못했어요: $emulatorExe"
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'flutter 명령어를 찾지 못했어요. Flutter bin 경로가 PATH에 들어갔는지 확인해 주세요.'
}

& $adbExe start-server | Out-Null

Write-Step '[3/4] Android emulator 확인'
$deviceId = Get-RunningEmulator -AdbExe $adbExe

if (-not $deviceId) {
  $avds = & $emulatorExe -list-avds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  if (-not $avds) {
    throw '생성된 Android 가상 기기를 찾지 못했어요. 먼저 에뮬레이터를 하나 만들어 주세요.'
  }

  $preferred = $avds | Where-Object { $_ -eq 'Medium_Phone_API_36.1' } | Select-Object -First 1
  if ($preferred) {
    $avdName = $preferred
  } else {
    $avdName = $avds | Select-Object -First 1
  }

  Write-Host "에뮬레이터 시작: $avdName"
  Start-Process -FilePath $emulatorExe -ArgumentList @('-avd', $avdName)
} else {
  Write-Host "이미 실행 중인 에뮬레이터: $deviceId" -ForegroundColor Green
}

Write-Host '에뮬레이터 부팅 완료를 기다리는 중...'
$deviceId = Wait-EmulatorReady -AdbExe $adbExe
Write-Host "에뮬레이터 준비 완료: $deviceId" -ForegroundColor Green

try {
  & $adbExe -s $deviceId shell pm trim-caches 2G | Out-Null
} catch {
  Write-Host '저장공간 정리는 건너뛰었어요. 앱 실행은 계속 진행합니다.' -ForegroundColor Yellow
}

Write-Step '[4/4] Flutter app 실행'
flutter pub get
if ($LASTEXITCODE -ne 0) {
  throw 'flutter pub get 실패'
}

flutter run -d $deviceId --dart-define="SERVER_URL=$serverUrl" --dart-define='DEMO_MODE=false'
if ($LASTEXITCODE -ne 0) {
  throw 'flutter run 실패'
}
