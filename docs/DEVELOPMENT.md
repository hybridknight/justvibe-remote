# Development, CI, and releases

## Git Flow

- `main` contains release-ready history. Tag production releases here.
- `develop` is the integration branch for the next release.
- `feature/<name>` starts from `develop` and returns to `develop` through a pull request.
- `release/<version>` starts from `develop`. Finish version metadata, documentation, and acceptance checks here, then merge into `main` and back into `develop`.
- `hotfix/<version>` starts from `main` for an urgent fix. Merge into `main` and back into `develop` (and any active release branch).
- Release tags use `vMAJOR.MINOR.PATCH`, such as `v1.0.0`.

Use merge commits when finishing Git Flow branches so their ancestry is preserved. Review pull requests and wait for CI before merging. The `git-flow` extension is optional; ordinary Git and GitHub pull requests are sufficient. Do not rebase or force-push shared `main` or `develop` history.

Start a feature:

```sh
git switch develop
git pull --ff-only
git switch -c feature/my-change
# Make and commit your changes.
git push -u origin feature/my-change
gh pr create --base develop
```

After merging, update local `develop` before starting the next feature. Use pull requests targeting `main` explicitly; GitHub's default branch remains `main`.

## Continuous integration

[CI](../.github/workflows/ci.yml) runs on pull requests targeting `main`, `develop`, `release/**`, or `hotfix/**`; pushes to those branches; and manual dispatches. The release workflow also calls it against the tagged commit.

- **macOS ARM64:** use a native Apple Silicon runner, run Python signing/release checks and Swift core/session tests, build the app, and upload a ZIP.
- **Windows x64 and ARM64:** run portable tests, validate bundled plugins and starter manifests using the official validator, build and verify native UI pages, and publish self-contained ZIPs for both architectures.
- Upload the Windows UI verification report even if a later step fails.
- Keep build artifacts for 14 days. Downloads appear on the Actions run page; release drafts receive their own copies.

The macOS CI build uses an explicit ad-hoc signature (`JUSTVIBEREMOTE_SIGNING_IDENTITY=-`). It never creates a development certificate or requests user trust. Local builds retain their existing persistent signer behavior. Neither platform's CI package has a distribution signing certificate or Apple notarization. No signing secrets are required for this initial pipeline.

CI never runs `test-cursor-macos.sh`, starts a receiver session, or requests microphone capture. Tests and UI previews do not replace live hardware and dictation acceptance checks. Windows ARM64 is cross-built on an x64 runner, not exercised on ARM64 hardware.

## Prepare version 1.0.0

After the feature pull requests have been integrated and CI is green:

```sh
git switch develop
git pull --ff-only
git switch -c release/1.0.0
```

Update these values together:

| File | Value for 1.0.0 |
| --- | --- |
| `macos/Info.plist` → `CFBundleShortVersionString` | `1.0.0` |
| `macos/Info.plist` → `CFBundleVersion` | Increase the current build number |
| `windows/JustVibeRemote.App/JustVibeRemote.App.csproj` → `Version` | `1.0.0` |
| `windows/JustVibeRemote.App/app.manifest` → `assemblyIdentity.version` | `1.0.0.0` |

Plugin release versions and schema/API versions are independent; do not bump them for a host release.

Run `python3 scripts/check-release.py v1.0.0`, update live-test status and release notes, commit, and push `release/1.0.0`. Open a pull request into `main`, wait for CI, and merge with a merge commit. Merge the release branch back into `develop` through another pull request. Check CI on the resulting `main` commit before tagging it.

## Draft release delivery

[Draft release](../.github/workflows/release.yml) starts only when a `v*` tag is pushed. It requires a stable semantic version, verifies that the tagged commit belongs to `main`, and checks both app versions and the Windows manifest against the tag. It then rebuilds and tests that exact commit.

When ready to create the draft (this is a separate step from setting up CI):

```sh
git switch main
git pull --ff-only
git tag -a v1.0.0 -m "JustVibe Remote 1.0.0"
git push origin v1.0.0
```

Only after all jobs pass, the workflow creates a **draft** GitHub release containing three versioned ZIPs, `SHA256SUMS.txt`, the package/signing notes in `.github/RELEASE-NOTES.md`, and generated change notes. It never publishes the draft automatically. Inspect the assets, complete live acceptance checks, and edit the notes before publishing through GitHub Releases.

If a build fails, fix the release branch before creating a new release commit and tag. Do not move a published tag. If draft creation fails before creating the draft, retry the failed job. If a draft was partially created, inspect it and its assets before deciding whether to replace the draft or upload missing assets; the workflow intentionally does not overwrite existing releases.

## GitHub configuration

Actions is enabled for this repository. CI needs only read access to repository contents; only the draft-release job requests write access. Checkout credentials are not retained, and pull-request workflows do not receive distribution signing secrets.

Once the workflows are on `develop` and `main`, configure branch protection or rulesets for both branches as supported by the repository's GitHub plan. Require pull requests, disallow force pushes/deletion, and require the `macOS ARM64` and `Windows x64 and ARM64` checks after their first runs. Confirm the exact displayed check names in GitHub before adding requirements. Keep merge commits enabled for Git Flow. Branch protection is not installed by these workflow files.

GitHub Actions must be permitted by repository/organization policy and have available runner minutes. This setup does not change repository visibility, publish version 1.0.0, or enable GitHub Wiki.

References: [GitHub runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [reusing workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows), and [GitHub CLI release creation](https://cli.github.com/manual/gh_release_create).
