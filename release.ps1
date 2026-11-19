# Builds the demo APK and puts the clinician portal online (Firebase Hosting).
# Run from this folder:
#     powershell -ExecutionPolicy Bypass -File .\release.ps1
# First time only: you may be asked to run `firebase login`.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$out = Join-Path $PSScriptRoot "release"
New-Item -ItemType Directory $out -Force | Out-Null

Write-Host "`n1/4 Building the patient app (APK)..." -ForegroundColor Cyan
flutter build apk --release
Copy-Item build\app\outputs\flutter-apk\app-release.apk (Join-Path $out "angies-app.apk") -Force

Write-Host "`n2/4 Building the clinician portal (web)..." -ForegroundColor Cyan
flutter build web --release -t lib/portal/main_portal.dart

Write-Host "`n3/4 Publishing the security rules..." -ForegroundColor Cyan
firebase deploy --only firestore:rules --project pharmavigilance

Write-Host "`n4/4 Putting the portal online..." -ForegroundColor Cyan
firebase deploy --only hosting --project pharmavigilance

Write-Host "`nDone." -ForegroundColor Green
Write-Host "APK to share:  $out\angies-app.apk"
Write-Host "Portal link:   https://pharmavigilance.web.app"
