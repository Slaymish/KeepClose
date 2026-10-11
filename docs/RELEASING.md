# Releasing Keep Close

Invoke the project `$release` skill in `.agents/skills/release/SKILL.md` when asking an agent to release. Claude Code can read the same file through `AGENTS.md`. The skill prepares the changelog, updates the app version, runs checks and pushes an annotated version tag.

## One-time credentials

GitHub Actions → repository Settings → Secrets and variables → Actions needs these secrets:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | Base64-encoded exported **Developer ID Application** certificate and private key |
| `APPLE_CERTIFICATE_PASSWORD` | Password protecting that P12 (may be empty only if the P12 is unprotected) |
| `APPLE_SIGNING_IDENTITY` | Exact `Developer ID Application: … (TEAMID)` identity |
| `APPLE_API_KEY_ID` | App Store Connect API key ID with notarization access |
| `APPLE_API_ISSUER_ID` | The API key's issuer UUID |
| `APPLE_API_PRIVATE_KEY` | Complete `.p8` private key contents |
| `SPARKLE_PRIVATE_KEY` | Sparkle Ed25519 private key; already configured for this repository |

Apple Development certificates are for development; the distribution workflow requires Developer ID Application and Apple notarization. The workflow fails before packaging if credentials are missing, and does not publish an unsigned substitute. Do not commit/export private keys into this checkout. Use `gh secret set NAME < /secure/path/file` or GitHub's secret UI. Keep offline recovery copies of signing keys in a secure location.

The Sparkle public key is committed in `project.yml`. Its private counterpart is stored in the local Keychain under the `KeepClose` account and in the repository secret. Releasing requires no key generation. Losing or rotating it affects existing installs; follow [Sparkle's signing documentation](https://sparkle-project.org/documentation/) before making any change.

## Version and publication

1. Write concrete notes under `CHANGELOG.md` → `[Unreleased]`.
2. `python3 scripts/release.py prepare 0.1.0` (example first release). It moves notes into a dated section, updates `MARKETING_VERSION`, increments `CURRENT_PROJECT_VERSION`, and regenerates Xcode.
3. Run checks, inspect the diff and `python3 scripts/release.py verify 0.1.0`.
4. Commit/push to main; `git tag -a v0.1.0 -m 'Keep Close 0.1.0'`, then `git push origin v0.1.0`.
5. Inspect the **Release** workflow and the resulting GitHub release. A failed tag does not imply a published release.

The workflow builds/tests both platforms, then packages universal Apple Silicon/Intel Mac app and CLI binaries. It signs every nested Sparkle component with the same Developer ID identity, notarizes the app and CLI, staples the app, signs the archive and appcast with Sparkle, and publishes `KeepClose-macOS.zip`, `keepclose-cli-macOS.zip`, `appcast.xml`, and `SHA256SUMS` together. The CLI has an online notarization ticket; command-line executables do not support stapling.

The app reads `https://github.com/slaymish/KeepClose/releases/latest/download/appcast.xml`. Releases must remain public. The feed points directly at that version's immutable archive. Version numbers are semantic; build numbers are increasing integers, used by Sparkle to compare installs. Do not overwrite published archives/tags. The current feed intentionally advertises just the latest full update, without delta updates or older releases.

Sparkle is macOS-only. Release builds support scheduled checks, optional automatic installation through Sparkle's UI, and **Keep Close → Check for Updates…**. Debug builds don't start the updater. iPhone/iPad distribution and updates still require Xcode or a separately configured App Store/TestFlight process; this workflow does not upload to Apple.

## Signing without a Developer ID certificate

A Developer ID Application certificate and notarization credentials require paid Apple Developer
Program membership. Until those exist, two helper scripts cover local use:

```sh
scripts/create-selfsigned-identity.sh          # once: a trusted, self-signed code-signing identity
scripts/build-selfsigned.sh                    # signs and packages app + CLI archives
scripts/build-selfsigned.sh 0.1.0 --publish    # also tags, pushes and creates the GitHub release
```

The result is signed but **not notarized**. Other Macs block the first launch until the user approves it
in System Settings → Privacy & Security, or clears the quarantine flag on the CLI with
`xattr -d com.apple.quarantine keepclose`. The helper now signs the update ZIP and appcast with the existing
KeepClose Sparkle key and publishes the feed. Set `SPARKLE_KEY_FILE` to use an explicitly provided key file;
otherwise it uses the existing `KeepClose` Keychain account. It never generates or rotates keys. Test updating
an older installation before publishing. Sparkle authentication does not provide Apple notarization.
Explicitly self-signed annotated tags still run the Release workflow's core/CLI tests and both
platform builds, while skipping its Apple notarization/publication job; the local packaging path
publishes the verified archives and feed instead.

`scripts/release-secrets.sh <setup|check|load|tag>` loads the six Apple secrets into the repository when
the credentials do exist, and can tag the prepared release afterwards. `scripts/build-selfsigned.sh`
prefers a Developer ID identity when one is present, so the same command produces a better-signed result
once the certificate is installed.

The Apple Development certificate in this checkout's keychain is revoked, which is why
`scripts/create-selfsigned-identity.sh` exists: `codesign` rejects a revoked identity, so an expired or
revoked Apple certificate cannot be used even for local builds.

## Local build

`scripts/build-release.sh VERSION BUILD` performs the same packaging when the signing identity and `NOTARY_KEY_FILE`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` are provided in the environment. Output is ignored under `.build-release/dist`. It does not publish or tag by itself.
