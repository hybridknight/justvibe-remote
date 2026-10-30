param([string]$OutputDirectory, [switch]$SkipBuild)
$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
if (-not $IsWindows -and $env:OS -ne "Windows_NT") { throw "Native UI verification requires Windows. Portable core tests can run on other systems." }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $Root "build/windows-ui-verification" }
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
if (-not $SkipBuild) {
    dotnet build "$Root/windows/JustVibeRemote.App" -c Release
    if ($LASTEXITCODE -ne 0) { throw "Windows build failed." }
}
$App = Join-Path $Root "windows/JustVibeRemote.App/bin/Release/net10.0-windows/JustVibeRemote.exe"
if (-not (Test-Path $App)) { throw "Build the Windows app before using -SkipBuild." }
# Never let a report from an earlier run stand in for this process's result.
foreach ($Name in @("verification.json", "failure.txt")) {
    Remove-Item (Join-Path $OutputDirectory $Name) -Force -ErrorAction SilentlyContinue
}
$Process = Start-Process -FilePath $App -ArgumentList @("--verify-ui", ('"' + $OutputDirectory + '"')) -PassThru
if (-not $Process.WaitForExit(120000)) {
    $Process.Kill()
    throw "Native UI verification exceeded two minutes. Inspect the screenshots in $OutputDirectory."
}
if ($Process.ExitCode -ne 0) { throw "Native UI checks failed. Read $OutputDirectory/failure.txt" }
if (-not (Test-Path (Join-Path $OutputDirectory "verification.json"))) { throw "The app did not produce a verification report." }
$Report = Get-Content (Join-Path $OutputDirectory "verification.json") -Raw | ConvertFrom-Json
if (-not $Report.passed -or $Report.images -ne 35 -or -not $Report.editingWorkflows -or -not $Report.hoverRepaint -or $Report.deviceTests -or $Report.audioCapture) { throw "Native UI verification did not satisfy the expected checks." }
Write-Host "Verified $($Report.images) native Windows previews at $($Report.dpi) DPI. No receiver started or audio captured."
