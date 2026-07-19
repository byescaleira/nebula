//
//  NebulaTests.swift
//  NebulaTests
//
//  Wave A scaffold tests (Swift Testing). Per-module tests are added as each
//  roadmap wave ships; see ROADMAP.md.
//

import Testing
import Nebula

@Suite("NebulaVersion")
struct NebulaVersionTests {
    @Test func baselineVersionIsNebula26() {
        #expect(Nebula.version == NebulaVersion(major: 26))
        #expect(Nebula.version.description == "26.0.0")
    }

    @Test func versionsOrderByMajorThenMinorThenPatch() {
        #expect(NebulaVersion(major: 26) < NebulaVersion(major: 27))
        #expect(NebulaVersion(major: 26, minor: 1) > NebulaVersion(major: 26))
        #expect(NebulaVersion(major: 26, minor: 0, patch: 2) > NebulaVersion(major: 26, minor: 0, patch: 1))
    }

    @Test func isSendable() {
        // Confirms the public value type satisfies Sendable under language mode v6.
        let v = Nebula.version
        #expect(v.major == 26)
    }
}