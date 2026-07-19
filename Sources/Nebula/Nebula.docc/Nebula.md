# ``Nebula``

> A clean-room Swift foundation/architecture library for iOS, macOS, tvOS, watchOS, and visionOS 26.

Nebula is a Swift foundation/architecture SwiftPM library — the sibling of [Cosmos](https://github.com/byescaleira/cosmos), the SwiftUI design system. It is distributed as a single SwiftPM module — one `import`, one target, no third-party dependencies. Nebula wraps Apple-native primitives (`os.Logger`, `FormatStyle`, `Measurement`, `Regex`, `AttributedString`, `Duration`/`Clock`, `Mutex`/`Atomic`) so every consumer reads the same Sendable contracts for logging, error reporting, formatting, and measurement.

## Topics

### Configuration contracts

Four `Sendable` value-type configuration structs flow through explicit injection (there is no SwiftUI environment):

- ``NebulaLogConfiguration`` — logging behavior.
- ``NebulaErrorConfiguration`` — error reporting.
- ``NebulaStandards`` — formatting policy.
- ``NebulaMeasureConfiguration`` — measurement.

### Articles

- <doc:Logging>
- <doc:Errors>
- <doc:Extensions>
- <doc:Standardize>
- <doc:Measure>