# Permissions

A `Sendable` permission-status value enum — the union superset of Apple's per-framework status vocabularies, hoisted ahead of the unified request port.

## Overview

There is no unified Apple permissions API: each framework (UserNotifications, AVFoundation, CoreLocation, Photos, App Tracking Transparency) ships its **own** status enum with its **own** vocabulary (`AVAuthorizationStatus`, `CLAuthorizationStatus`, `PHAuthorizationStatus`, `ATTrackingManagerAuthorizationStatus`, `UNAuthorizationStatus`). A Nebula request port that adapts each framework's request flow is app-level glue and is **deferred** — only the status **value** is hoisted now, so callers speak one status type across frameworks.

- ``NebulaPermissionStatus`` — a `Sendable`, `Equatable`, `Hashable`, `CaseIterable` enum: the union superset (`notDetermined` / `restricted` / `denied` / `authorized` / `provisional` / `ephemeral` / `authorizedAlways` / `authorizedWhenInUse`). It is available on all five platforms with no gates.
- ``NebulaPermissionStatus/init(_:)`` — the `UNAuthorizationStatus` bridge, the one status source shipped in this wave. `.notDetermined` / `.denied` / `.authorized` / `.provisional` map 1:1; `.ephemeral` is iOS-only (`API_UNAVAILABLE(macos, watchos, tvos)`) so its bridge arm is `#if os(iOS)`; statuses with no Nebula equivalent return `nil`.

When the deferred `NebulaPermissions` request port ships, this article grows: AV / CoreLocation / Photos / ATT status bridges join the `UNAuthorizationStatus` bridge, each mapping its framework's status vocabulary into the one superset.

## Topics

### Status value
- ``NebulaPermissionStatus``
- ``NebulaPermissionStatus/init(_:)``