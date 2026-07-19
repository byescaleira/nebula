# Standardize

Nebula's standardize module is a thin `Sendable` facade over Foundation's modern `FormatStyle` family, pre-configuring each accessor with a shared locale, time zone, and calendar. It is the third of Nebula's four cross-cutting configuration structs.

## Overview

``NebulaStandards`` is a `Sendable` value struct holding ``NebulaStandards/locale``, ``NebulaStandards/timeZone``, and ``NebulaStandards/calendar``, and exposing typed accessors that return Apple's real `FormatStyle` values, **pre-configured** with those three components. It is the only one of the four configuration structs **without a `@Sendable` handler**: formatting is stateless, so there is no fan-out path and no `Equatable`-breaking closure.

### Thin facade, not a re-wrap

Each accessor returns a fresh `Sendable` `FormatStyle` — Nebula does **not** hide formatting behind an opaque `format(_:)`. Callers keep the full Apple API — `.attributed`, `.precision`, `.grouping`, `.notation`, `.locale`, and so on — because Nebula returns the real Apple type. Use the convenience entry points (``NebulaStandards/attributed(_:format:)``, ``NebulaStandards/iso8601String(for:includingFractionalSeconds:)``, and the overloaded `string(_:format:)`) only when you want a one-shot `String`.

The locale-independent presets pinned to `en_US_POSIX` + GMT (for logs, persistence, snapshots) live in the DateTime extensions — see ``NebulaDateFormat`` and ``NebulaDurationFormat``. ``NebulaStandards`` carries the caller's locale for UI/presentation.

### Accessors

Date and time: ``NebulaStandards/date`` (a `Date.FormatStyle` mirroring `.dateTime` — abbreviated date + standard time, baked with locale/calendar/timeZone via the `init` because `.timeZone(_:)` takes a display-format enum and there is no `.calendar(_:)` builder), ``NebulaStandards/iso8601`` (a `Date.ISO8601FormatStyle` with `Z` for GMT and `±HH:MM` for any other zone), and ``NebulaStandards/date(verbatim:)`` (a `Date.VerbatimFormatStyle` from a symbol-interpolation `Date.FormatString`).

Number: ``NebulaStandards/decimal``, ``NebulaStandards/integer()``, ``NebulaStandards/double()``, ``NebulaStandards/percent()``, ``NebulaStandards/currency(code:)``, ``NebulaStandards/byteCount(style:)``.

List and name: ``NebulaStandards/list(memberStyle:type:width:)`` (defaults `type` to `.and` and `width` to `.standard`, because the Swift overload requires `type`), and ``NebulaStandards/name`` (`PersonNameComponents.FormatStyle`, medium).

Measurement and duration: ``NebulaStandards/measurement(width:usage:numberFormatStyle:)`` (no `unit` parameter — the unit is implied by the `Measurement<U>` value), ``NebulaStandards/durationUnits(allowed:width:maximumUnitCount:)``, and ``NebulaStandards/durationTime(pattern:)``.

URL: ``NebulaStandards/url`` (a `URL.FormatStyle`; `URL.FormatStyle` has no locale in its `init`, but the generic `FormatStyle.locale(_:)` extension applies).

### At-floor DateComponents accessors

`DateComponents.formatted(_:)` and `DateComponents.ISO8601FormatStyle` are **at-floor** (OS 26 / Nebula 26). The two `DateComponents` convenience accessors on ``NebulaStandards`` (`string(_:format:)` and the no-format `string(_:)` defaulting to `DateComponents.ISO8601FormatStyle.iso8601`) are gated explicitly with `@available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)`. Everything else in the module is below the `.v26` floor.

### Builders and process-wide access

Override individual components with ``NebulaStandards/withLocale(_:)``, ``NebulaStandards/withTimeZone(_:)``, and ``NebulaStandards/withCalendar(_:)``. All three default to `.autoupdatingCurrent`; pin them for deterministic, locale-independent output. For process-wide ergonomics alongside explicit-parameter DI, ``NebulaStandardsConfig`` holds the current configuration in a `Mutex<NebulaStandards>` (`Synchronization`; below the `.v26` floor).

```swift
let standards = NebulaStandards.default
    .withLocale(Locale(identifier: "pt-BR"))
    .withTimeZone(.gmt)

// Typed accessor — keep the full Apple API.
let style = standards.date.attributed    // AttributedString, locale = pt-BR, GMT
let price = 1234.56.formatted(standards.currency(code: "BRL"))

// One-shot String convenience.
let iso = standards.iso8601String(for: Date())   // 2026-07-18T12:00:00Z
```

## Topics

### Configuration
- ``NebulaStandards``
- ``NebulaStandardsConfig``

### Builders
- ``NebulaStandards/withLocale(_:)``
- ``NebulaStandards/withTimeZone(_:)``
- ``NebulaStandards/withCalendar(_:)``

### Date and time
- ``NebulaStandards/date``
- ``NebulaStandards/iso8601``
- ``NebulaStandards/date(verbatim:)``
- ``NebulaStandards/iso8601String(for:includingFractionalSeconds:)``

### Number
- ``NebulaStandards/decimal``
- ``NebulaStandards/integer()``
- ``NebulaStandards/double()``
- ``NebulaStandards/percent()``
- ``NebulaStandards/currency(code:)``
- ``NebulaStandards/byteCount(style:)``

### List and name
- ``NebulaStandards/list(memberStyle:type:width:)``
- ``NebulaStandards/name``

### Measurement and duration
- ``NebulaStandards/measurement(width:usage:numberFormatStyle:)``
- ``NebulaStandards/durationUnits(allowed:width:maximumUnitCount:)``
- ``NebulaStandards/durationTime(pattern:)``

### URL
- ``NebulaStandards/url``

### Convenience
- `string(_:format:)` — one-shot `String` from any value (overloaded: generic `string<T>(_:format:)` and the at-floor `string(_ components: DateComponents, format:)` / `string(_ components: DateComponents)`)
- ``NebulaStandards/attributed(_:format:)``