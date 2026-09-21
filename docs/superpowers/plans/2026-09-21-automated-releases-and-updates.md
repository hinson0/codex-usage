# Automated Releases and Sparkle Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish verified DMG and ZIP downloads automatically from version changes on `main`, and let installed copies securely discover and install later releases through Sparkle.

**Architecture:** Keep version and release naming in a small shell library shared by tests, packaging, and GitHub Actions. Embed Sparkle 2.10.0 in the native app behind one process-lifetime coordinator, generate a signed appcast from the exact ZIP uploaded to GitHub, and gate public publication behind a repository variable so the first workflow run can validate without releasing.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Package Manager, Sparkle 2.10.0, Bash, GitHub Actions, GitHub CLI, `ditto`, `hdiutil`, `codesign`, `xmllint`.

**Spec:** `docs/superpowers/specs/2026-09-21-automated-releases-and-updates-design.md`

## Global Constraints

- Keep the deployment target at macOS 13 or newer and publish a universal `arm64` + `x86_64` application.
- `Packaging/Info.plist` remains the sole version source of truth.
- This feature releases as `0.4.1 (5)` after the validation-only CI run exposed and fixed full-Xcode test-runner portability.
- Public assets are exactly the versioned DMG, versioned ZIP, `SHA256SUMS`, and `appcast.xml`.
- The DMG is for manual installation; the ZIP is the only Sparkle update enclosure.
- Only the public EdDSA key enters Git history; the private key lives in the login Keychain and GitHub Actions secret `SPARKLE_PRIVATE_KEY`.
- Automatic checks are enabled, but unattended installation is disabled.
- No Developer ID signing, notarization, beta channel, delta update, forced update, or pull-request publication is added.
- Existing Codex usage and reset behavior must remain independent of updater failures.
- Use `scripts/test.sh`, not bare `swift test`, for Swift tests.
- Live Codex verification remains read-only and must never consume a reset.

## Review Focus

- A malformed short version such as `0.3` or `v0.3.0` must stop before an artifact or tag is created; Task 1 adds both cases to `ReleaseScriptsTests.sh`.
- An already-published tag must be rejected without moving the tag or replacing assets; Task 1 tests the duplicate-ref predicate and Task 6 asserts immutable publication commands.
- A missing Sparkle private key must fail before packaging emits a signed feed; Task 5 exercises the missing-secret guard.
- A ZIP containing the wrong app version or anything beside `CodexUsage.app` must be rejected; Task 5 builds invalid fixtures and exercises archive validation.
- When Sparkle cannot check, “Check for Updates” must be disabled while Refresh and reset behavior remain unchanged; Task 2 tests the pure presentation state and Task 3 keeps updater state separate from `UsageController`.

---

### Task 1: Release identity and immutable-version guards

**Files:**
- Create: `scripts/release-lib.sh`
- Create: `Tests/ReleaseScriptsTests.sh`
- Modify: `scripts/test.sh`

**Interfaces:**
- Consumes: `Packaging/Info.plist` keys `CFBundleShortVersionString` and `CFBundleVersion`.
- Produces: Bash functions `release_short_version PLIST`, `release_build_number PLIST`, `release_validate_semver VERSION`, `release_tag VERSION`, `release_asset_stem VERSION`, `release_tag_is_present TAG REFS`, and `release_require_private_key VALUE`.

- [ ] **Step 1: Write the failing shell tests**

Create `Tests/ReleaseScriptsTests.sh` with strict mode, source the library, and pin the public interface:

```bash
#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
source "$repo_root/scripts/release-lib.sh"
fixture="$(mktemp "${TMPDIR:-/tmp}/codex-usage-release-plist.XXXXXX")"
trap 'rm -f "$fixture"' EXIT
cp "$repo_root/Packaging/Info.plist" "$fixture"
plutil -replace CFBundleShortVersionString -string 9.8.7 "$fixture"
plutil -replace CFBundleVersion -string 42 "$fixture"

assert_equal() {
  [[ "$1" == "$2" ]] || { echo "Expected '$2', got '$1'" >&2; exit 1; }
}

assert_fails() {
  "$@" >/dev/null 2>&1 && { echo "Expected failure: $*" >&2; exit 1; }
}

assert_equal "$(release_short_version "$fixture")" "9.8.7"
assert_equal "$(release_build_number "$fixture")" "42"
release_validate_semver "0.3.0"
assert_fails release_validate_semver "0.3"
assert_fails release_validate_semver "v0.3.0"
assert_equal "$(release_tag 0.3.0)" "v0.3.0"
assert_equal "$(release_asset_stem 0.3.0)" "CodexUsage-v0.3.0-macOS"
release_tag_is_present "v0.3.0" $'refs/tags/v0.2.0\nrefs/tags/v0.3.0'
assert_fails release_tag_is_present "v0.4.0" $'refs/tags/v0.2.0\nrefs/tags/v0.3.0'
assert_fails release_require_private_key ""
release_require_private_key "test-only-key"
```

Append `Tests/ReleaseScriptsTests.sh` to `scripts/test.sh` after the Swift runner exits successfully.

- [ ] **Step 2: Run the focused test and observe RED**

Run: `bash Tests/ReleaseScriptsTests.sh`

Expected: FAIL because `scripts/release-lib.sh` does not exist.

- [ ] **Step 3: Add the minimal release library**

Implement the functions without side effects or network access:

```bash
#!/bin/bash

release_short_version() {
  plutil -extract CFBundleShortVersionString raw "$1"
}

release_build_number() {
  plutil -extract CFBundleVersion raw "$1"
}

release_validate_semver() {
  [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

release_tag() { printf 'v%s\n' "$1"; }
release_asset_stem() { printf 'CodexUsage-v%s-macOS\n' "$1"; }

release_tag_is_present() {
  grep -Fxq "refs/tags/$1" <<<"$2"
}

release_require_private_key() {
  [[ -n "$1" ]] || { echo "SPARKLE_PRIVATE_KEY is required." >&2; return 1; }
}
```

- [ ] **Step 4: Run focused and complete tests**

Run: `bash Tests/ReleaseScriptsTests.sh`

Expected: PASS with exit status 0.

Run: `scripts/test.sh`

Expected: all existing Swift tests and the shell release tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/release-lib.sh Tests/ReleaseScriptsTests.sh scripts/test.sh
git commit -m "build: add release metadata guards"
```

### Task 2: Localized updater presentation

**Files:**
- Modify: `Sources/CodexUsageCore/Localization.swift`
- Modify: `Sources/CodexUsageCore/MenuPresentation.swift`
- Modify: `Tests/CodexUsageCoreTests/MenuPresentationTests.swift`
- Modify: `Tests/CodexUsageCoreTests/PreferencesLocalizationControllerTests.swift`

**Interfaces:**
- Consumes: existing `AppLanguage` and `LocalizationCatalog` lookup behavior.
- Produces: `LocalizationKey.checkForUpdates`, `MenuPresentation.canCheckForUpdates`, `MenuPresentation.checkForUpdatesTitle`, and `MenuPresentation.isUpdateEnabled`.

- [ ] **Step 1: Write failing localization and state tests**

Add assertions that both catalogs contain `checkForUpdates`, and add this focused presentation test:

```swift
@Test
func updateActionRelocalizesAndFollowsInjectedAvailability() {
    let english = MenuPresentation(
        snapshot: nil,
        lastReset: nil,
        isRefreshing: false,
        isRedeeming: false,
        error: nil,
        appearance: .light,
        language: .english,
        canCheckForUpdates: true
    )
    let chinese = MenuPresentation(
        snapshot: nil,
        lastReset: nil,
        isRefreshing: false,
        isRedeeming: false,
        error: nil,
        appearance: .light,
        language: .zhHans,
        canCheckForUpdates: false
    )

    #expect(english.checkForUpdatesTitle == "Check for Updates…")
    #expect(english.isUpdateEnabled)
    #expect(chinese.checkForUpdatesTitle == "检查更新…")
    #expect(!chinese.isUpdateEnabled)
}
```

- [ ] **Step 2: Run the focused tests and observe RED**

Run: `scripts/test.sh --filter updateActionRelocalizesAndFollowsInjectedAvailability`

Expected: compilation fails because the new key and initializer argument do not exist.

- [ ] **Step 3: Add the presentation state**

Add `.checkForUpdates` to `LocalizationKey`, with `"检查更新…"` and
`"Check for Updates…"` in the two dictionaries. Extend `MenuPresentation`:

```swift
public let canCheckForUpdates: Bool

public init(
    snapshot: UsageSnapshot?,
    lastReset: LastResetRecord?,
    isRefreshing: Bool,
    isRedeeming: Bool,
    error: UsageDisplayError?,
    appearance: AppAppearance,
    language: AppLanguage,
    timeZone: TimeZone = .current,
    canCheckForUpdates: Bool = false
) {
    self.snapshot = snapshot
    self.lastReset = lastReset
    self.isRefreshing = isRefreshing
    self.isRedeeming = isRedeeming
    self.error = error
    self.appearance = appearance
    self.language = language
    self.timeZone = timeZone
    self.canCheckForUpdates = canCheckForUpdates
}

public var checkForUpdatesTitle: String { text(.checkForUpdates) }
public var isUpdateEnabled: Bool { canCheckForUpdates }
```

- [ ] **Step 4: Run focused and complete Swift tests**

Run: `scripts/test.sh --filter updateActionRelocalizesAndFollowsInjectedAvailability`

Expected: PASS.

Run: `scripts/test.sh`

Expected: all tests pass and the English/Chinese key sets remain identical.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexUsageCore/Localization.swift Sources/CodexUsageCore/MenuPresentation.swift Tests/CodexUsageCoreTests/MenuPresentationTests.swift Tests/CodexUsageCoreTests/PreferencesLocalizationControllerTests.swift
git commit -m "feat: add localized update action state"
```

### Task 3: Sparkle coordinator and popover action

**Files:**
- Modify: `Package.swift`
- Create: `Package.resolved`
- Create: `Sources/CodexUsageApp/UpdateCoordinator.swift`
- Modify: `Sources/CodexUsageApp/CodexUsageApp.swift`
- Modify: `Sources/CodexUsageApp/UsagePopoverView.swift`
- Modify: `scripts/test.sh`

**Interfaces:**
- Consumes: Task 2’s `MenuPresentation(canCheckForUpdates:)`, `checkForUpdatesTitle`, and `isUpdateEnabled`.
- Produces: `@MainActor final class UpdateCoordinator: ObservableObject` with read-only `canCheckForUpdates`, `start()`, and `checkForUpdates()`.

- [ ] **Step 1: Add a compile-time failing app integration**

Add the Sparkle import and coordinator ownership before declaring the package dependency:

```swift
@StateObject private var updater: UpdateCoordinator

init() {
    _controller = StateObject(wrappedValue: UsageController(service: CodexAppServerClient()))
    _updater = StateObject(wrappedValue: UpdateCoordinator())
}
```

Pass `updater` into `UsagePopoverView` and `StatusItemLabel`, call
`updater.start()` from the status label task, and pass
`updater.canCheckForUpdates` into `MenuPresentation`.

- [ ] **Step 2: Run the release build and observe RED**

Run: `swift build -c release --product CodexUsage -Xswiftc -warnings-as-errors`

Expected: FAIL because `UpdateCoordinator` and the Sparkle module do not exist.

- [ ] **Step 3: Pin Sparkle and add the coordinator**

Add the exact package and executable dependency:

```swift
dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
],
```

Replace the manifest’s fixed Command Line Tools lookup with an environment-aware
developer directory, defaulting to the current local path:

```swift
import Foundation
import PackageDescription

let developerDirectory = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? "/Library/Developer/CommandLineTools"
let commandLineToolsFrameworks = "\(developerDirectory)/Library/Frameworks"
let commandLineToolsTestingLibraries = "\(developerDirectory)/usr/lib"
```

Make `scripts/test.sh` use `${DEVELOPER_DIR:-$(xcode-select -p)}` for the same
two paths. This keeps the custom runner working under both local Command Line
Tools and a GitHub runner’s full Xcode installation.

```swift
dependencies: [
    "CodexUsageCore",
    .product(name: "Sparkle", package: "Sparkle"),
],
```

Resolve once with `swift package resolve` and commit the resulting pin. Create
`UpdateCoordinator.swift` around one `SPUStandardUpdaterController` initialized
with `startingUpdater: false`. Retain an observation of
`updater.canCheckForUpdates`, make `start()` idempotent, and implement
`checkForUpdates()` as `controller.checkForUpdates(nil)`. Observation updates
must hop back to `MainActor` before changing the published property.

- [ ] **Step 4: Add the popover button**

Insert the update row between Refresh and Quit without changing the footer
dimensions:

```swift
Button {
    updater.checkForUpdates()
} label: {
    actionRow(
        title: presentation.checkForUpdatesTitle,
        symbol: "arrow.down.circle"
    )
}
.buttonStyle(.plain)
.disabled(!presentation.isUpdateEnabled)
```

Keep `UsageController` unchanged so a Sparkle failure cannot disable refresh or
reset redemption.

- [ ] **Step 5: Run tests and warnings-as-errors build**

Run: `scripts/test.sh`

Expected: all tests pass.

Run: `swift build -c release --product CodexUsage -Xswiftc -warnings-as-errors`

Expected: build succeeds without warnings.

Run: `otool -L "$(swift build -c release --show-bin-path)/CodexUsage" | rg Sparkle`

Expected: exactly one Sparkle framework dependency is listed.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Package.resolved Sources/CodexUsageApp/UpdateCoordinator.swift Sources/CodexUsageApp/CodexUsageApp.swift Sources/CodexUsageApp/UsagePopoverView.swift scripts/test.sh
git commit -m "feat: integrate Sparkle update checks"
```

### Task 4: Embed and verify Sparkle in the application bundle

**Files:**
- Modify: `scripts/build-app.sh`
- Modify: `Tests/PackagingTests.sh`
- Modify: `Packaging/Info.plist`

**Interfaces:**
- Consumes: Task 3’s resolved Sparkle binary artifact and the generated public EdDSA key.
- Produces: a self-contained `dist/CodexUsage.app` with `Contents/Frameworks/Sparkle.framework`, correct rpaths, Sparkle configuration, and strict nested signatures.

- [ ] **Step 1: Add failing packaging assertions**

Before changing the packager, assert:

```bash
framework="$app/Contents/Frameworks/Sparkle.framework"
[[ -d "$framework" ]]
[[ -n "$(plutil -extract SUFeedURL raw "$info")" ]]
public_key="$(plutil -extract SUPublicEDKey raw "$info")"
[[ "$(printf '%s' "$public_key" | base64 -D | wc -c | tr -d ' ')" == "32" ]]
[[ "$(plutil -extract SUEnableAutomaticChecks raw "$info")" == "true" ]]
[[ "$(plutil -extract SUAutomaticallyUpdate raw "$info")" == "false" ]]
[[ "$(plutil -extract SUVerifyUpdateBeforeExtraction raw "$info")" == "true" ]]
otool -L "$executable" | grep -Fq '@rpath/Sparkle.framework/'
codesign --verify --deep --strict "$framework"
```

- [ ] **Step 2: Run packaging tests and observe RED**

Run: `Tests/PackagingTests.sh`

Expected: FAIL because the framework directory and Sparkle plist keys are absent.

- [ ] **Step 3: Bootstrap the dedicated Sparkle key securely**

Locate `generate_keys` under `.build/artifacts`, use account
`hinson0.codex-usage`, and let it store the private key in the login Keychain:

```bash
generate_keys="$(find .build/artifacts -type f -name generate_keys -perm -111 -print -quit)"
"$generate_keys" --account hinson0.codex-usage
"$generate_keys" --account hinson0.codex-usage -p
```

Copy the printed public key into `Packaging/Info.plist` as `SUPublicEDKey`.
Also add the fixed feed URL, enable automatic checks, disable unattended
installation, and enable pre-extraction verification. Do not export the private
key in this task.

- [ ] **Step 4: Embed and sign the framework**

Update `scripts/build-app.sh` to find the single resolved
`Sparkle.framework`, create `Contents/Frameworks`, copy it with `ditto` so
symlinks survive, ad-hoc sign the framework recursively, then sign the outer
app. Add explicit failures for zero or multiple framework matches. Keep the
final `codesign --verify --deep --strict` call. Add
`CODEX_USAGE_UNIVERSAL=1` support that appends both `--arch arm64` and
`--arch x86_64` to the Swift build; local builds without that environment
variable retain their native architecture.

- [ ] **Step 5: Run packaging, linkage, and smoke verification**

Run: `Tests/PackagingTests.sh`

Expected: PASS and report the packaged app path.

Run: `codesign --verify --deep --strict dist/CodexUsage.app`

Expected: exit status 0.

Run: `otool -L dist/CodexUsage.app/Contents/MacOS/CodexUsage | rg '@rpath/Sparkle.framework/'`

Expected: one embedded Sparkle linkage.

Run: `scripts/smoke-test.sh`

Expected: the menu-bar process stays alive for the smoke interval.

Run: `CODEX_USAGE_UNIVERSAL=1 scripts/build-app.sh && lipo -archs dist/CodexUsage.app/Contents/MacOS/CodexUsage`

Expected: output contains exactly `x86_64 arm64` in either order.

- [ ] **Step 6: Commit**

```bash
git add scripts/build-app.sh Tests/PackagingTests.sh Packaging/Info.plist
git commit -m "build: embed and configure Sparkle"
```

### Task 5: Reproducible ZIP, DMG, appcast, and checksum packaging

**Files:**
- Create: `scripts/package-release.sh`
- Create: `Tests/ReleaseArtifactsTests.sh`
- Modify: `scripts/test.sh`

**Interfaces:**
- Consumes: Task 1 release functions, Task 4 self-contained app, environment variable `SPARKLE_PRIVATE_KEY`, and Sparkle’s `generate_appcast`/`sign_update` tools.
- Produces: `release_validate_zip ZIP EXPECTED_VERSION` plus `dist/release/CodexUsage-vVERSION-macOS.zip`, matching DMG, `appcast.xml`, and `SHA256SUMS`.

- [ ] **Step 1: Write failing guard and archive tests**

Create fixtures under a `mktemp -d` directory and assert that:

```bash
assert_fails env SPARKLE_PRIVATE_KEY= scripts/package-release.sh --validate-inputs

mkdir -p "$fixture/CodexUsage.app/Contents"
ditto -c -k --keepParent "$fixture/CodexUsage.app" "$fixture/wrong.zip"
assert_fails release_validate_zip "$fixture/wrong.zip" "0.3.0"

mkdir -p "$fixture/extra"
ditto -c -k "$fixture" "$fixture/extra.zip"
assert_fails release_validate_zip "$fixture/extra.zip" "0.3.0"
```

Add `release_validate_zip ZIP EXPECTED_VERSION` to `release-lib.sh`; it must
require one top-level `CodexUsage.app` and compare the embedded plist version.
Add `Tests/ReleaseArtifactsTests.sh` to the full `scripts/test.sh` run.

- [ ] **Step 2: Run the focused artifact tests and observe RED**

Run: `bash Tests/ReleaseArtifactsTests.sh`

Expected: FAIL because the packager and ZIP validator do not exist.

- [ ] **Step 3: Implement input validation and artifact creation**

Create a strict-mode script that validates the private key before building,
reads version/build from the plist, derives names from Task 1, and uses an exact
`mktemp -d` staging root with a cleanup trap. A `--validate-inputs` mode runs
only the private-key and tool-discovery guards, then exits without building.
The production sequence is:

```bash
CODEX_USAGE_UNIVERSAL=1 scripts/build-app.sh
ditto -c -k --sequesterRsrc --keepParent dist/CodexUsage.app "$zip_path"
release_validate_zip "$zip_path" "$version"

mkdir -p "$dmg_root"
ditto dist/CodexUsage.app "$dmg_root/CodexUsage.app"
ln -s /Applications "$dmg_root/Applications"
hdiutil create -quiet -volname "Codex Usage" -srcfolder "$dmg_root" -format UDZO "$dmg_path"

printf '%s' "$SPARKLE_PRIVATE_KEY" | "$generate_appcast" \
  --ed-key-file - \
  --download-url-prefix "https://github.com/hinson0/codex-usage/releases/download/$tag/" \
  --link "https://github.com/hinson0/codex-usage" \
  -o appcast.xml \
  "$updates_root"
```

Place only a copy of the versioned ZIP in `$updates_root`, so the appcast cannot
select the DMG or invent a delta. Copy the generated feed beside the DMG and ZIP.
Parse the enclosure’s `sparkle:edSignature` and verify the ZIP with
`sign_update --verify --ed-key-file -` using the same standard-input key path.
Generate `SHA256SUMS` over the
DMG, ZIP, and appcast in sorted filename order. Mount the DMG read-only at an
explicit temporary mount point, assert the app and `/Applications` symlink,
then detach it before exiting.

- [ ] **Step 4: Make artifact tests GREEN**

Run: `bash Tests/ReleaseArtifactsTests.sh`

Expected: all missing-secret and malformed-ZIP cases pass.

Run: `scripts/test.sh`

Expected: all Swift and shell tests pass.

- [ ] **Step 5: Export the key temporarily and exercise real packaging**

Export to a permission-restricted temporary file, load it without printing,
and remove the file through a trap:

```bash
key_file="$(mktemp "${TMPDIR:-/tmp}/codex-usage-sparkle-key.XXXXXX")"
chmod 600 "$key_file"
trap 'rm -f "$key_file"' EXIT
"$generate_keys" --account hinson0.codex-usage -x "$key_file"
SPARKLE_PRIVATE_KEY="$(<"$key_file")" scripts/package-release.sh
```

Expected: four release files appear under `dist/release`.

Run: `(cd dist/release && shasum -a 256 -c SHA256SUMS)`

Expected: the DMG, ZIP, and appcast each report `OK`.

Run: `xmllint --noout dist/release/appcast.xml`

Expected: exit status 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/release-lib.sh scripts/package-release.sh Tests/ReleaseArtifactsTests.sh scripts/test.sh
git commit -m "build: package signed release artifacts"
```

### Task 6: Safe GitHub Release workflow

**Files:**
- Create: `.github/workflows/release.yml`
- Create: `Tests/ReleaseWorkflowTests.sh`
- Modify: `scripts/test.sh`

**Interfaces:**
- Consumes: Task 5’s four `dist/release` outputs, secret `SPARKLE_PRIVATE_KEY`, repository variable `RELEASES_ENABLED`, and `GITHUB_TOKEN`.
- Produces: validation-only runs by default and immutable public `vVERSION` GitHub Releases when explicitly enabled.

- [ ] **Step 1: Write failing workflow contract tests**

Parse the workflow with Ruby’s YAML library and assert:

```ruby
workflow = YAML.safe_load(File.read(".github/workflows/release.yml"), aliases: true)
raise unless workflow.fetch("permissions") == {"contents" => "write"}
events = workflow.fetch("on")
raise unless events.key?("push") && events.key?("workflow_dispatch")
raise if events.key?("pull_request") || events.key?("pull_request_target")
publish = events.fetch("workflow_dispatch").fetch("inputs").fetch("publish")
raise unless publish.fetch("default") == false
```

Also assert the text contains `vars.RELEASES_ENABLED`, refuses an existing tag,
passes `SPARKLE_PRIVATE_KEY` only to the packaging step, creates a draft release,
and publishes it only after all assets were attached. Add this test to
`scripts/test.sh`.

- [ ] **Step 2: Run the workflow test and observe RED**

Run: `bash Tests/ReleaseWorkflowTests.sh`

Expected: FAIL because `.github/workflows/release.yml` is absent.

- [ ] **Step 3: Add validation and publication jobs**

Create one `macos-15` job with `fetch-depth: 0`, concurrency keyed by version,
and these ordered phases:

1. Checkout the exact commit.
2. Read and validate plist version/build with `release-lib.sh`.
3. Export `DEVELOPER_DIR="$(xcode-select -p)"` and run `scripts/test.sh`.
4. Build universal release artifacts with `SPARKLE_PRIVATE_KEY` scoped only to
   the packaging step.
5. Run packaging, code-sign, ZIP, DMG, appcast, and checksum verification.
6. Stop successfully when this is a validation run.
7. For publication, reject `refs/tags/vVERSION` when it belongs to a published
   or unrelated release. Permit only a same-version draft targeting the exact
   workflow commit, so an interrupted publication can resume without moving a
   tag.
8. Create or resume that draft GitHub Release at the exact commit, attach all
   four files without replacing any existing asset, generate notes, then switch
   the complete draft to published.
9. Download each public asset by immutable URL and verify `SHA256SUMS` again.

Determine publication with this expression:

```yaml
${{ (github.event_name == 'push' && vars.RELEASES_ENABLED == 'true') || (github.event_name == 'workflow_dispatch' && inputs.publish) }}
```

The push trigger is limited to `main` and `Packaging/Info.plist`. Manual runs
default to `publish: false`. Use only `actions/checkout` plus tools already on
the GitHub macOS runner; every `gh` step receives `GH_TOKEN: ${{ github.token }}`.

- [ ] **Step 4: Run workflow and complete tests locally**

Run: `bash Tests/ReleaseWorkflowTests.sh`

Expected: PASS.

Run: `scripts/test.sh`

Expected: all Swift, release-library, artifact, and workflow contract tests pass.

Run: `ruby -e 'require "yaml"; YAML.safe_load(File.read(".github/workflows/release.yml"), aliases: true)'`

Expected: exit status 0.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml Tests/ReleaseWorkflowTests.sh scripts/test.sh
git commit -m "ci: automate verified GitHub releases"
```

### Task 7: Version, documentation, secret bootstrap, and end-to-end release

**Files:**
- Modify: `Packaging/Info.plist`
- Modify: `Tests/PackagingTests.sh`
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: every earlier task, GitHub authentication for `hinson0/codex-usage`, and the Keychain account `hinson0.codex-usage`.
- Produces: version `0.4.1 (5)`, GitHub secret `SPARKLE_PRIVATE_KEY`, enabled future automatic releases, and public release `v0.4.1`.

- [ ] **Step 1: Make the packaging version assertion fail**

Change only `Tests/PackagingTests.sh` to expect short version `0.4.1` and build
number `5`.

Run: `Tests/PackagingTests.sh`

Expected: FAIL because the previous validation commit still contains `0.4.0 (4)`.

- [ ] **Step 2: Bump the single version source and update docs**

Change the two plist values to `0.4.1` and `5`. Update both READMEs with:

- a “Download” link to `releases/latest`;
- the DMG/manual and ZIP/Sparkle roles;
- the Gatekeeper limitation caused by ad-hoc signing;
- the localized “Check for Updates” behavior;
- the release asset names.

Add the release workflow and Sparkle key rule to `AGENTS.md`, including that a
published tag is immutable and that local/integration tests never publish.

- [ ] **Step 3: Run the complete local verification matrix**

Run: `scripts/test.sh`

Expected: all suites and shell tests pass.

Run: `CODEX_USAGE_RUN_INTEGRATION=1 scripts/test.sh --filter AppServerIntegrationTests`

Expected: one read-only integration test passes and no reset is consumed.

Run: `swift build -c release --product CodexUsage -Xswiftc -warnings-as-errors`

Expected: exit status 0 and no warning text.

Run: `Tests/PackagingTests.sh`

Expected: packaging checks pass for `0.4.1 (5)`.

Run: `codesign --verify --deep --strict dist/CodexUsage.app`

Expected: exit status 0.

Run: `scripts/smoke-test.sh`

Expected: the exact packaged executable remains alive for the smoke interval.

Export the Keychain key temporarily and run `scripts/package-release.sh`, then
verify checksums, appcast XML, ZIP contents, and DMG mount contents again.

- [ ] **Step 4: Commit the versioned release**

```bash
git add Packaging/Info.plist Tests/PackagingTests.sh README.md README.zh-CN.md AGENTS.md
git commit -m "feat: prepare automatic updates and releases"
```

- [ ] **Step 5: Save the Sparkle private key as a GitHub secret**

Use a new permission-restricted temporary export and send it through standard
input so it never appears in process arguments or logs:

```bash
key_file="$(mktemp "${TMPDIR:-/tmp}/codex-usage-sparkle-key.XXXXXX")"
chmod 600 "$key_file"
trap 'rm -f "$key_file"' EXIT
"$generate_keys" --account hinson0.codex-usage -x "$key_file"
gh secret set SPARKLE_PRIVATE_KEY --repo hinson0/codex-usage < "$key_file"
gh secret list --repo hinson0/codex-usage | grep -Fq SPARKLE_PRIVATE_KEY
```

Remove the exact temporary export after GitHub confirms the secret. Keep the
Keychain copy as the recovery source and never print either secret value.

- [ ] **Step 6: Push once in validation-only mode**

Confirm `RELEASES_ENABLED` is absent or not `true`, push `main`, then watch the
release workflow:

```bash
git push origin main
run_id="$(gh run list --workflow release.yml --limit 1 --repo hinson0/codex-usage --json databaseId --jq '.[0].databaseId')"
gh run watch "$run_id" --repo hinson0/codex-usage --exit-status
```

Expected: the workflow completes all tests and artifact checks, creates no tag,
and creates no GitHub Release.

- [ ] **Step 7: Enable publication and dispatch the first release**

After the validation run is green:

```bash
gh variable set RELEASES_ENABLED --body true --repo hinson0/codex-usage
gh workflow run release.yml --repo hinson0/codex-usage --ref main -f publish=true
run_id="$(gh run list --workflow release.yml --limit 1 --repo hinson0/codex-usage --json databaseId --jq '.[0].databaseId')"
gh run watch "$run_id" --repo hinson0/codex-usage --exit-status
```

Expected: tag `v0.4.1` and one published GitHub Release are created at the
verified `main` commit.

- [ ] **Step 8: Verify public downloads and stable update feed**

Run:

```bash
gh release view v0.4.1 --repo hinson0/codex-usage --json tagName,isDraft,isPrerelease,url,assets
curl -fL https://github.com/hinson0/codex-usage/releases/latest/download/appcast.xml -o /tmp/codex-usage-appcast.xml
xmllint --noout /tmp/codex-usage-appcast.xml
```

Expected: the release is neither draft nor prerelease, all four named assets
exist, the stable appcast URL resolves, and the enclosure URL references
`CodexUsage-v0.4.1-macOS.zip` under immutable tag `v0.4.1`.

- [ ] **Step 9: Final whole-change verification**

Run: `git status --short --branch`

Expected: clean `main` synchronized with `origin/main`.

Run: `open dist/CodexUsage.app`

Expected: the compact popover shows the localized update row, Light/Dark still
affects only the popover, and checking on `0.4.1` reports no newer update.
