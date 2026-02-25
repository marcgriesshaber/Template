<#
.SYNOPSIS
    Führt alle Pester-Tests für GenerateReleaseNotes_Advanced.ps1 aus.

.DESCRIPTION
    Stellt sicher, dass Pester v5 installiert ist, und startet die Tests
    mit ausführlicher Ausgabe sowie einem JUnit-Bericht (für CI-Pipelines).
#>

# --- Pester v5 sicherstellen ---
$pester = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester -or $pester.Version.Major -lt 5) {
    Write-Host "Pester v5 nicht gefunden. Installiere jetzt..." -ForegroundColor Yellow
    Install-Module -Name Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck -Scope CurrentUser
}

Import-Module Pester -MinimumVersion 5.0

# --- Konfiguration ---
$config = New-PesterConfiguration
$config.Run.Path                  = $PSScriptRoot
$config.Output.Verbosity          = 'Detailed'
$config.TestResult.Enabled        = $true
$config.TestResult.OutputPath     = Join-Path $PSScriptRoot 'TestResults.xml'
$config.TestResult.OutputFormat   = 'JUnitXml'

# --- Tests starten ---
$result = Invoke-Pester -Configuration $config

# --- Exit-Code für CI ---
if ($result.FailedCount -gt 0) {
    Write-Host "`n$($result.FailedCount) Test(s) FEHLGESCHLAGEN" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "`nAlle $($result.PassedCount) Tests erfolgreich." -ForegroundColor Green
    exit 0
}
