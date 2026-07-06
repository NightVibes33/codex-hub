# CODEX HUB
# VERIFIED PRECISE BUILD PLAN
# Target: iOS 26 app built on GitHub Actions macOS 26 runner
# Output: unsigned .ipa artifact
# Status: Production roadmap + CI packaging plan
# Important: Unsigned IPA is NOT installable on normal stock iPhones and is NOT valid for TestFlight/App Store.

============================================================
0. HARD TRUTH / DECISION GATES
============================================================

Before coding the full app, validate these gates:

GATE 1:
Confirm which parts of OpenAI support are official for this product.

Verified supported:
- Official OpenAI-supported ChatGPT sign-in for Codex clients.
- Official OpenAI-supported API-key authentication for Codex and API workflows.
- Official enterprise access-token support for Codex local workflows in ChatGPT Enterprise.

Still unverified here for a standalone third-party iOS dashboard app:
- Official public consumer ChatGPT/Codex quota endpoint.
- Official public consumer ChatGPT/Codex reset-timer endpoint.
- Official public consumer ChatGPT/Codex usage-history endpoint.

Not allowed for production/App Store:
- Scraping ChatGPT web pages.
- Stealing or copying browser cookies.
- Asking users to paste private refresh tokens.
- Reverse-engineering private mobile/web endpoints.
- Storing raw ChatGPT session cookies.
- Using private APIs that can break or violate terms.

If the consumer usage-data part of GATE 1 fails:
The product must pivot to one of these supported scopes:
- ChatGPT-authenticated Codex client without quota dashboard claims.
- API-key usage tracker only.
- Manual usage dashboard where the user enters limits manually.
- Companion app that reads data exported from a trusted desktop/CLI tool.
- Enterprise-only dashboard using official Enterprise interfaces if available.
- Notification/widget shell with user-provided usage/reset values.

GATE 2:
Confirm whether the first shipped target is:
- iPhone/iPad only
OR
- iPhone/iPad + Widget extension
OR
- iPhone/iPad + Widget + Watch app

Recommended build order:
1. iPhone/iPad app only.
2. Add widgets after base app CI is green.
3. Add Watch app after widgets are green.
4. Add macOS target later.
5. Add Vision Pro later.

Reason:
Unsigned archives with widgets/watch/extensions are more fragile in CI because every nested target has signing and entitlement settings.

============================================================
1. VERIFIED GITHUB RUNNER TARGET
============================================================

Use:
`runs-on: macos-26`

Do not use:
`macos-latest`

Reason:
`macos-latest` can move over time and break deterministic builds.

Use explicit Xcode selection:
Preferred current pin:
- `/Applications/Xcode_26.6.app`

Fallback:
- Fail fast if that path does not exist.
- Print all installed Xcode versions.
- Do not silently continue with unknown Xcode.

Current expected runner facts as of 2026-07-06:
- macOS 26 runner exists.
- Xcode 26.5 is listed as default on the image.
- Xcode 26.6 is listed as installed.
- Installed SDKs should be verified from the current runner image readme and build logs, not assumed beyond the published image inventory.

============================================================
2. LOCAL PROJECT REQUIREMENTS BEFORE CI
============================================================

The repository must contain exactly one buildable Xcode project or workspace.

Supported options:

Option A:
`CodexHub.xcodeproj`

Option B:
`CodexHub.xcworkspace`

Use workspace if:
- CocoaPods is used.
- The project requires a generated workspace.
- Multiple projects are combined.

Use project if:
- Native Xcode project.
- Swift Package Manager only.
- No CocoaPods workspace.

Required files once the app exists:

```text
CodexHub/
  CodexHub.xcodeproj
  CodexHub/
    CodexHubApp.swift
    Info.plist or generated Info settings
    Assets.xcassets
```

Required Xcode setup:
- Scheme name must be `CodexHub`.
- Scheme must be shared.
- App target must support generic iOS device archive.
- Bundle identifier must be valid.
- App icon must be valid.
- Build configuration `Release` must exist.
- Base app must build locally before CI is enabled.

Shared scheme path should exist:
`CodexHub.xcodeproj/xcshareddata/xcschemes/CodexHub.xcscheme`

If workspace:
`CodexHub.xcworkspace/xcshareddata/xcschemes/CodexHub.xcscheme`

============================================================
3. REQUIRED TARGET SETTINGS
============================================================

Main iOS app target:
- `PRODUCT_NAME = CodexHub`
- `PRODUCT_BUNDLE_IDENTIFIER = your.real.bundle.id`
- `IPHONEOS_DEPLOYMENT_TARGET = 26.0` only if you intentionally require iOS 26+
- `SUPPORTED_PLATFORMS` includes `iphoneos`
- `SKIP_INSTALL = NO` for app target
- `CODE_SIGN_STYLE` can be Automatic locally, but CI overrides signing off
- App Groups only if widgets are already added
- Push Notifications only if implemented
- iCloud only if implemented
- Background Modes only if implemented

Framework/library targets:
- `SKIP_INSTALL = YES`

Do NOT globally force `SKIP_INSTALL=NO` in CI.

============================================================
4. UNSIGNED IPA LIMITATIONS
============================================================

The unsigned IPA produced by this workflow:
- Is only a zipped Payload folder.
- Contains `Payload/CodexHub.app`.
- Is not signed.
- Is not installable on a normal iPhone through standard Apple distribution.
- Is not valid for TestFlight.
- Is not valid for App Store.
- Is useful as a CI build artifact.
- Can be passed to a later signing/distribution system.

============================================================
5. EXACT GITHUB ACTIONS WORKFLOW STATUS
============================================================

The workflow design is valid, but it should remain an example until the repo contains a real Xcode project and shared scheme.

For that reason, this repo stores the workflow as:

`docs/unsigned-ios-build.yml.example`

Only promote it to:

`.github/workflows/unsigned-ios-build.yml`

after the project exists and local archive assumptions are real.

============================================================
6. EXPECTED SUCCESS RESULT
============================================================

Once a real project exists, a successful run must produce:

`build/CodexHub-unsigned.ipa`

The IPA must contain:

`Payload/CodexHub.app/`

The GitHub artifact should be named:

`CodexHub-unsigned-ipa`

============================================================
7. COMMON FAILURES AND EXACT FIXES
============================================================

Failure:
Scheme not found.

Fix:
Open Xcode:
`Product > Scheme > Manage Schemes > Shared`

Commit:
`CodexHub.xcodeproj/xcshareddata/xcschemes/CodexHub.xcscheme`

Failure:
No `.app` found in archive.

Fix:
Check app target:
`SKIP_INSTALL = NO`

Check framework/library targets:
`SKIP_INSTALL = YES`

Do not globally pass `SKIP_INSTALL=NO` in the workflow.

Failure:
Signing error.

Fix:
Make sure workflow passes:
- `CODE_SIGNING_ALLOWED=NO`
- `CODE_SIGNING_REQUIRED=NO`
- `CODE_SIGN_IDENTITY=`
- `CODE_SIGN_STYLE=Manual`
- `DEVELOPMENT_TEAM=`
- `PROVISIONING_PROFILE_SPECIFIER=`
- `AD_HOC_CODE_SIGNING_ALLOWED=NO`

Failure:
Xcode path missing.

Fix:
Read the workflow log section:
`Available Xcode apps`

Then update:
`XCODE_APP: /Applications/Xcode_26.x.app`

============================================================
8. PRECISE BUILD ORDER
============================================================

PHASE 1:
Create a real SwiftUI iOS app on macOS with Xcode.

Acceptance:
- `xcodebuild` can list scheme.
- Local Release build succeeds.

PHASE 2:
Move the example workflow into `.github/workflows/unsigned-ios-build.yml`.

Acceptance:
- unsigned IPA uploads as an artifact.

PHASE 3:
Add local app shell.

Acceptance:
- App builds in CI.
- App opens locally.

PHASE 4:
Validate OpenAI-supported data access beyond login.

Acceptance:
- Written proof for any quota/reset/usage endpoint claim.
- If unsupported, product pivots to API-key/manual/enterprise mode.

============================================================
9. FINAL VERDICT
============================================================

Use this corrected plan:

- The CI runner and unsigned IPA plan are viable.
- ChatGPT login for Codex clients is officially supported.
- Consumer quota/reset/usage data access is not verified here and must not be assumed.
