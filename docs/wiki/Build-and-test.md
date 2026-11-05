# Build and test

**macOS:** install Apple Command Line Tools. Configure a persistent development signer once, then test and build:

```sh
python3 scripts/local-signing.py setup
./scripts/test-macos.sh
./scripts/build-macos.sh
```

Signing setup creates a local code-signing identity and may request authorization. Alternatively, set `JUSTVIBEREMOTE_SIGNING_IDENTITY` to your Apple Development or Developer ID identity.

**Windows:** install the .NET 10 SDK and run from PowerShell:

```powershell
./scripts/build-windows.ps1
```

For native Windows page/layout verification without starting receivers or recording,
run `./scripts/test-windows-ui.ps1` on Windows. See [the platform support review](https://github.com/hybridknight/justvibe-remote/blob/main/docs/PLATFORM-PARITY.md)
for the feature matrix, platform boundaries, and live acceptance checks.

Run the portable Windows core tests on macOS, Windows, or Linux:

```sh
dotnet run --project windows/JustVibeRemote.Tests/JustVibeRemote.Tests.csproj -- .
```
