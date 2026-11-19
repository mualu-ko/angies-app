# One-time setup. In PowerShell, from this folder, run:
#     powershell -ExecutionPolicy Bypass -File .\setup.ps1
# It generates the Android project files around the app code, applies the
# settings the alarm package needs, and downloads the packages.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if ($PSScriptRoot -match "[' ]") {
    Write-Warning "This folder's path has a space or an apostrophe ($PSScriptRoot)."
    Write-Warning "If the Android build fails with odd path errors, copy the project to e.g. C:\dev\angies_app and run this again."
}

Write-Host "`n1/5 Checking Flutter..." -ForegroundColor Cyan
flutter --version

Write-Host "`n2/5 Backing up the app code..." -ForegroundColor Cyan
$backup = Join-Path $PSScriptRoot ".setup_backup"
if (Test-Path $backup) { Remove-Item $backup -Recurse -Force }
New-Item -ItemType Directory $backup | Out-Null
Copy-Item lib, pubspec.yaml, analysis_options.yaml, test -Destination $backup -Recurse
Copy-Item android\app\src\main\AndroidManifest.xml $backup

Write-Host "`n3/5 Generating Android project files..." -ForegroundColor Cyan
flutter create --org com.angiesapp --project-name angies_app --platforms android .

# Put our code and manifest back in case 'flutter create' replaced anything.
Copy-Item (Join-Path $backup "lib\*") lib -Recurse -Force
Copy-Item (Join-Path $backup "test\*") test -Recurse -Force
Copy-Item (Join-Path $backup "pubspec.yaml") . -Force
Copy-Item (Join-Path $backup "analysis_options.yaml") . -Force
Copy-Item (Join-Path $backup "AndroidManifest.xml") android\app\src\main\AndroidManifest.xml -Force
if (Test-Path test\widget_test.dart) { Remove-Item test\widget_test.dart }

Write-Host "`n4/5 Applying alarm package settings (minSdk 23, Kotlin 2.x)..." -ForegroundColor Cyan
$appGradle = @("android\app\build.gradle.kts", "android\app\build.gradle") | Where-Object { Test-Path $_ } | Select-Object -First 1
$c = [IO.File]::ReadAllText((Resolve-Path $appGradle))
$c = $c -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23'
$c = $c -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 23'
[IO.File]::WriteAllText((Resolve-Path $appGradle), $c)

$settings = @("android\settings.gradle.kts", "android\settings.gradle") | Where-Object { Test-Path $_ } | Select-Object -First 1
$s = [IO.File]::ReadAllText((Resolve-Path $settings))
$s = $s -replace '(org\.jetbrains\.kotlin\.android"\)?\s+version\s+")1\.[0-9.]+', '${1}2.1.0'
[IO.File]::WriteAllText((Resolve-Path $settings), $s)

Write-Host "`n5/5 Downloading packages..." -ForegroundColor Cyan
flutter pub get

Remove-Item $backup -Recurse -Force
Write-Host "`nDone. Plug in an Android phone (USB debugging on) and run:  flutter run" -ForegroundColor Green
