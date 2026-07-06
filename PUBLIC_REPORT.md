# Public Report: CODEX HUB

Date: 2026-07-06

## Executive summary

The original plan was mostly right about the unsigned iOS packaging path and the need to pin the GitHub-hosted macOS runner and Xcode version. The main correction is in `GATE 1`.

Official OpenAI Codex docs now support ChatGPT sign-in for Codex clients. That removes the earlier claim that direct ChatGPT login was inherently unsupported.

The unverified part is not login itself. The unverified part is whether a standalone third-party iOS dashboard app has an official public interface for reading consumer ChatGPT/Codex quota, reset, and usage data.

## Final verdict

- `runs-on: macos-26` is a valid target.
- Explicit Xcode pinning is still the right approach.
- The unsigned IPA packaging concept is valid.
- ChatGPT sign-in for a Codex client is supported by official OpenAI docs.
- Consumer quota/reset/usage endpoints for this product are still not verified in public official docs.

## Product implication

The product can safely plan around:

- official ChatGPT sign-in for Codex-client style authentication
- API-key usage mode
- manual usage/reset tracking
- enterprise-only reporting when a supported customer-approved surface exists

The product should not yet promise:

- remaining consumer Codex quota
- consumer reset countdown
- consumer usage history pulled from an official public dashboard API

## CI implication

Do not publish an active GitHub Actions iOS build workflow until the repo contains:

- a real `CodexHub.xcodeproj` or `CodexHub.xcworkspace`
- a shared `CodexHub` scheme
- a buildable Release archive path

Without that, public CI would fail deterministically and add noise.

## Sources

- <https://developers.openai.com/codex/auth>
- <https://developers.openai.com/codex/auth/ci-cd-auth>
- <https://developers.openai.com/codex/enterprise/access-tokens>
- <https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md>
