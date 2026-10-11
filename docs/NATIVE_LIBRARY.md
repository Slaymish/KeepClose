# Shared native library

The CLI/core package and macOS/iOS app consume HamishNativeLibrary 0.2.x from its public GitHub repository.
Package.swift and project.yml own the dependency; commit Package.resolved when updating its tested version.

NativeCore supplies JSON codecs, application-support paths, atomic private writes, the synchronous lock
and snapshot comparisons. The Mac app/CLI still share `Application Support/KeepClose`; iOS uses its sandbox.
The lock remains the existing `.lock`, so old and new writers cooperate. Stored dates retain Foundation's
original reference-date representation; prompts and CLI output retain ISO 8601 dates. No data migration occurs.

AgentInterchange supplies StrictJSONDocument and PayloadSchema for Keep Close's existing version-1/2 import
contract. People matching, additive notes/categories/context, history, user preferences and dismissal rules
stay in AgentImport.swift. Its repository still owns preview freshness, backups and provider checkpoints.
Replacing that transaction with a second ExchangeSession store would risk inconsistent domain updates.

NativeUI supplies bounded security-scoped file reads and text copy. The existing person/idea selection UI
stays app-specific. NativeSecurity supplies the authentication gate model; LocalAuthentication and private
reminder policies remain in the app. Accepting context still does not imply that agent memory was saved.

Archive/appcast entrypoints delegate to scripts in the same resolved library checkout through
scripts/native-library-tool. They resolve the dependency if needed and keep the existing external command
arguments and filenames. HAMISH_NATIVE_LIBRARY_PATH is an explicit local-development override only.
The self-signed release helper now signs archive and feed using the existing KeepClose key, verifies archive
key continuity and includes the feed in release assets. Code-signing identities, entitlements, notarisation,
version preparation and actual publication remain this app's responsibility.

Run `swift test`, `python3 scripts/test-cli.py`, both native builds and release-script checks after upgrading.
Test a real update from the previous installed app before publishing a feed. No real user data or credentials
are touched during these isolated checks. Shared fixes belong in HamishNativeLibrary; Keep Close's domain
rules belong here. Library updates require an app rebuild/release to reach installed users.
