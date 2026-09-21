# Automated Releases and Sparkle Updates Design

## Summary

Codex Usage will publish installable macOS artifacts automatically whenever a
new application version reaches `main`. A GitHub Actions workflow will create
the matching Git tag and GitHub Release, then attach a DMG for manual installs,
a ZIP for Sparkle updates, checksums, and an appcast feed.

The application will integrate Sparkle 2 and expose a localized “Check for
Updates” action in the existing popover. Sparkle will check the stable GitHub
feed on its normal schedule and present its standard confirmation UI before an
update is installed. Updates will be authenticated with a dedicated EdDSA key.

## Goals

- Turn a version change on `main` into a tagged GitHub Release without a manual
  packaging step.
- Offer a polished DMG for people downloading the app from GitHub.
- Offer a ZIP and stable appcast URL for secure in-app updates.
- Keep the Sparkle private key out of Git history and workflow logs.
- Preserve the current macOS 13 minimum, compact popover, bilingual menu text,
  and no-Dock-icon behavior.
- Keep local builds and tests usable without release secrets.

## Non-goals

- Developer ID signing, Apple notarization, or Mac App Store distribution.
- Silent forced updates that remove the user’s choice to install.
- Beta channels, phased rollouts, delta updates, or downgrade support.
- Replacing the existing semantic-version policy in `AGENTS.md`.
- Publishing a release from pull requests, forks, or untrusted workflow input.

## Release contract

`Packaging/Info.plist` remains the only source of truth for both
`CFBundleShortVersionString` and `CFBundleVersion`. A release workflow runs on a
push to `main` that changes the plist, with `workflow_dispatch` available for a
controlled retry.

For short version `0.3.0`, the workflow targets tag `v0.3.0` and produces:

- `CodexUsage-v0.3.0-macOS.dmg`
- `CodexUsage-v0.3.0-macOS.zip`
- `SHA256SUMS`
- `appcast.xml`

GitHub continues to add its generated source archives automatically. The
workflow validates the semantic version, runs the complete test suite, builds a
universal `arm64` + `x86_64` application, verifies the bundle, and packages the
four assets before creating any public release state.

If the tag already exists, a normal push fails with a clear duplicate-version
error instead of replacing an immutable published release. A manually
dispatched retry may update only a draft created by the same version; it must
not overwrite a published release or move an existing tag.

The release is created with GitHub’s automatically generated notes and points
at the exact `main` commit that passed verification. The workflow receives only
`contents: write` permission and uses the repository-scoped `GITHUB_TOKEN`.

## Distribution packaging

The existing build script will learn how to embed and sign
`Sparkle.framework` while retaining a convenient local-build mode. It will
preserve framework symlinks, sign nested Sparkle components before the outer
application, and verify the final bundle with `codesign --deep --strict`.

The release ZIP contains only `CodexUsage.app`, which avoids app translocation
problems and is the archive Sparkle downloads. The DMG contains
`CodexUsage.app` plus an `/Applications` symlink and uses a compressed,
read-only image. Both artifacts contain the same verified application bundle.

Until Developer ID credentials and notarization are added, the bundle remains
ad-hoc signed. This means a first-time manual install can still trigger
Gatekeeper. The DMG improves installation ergonomics but does not bypass that
security warning.

## Sparkle integration

The Swift package will pin Sparkle 2 to a reviewed release compatible with the
project’s deployment target. The application owns one
`SPUStandardUpdaterController` for its full process lifetime. The updater starts
after app launch and reads static configuration from `Info.plist`:

- `SUFeedURL` points to
  `https://github.com/hinson0/codex-usage/releases/latest/download/appcast.xml`.
- `SUPublicEDKey` contains the public half of the dedicated update-signing key.
- automatic checks are enabled;
- automatic unattended installation is disabled;
- update archives are verified before extraction.

The popover action calls Sparkle’s interactive update check and is disabled
while Sparkle cannot start another check. Its row label is provided by the
existing `LocalizationCatalog` in English and Simplified Chinese. Sparkle’s own
standard dialogs use the framework’s macOS-selected localization.

The current `0.2.0` build has no updater, so `0.3.0` is the first manually
installed Sparkle-enabled version. Releases after `0.3.0` can update it through
the appcast.

## Appcast and signing keys

A one-time bootstrap uses Sparkle’s `generate_keys` tool locally:

1. Generate a dedicated EdDSA keypair.
2. Put only the public key in `Packaging/Info.plist`.
3. Store the exported private key as the repository Actions secret
   `SPARKLE_PRIVATE_KEY`.
4. Delete the temporary plaintext export after GitHub confirms the secret.

The workflow reconstructs the private key only in a permission-restricted
temporary file, passes it to Sparkle’s official signing tools, and removes it
on exit. It must mask derived sensitive values and must never echo the secret.
The workflow stops before tagging if the secret is missing or an archive cannot
be signed.

`appcast.xml` contains the release build number, display version, minimum macOS
version, immutable versioned ZIP URL, archive size, and EdDSA signature. The
stable `releases/latest/download/appcast.xml` URL redirects clients to the feed
attached to the latest non-prerelease GitHub Release.

## Failure handling and idempotency

- Test, build, signing, checksum, appcast, bundle verification, ZIP validation,
  and DMG mounting checks all finish before tag or Release creation.
- Temporary key material and packaging directories are removed by shell traps.
- A failed pre-publication run creates no tag and no Release.
- A failure during GitHub publication leaves a draft Release when possible;
  the controlled retry path may complete that draft without moving a tag.
- Existing published releases and their assets are never overwritten.
- The application treats update-check failures as Sparkle UI errors; Codex
  usage refresh and reset redemption continue independently.

## Testing and verification

### Unit and package tests

- Localization keys exist in both languages and the new row changes immediately
  with the selected app language.
- The updater action is enabled and disabled from an injected updater state,
  allowing UI-facing behavior to be tested without a network request.
- Packaging tests assert the embedded framework, Sparkle plist keys, public key,
  rpaths, version metadata, and nested code signatures.
- Release-script tests use temporary fixtures to validate version parsing,
  artifact names, duplicate-tag refusal, checksum format, and appcast fields.

### Local verification

- `scripts/test.sh`
- read-only App Server integration test
- warnings-as-errors release build
- application packaging test
- strict code-sign verification
- smoke launch
- ZIP extraction and bundle verification
- DMG mount, content, and detach verification
- appcast XML parse and signature verification against the packaged public key

### Workflow verification

Before the first public release, the workflow runs through `workflow_dispatch`
in a non-publishing validation mode. After merge, the `0.3.0` plist change
triggers the real release, and the published assets, checksums, stable appcast
URL, and Sparkle probe are checked from their public URLs.

## Versioning

This is backward-compatible user-visible functionality, so implementation bumps
`CFBundleShortVersionString` from `0.2.0` to `0.3.0` and increments
`CFBundleVersion` from `2` to `3`. Later release-pipeline or updater bug fixes
increment the patch version and build number under the repository’s existing
rules.
