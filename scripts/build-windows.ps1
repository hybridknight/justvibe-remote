param([ValidateSet("win-x64", "win-arm64")][string]$Runtime = "win-x64")
$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
dotnet run --project "$Root/windows/JustVibeRemote.Tests/JustVibeRemote.Tests.csproj" -- "$Root"
if ($LASTEXITCODE -ne 0) { throw "Core tests failed." }
if (Test-Path "$Root/dist/windows-$Runtime") { Remove-Item "$Root/dist/windows-$Runtime" -Recurse -Force }
dotnet publish "$Root/windows/JustVibeRemote.App/JustVibeRemote.App.csproj" -c Release -r $Runtime --self-contained true -o "$Root/dist/windows-$Runtime"
if ($LASTEXITCODE -ne 0) { throw "Windows build failed." }
Write-Host "Built: $Root/dist/windows-$Runtime/JustVibeRemote.exe"
