# CODEX HUB

Public repo for the corrected `CODEX HUB` iOS build plan.

## Scope

This repository publishes a verified build and product plan for a future iOS app:

- Target CI runner: `macos-26`
- Target output: unsigned `.ipa` artifact
- Product state: roadmap and CI packaging plan

## Important constraints

- An unsigned IPA is not installable on normal stock iPhones.
- An unsigned IPA is not valid for TestFlight or the App Store.
- A real `.xcodeproj` or `.xcworkspace` is required before enabling build CI.

## Gate 1 correction

As of `2026-07-06`, official OpenAI Codex docs do support ChatGPT sign-in for Codex clients.

What remains unverified in public docs is narrower:

- a supported consumer ChatGPT/Codex quota endpoint
- a supported consumer ChatGPT/Codex reset-timer endpoint
- a supported consumer ChatGPT/Codex usage-history endpoint for a standalone third-party dashboard app

So the safe conclusion is:

- ChatGPT login for a Codex client: supported
- consumer quota/reset dashboard access: not yet verified here

## Files

- [VERIFIED_PRECISE_BUILD_PLAN.md](./VERIFIED_PRECISE_BUILD_PLAN.md)
- [PUBLIC_REPORT.md](./PUBLIC_REPORT.md)
- [docs/unsigned-ios-build.yml.example](./docs/unsigned-ios-build.yml.example)

## Sources

- OpenAI Codex authentication docs: <https://developers.openai.com/codex/auth>
- OpenAI Codex CI/CD auth guidance: <https://developers.openai.com/codex/auth/ci-cd-auth>
- OpenAI Codex enterprise access tokens: <https://developers.openai.com/codex/enterprise/access-tokens>
- GitHub Actions macOS 26 arm64 image: <https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md>
