# One-time Firebase setup for the patient app and the clinician portal.
# Do the console steps in README.md ("Firebase setup") first, then run:
#     powershell -ExecutionPolicy Bypass -File .\setup_firebase.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "`n1/5 Adding the web platform (for the clinician portal)..." -ForegroundColor Cyan
$backup = Join-Path $PSScriptRoot ".setup_backup"
if (Test-Path $backup) { Remove-Item $backup -Recurse -Force }
New-Item -ItemType Directory $backup | Out-Null
Copy-Item lib, pubspec.yaml, test -Destination $backup -Recurse
flutter create --org com.angiesapp --project-name angies_app --platforms web .
Copy-Item (Join-Path $backup "lib\*") lib -Recurse -Force
Copy-Item (Join-Path $backup "test\*") test -Recurse -Force
Copy-Item (Join-Path $backup "pubspec.yaml") . -Force
if (Test-Path test\widget_test.dart) { Remove-Item test\widget_test.dart }
Remove-Item $backup -Recurse -Force

Write-Host "`n2/5 Adding Firebase packages..." -ForegroundColor Cyan
flutter pub add firebase_core firebase_auth cloud_firestore

Write-Host "`n3/5 Checking the Firebase CLI..." -ForegroundColor Cyan
if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
    Write-Host "Installing firebase-tools with npm..."
    npm install -g firebase-tools
}
firebase login

Write-Host "`n4/5 Installing FlutterFire CLI..." -ForegroundColor Cyan
dart pub global activate flutterfire_cli
$env:Path += ";$env:LOCALAPPDATA\Pub\Cache\bin"

Write-Host "`n5/5 Connecting this app to your Firebase project (pick it from the list)..." -ForegroundColor Cyan
flutterfire configure --platforms=android,web

flutter pub get
Write-Host "`nDone." -ForegroundColor Green
Write-Host "Patient app (phone):     flutter run"
Write-Host "Clinician portal (web):  flutter run -d chrome -t lib/portal/main_portal.dart"
