# Creates a staff (clinician/pharmacist) login for the clinician portal.
# Run from this folder:
#     powershell -ExecutionPolicy Bypass -File .\create_staff.ps1
# Needs Email/Password sign-in turned on in Firebase > Authentication.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# Windows PowerShell 5.1 defaults to old TLS, which Google refuses.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Use the web key: the Android key may be locked to the Android app.
$options = Get-Content lib\firebase_options.dart -Raw
$web = [regex]::Match($options, "(?s)FirebaseOptions\s+web\s*=.*?apiKey:\s*'([^']+)'")
$apiKey = if ($web.Success) { $web.Groups[1].Value } else { [regex]::Match($options, "apiKey:\s*'([^']+)'").Groups[1].Value }
if (-not $apiKey) { throw "Could not find apiKey in lib\firebase_options.dart" }

$email = Read-Host "Staff email (press Enter for pharmacist@demo.clinic)"
if (-not $email) { $email = "pharmacist@demo.clinic" }
$password = Read-Host "Password (at least 6 characters; press Enter for Pharm2026!)"
if (-not $password) { $password = "Pharm2026!" }

$body = @{ email = $email; password = $password; returnSecureToken = $true } | ConvertTo-Json
try {
    Invoke-RestMethod -Method Post -ContentType "application/json" -Body $body `
        -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey" | Out-Null
    Write-Host "`nStaff account created." -ForegroundColor Green
    Write-Host "  Email:    $email"
    Write-Host "  Password: $password"
    Write-Host "Sign in at the portal:  flutter run -d chrome -t lib/portal/main_portal.dart"
} catch {
    $msg = "$($_.ErrorDetails.Message) $($_.Exception.Message)".Trim()
    if ($msg -match "EMAIL_EXISTS") { Write-Host "That email already has an account. Use it, or pick another email." -ForegroundColor Yellow }
    elseif ($msg -match "OPERATION_NOT_ALLOWED") { Write-Host "Turn on Email/Password in Firebase > Authentication > Sign-in method, then run this again." -ForegroundColor Yellow }
    else { Write-Host "Failed: $msg" -ForegroundColor Red }
}
