# iOS Integration Implementation Plan

> Execute inline with superpowers:executing-plans. Track actual checks and limitations here.

**Goal:** Connect the existing iOS app safely to current Kairos accounts, AI and planner data.
**Architecture:** Small Foundation-only access, AI request and planner-merge helpers shared by app source and a Swift package test target. Firebase adapters retain SDK concerns.
**Tech Stack:** SwiftUI, Firebase Auth/Firestore/App Check, Swift Testing/XCTest, existing Cloudflare JavaScript.
**Spec:** docs/superpowers/specs/2026-11-01-ios-integration-design.md

## Global Constraints

Preserve the existing UI and collections. No billing changes or deployment. Never bypass App Check. Keep new source in synchronized folders. Run dependency setup with Swift on macOS, not text edits to pbxproj.

## Review Focus

Unverified account restoration, identity changes during requests, unknown nested task fields, competing edits/deletion, missing attestation and quota errors.

## Tasks

- [x] Add Swift package regression tests for access policy, AI request/response contracts, and three-way planner merge; run on macOS CI.
- [x] Implement verified sessions, resend/refresh flow, UID-keyed workspace lifecycle, token-authenticated AI, and conflict-safe planner mutations. Keep profile writes nested and clear state on account changes.
- [x] Add App Check initialization and macOS dependency setup; allow the explicit native app identity in the backend and test that unlisted apps are rejected.
- [x] Review the diff, run available checks, inspect macOS CI, and open PRs with exact remaining device/configuration requirements.

## Execution ledger

Ruling: existing go-for-it approval covers implementation and draft PRs; proceed inline without another approval round.
Ruling: shell network cannot resolve GitHub, so read and publish through the GitHub connector. Local files are a source mirror; branches are isolated remotely.
Ruling: Swift/Xcode is absent on this Windows host. Use macOS GitHub Actions for executable Swift tests and dependency setup. Do not report local iOS build success.

Verification: initial tests failed on missing integration contracts; all 10 Swift tests now pass on macOS. Backend signed-token regression failed on the original verifier, then passed after implementation; the full backend suite passed (1,732 passed, one skipped), as did lint/type checking and the existing Schedule build.

Review: independent review caught enriched-item deletion conflicts, account-scoped timer leakage, statistics lost updates and achievement timing. Retain the complete raw baseline, reset the shared timer on UID changes, update progress in Firestore transactions and check achievements after the authoritative profile snapshot publishes.

Build: executed Firebase dependency linking with Swift/XcodeProj on macOS and committed its generated project. Preserved the existing SDK requirement. Removed the temporary setup tool afterward. The compiler found an async Firebase API name mismatch and an Observation listener-handle annotation issue; corrected both. Final macOS CI passed all 10 Swift tests and the unsigned arm64 simulator app/widget build: https://github.com/MRHWCKRR/Kairos-IOS/actions/runs/41287306677.

Remaining release prerequisites: Firebase App Attest registration, Apple signing/provisioning, deployment of the companion backend PR, and signed-iPhone flows in docs/ios-integration-setup.md. No PR was merged and no production deployment was performed.
