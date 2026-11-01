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

- [ ] Add Swift package regression tests for access policy, AI request/response contracts, and three-way planner merge; run on macOS CI.
- [ ] Implement verified sessions, resend/refresh flow, UID-keyed workspace lifecycle, token-authenticated AI, and conflict-safe planner mutations. Keep profile writes nested and clear state on account changes.
- [ ] Add App Check initialization and macOS dependency setup; allow the explicit native app identity in the backend and test that unlisted apps are rejected.
- [ ] Review the diff, run available checks, inspect macOS CI, and open draft PRs with exact remaining device/configuration requirements.

## Execution ledger

Ruling: existing go-for-it approval covers implementation and draft PRs; proceed inline without another approval round.
Ruling: shell network cannot resolve GitHub, so read and publish through the GitHub connector. Local files are a source mirror; branches are isolated remotely.
Ruling: Swift/Xcode is absent on this Windows host. Use macOS GitHub Actions for executable Swift tests and dependency setup. Do not report local iOS build success.
