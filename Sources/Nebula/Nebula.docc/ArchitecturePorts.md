# Ports & DTO Contract

The Interface Adapters markers: input ports, output ports, and the DTO contract.

## Overview

A **port** is the seam an outer layer implements. Nebula owns the inner port; the app supplies the adapter. All three markers are bare `Sendable` protocols — they carry no requirements in v1, they exist so a use case can constrain its input/output to "a value Nebula understands" and so a presenter can be named.

- ``NebulaInputPort`` — marker for a use case's input (a request model / command).
- ``NebulaOutputPort`` — marker for a presenter. Nebula defines **no** presenter — the app (or Cosmos) supplies a `@MainActor` (or `Mutex`-guarded) type conforming to this marker.
- ``NebulaDTO`` — marker for a Data Transfer Object crossing the boundary to Frameworks & Drivers. DTOs never carry entities. The marker is bare in v1; conforming DTOs are recommended to also conform to `Equatable` for test ergonomics.

## Topics

### Markers
- ``NebulaInputPort``
- ``NebulaOutputPort``
- ``NebulaDTO``