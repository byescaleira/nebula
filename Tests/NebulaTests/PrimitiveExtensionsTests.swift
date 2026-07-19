//
//  PrimitiveExtensionsTests.swift
//  NebulaTests
//
//  Wave D — primitive extension tests (Swift Testing).
//

import Testing
import Foundation
import Nebula

@Suite("Comparable.clamped")
struct ComparableClampedTests {
    @Test func clampsIntIntoRange() {
        #expect(Int(5).clamped(to: 0...10) == 5)
        #expect(Int(-1).clamped(to: 0...10) == 0)
        #expect(Int(99).clamped(to: 0...10) == 10)
        #expect(Int(0).clamped(to: 0...10) == 0)
        #expect(Int(10).clamped(to: 0...10) == 10)
    }

    @Test func clampsStringIntoRange() {
        #expect("a".clamped(to: "m"..."z") == "m")
        #expect("r".clamped(to: "m"..."z") == "r")
        #expect("zzz".clamped(to: "m"..."z") == "z")
    }
}

@Suite("BinaryInteger gap-fillers")
struct IntegerNebulaTests {
    @Test func isEvenIsOdd() {
        #expect(Int(4).isEven)
        #expect(!Int(4).isOdd)
        #expect(Int(7).isOdd)
        #expect(!Int(7).isEven)
        #expect(Int(0).isEven)
        #expect(Int(0).isEven == true)
    }

    @Test func timesRunsBodyNTimes() throws {
        var counter = 0
        Int(3).times { counter += 1 }
        #expect(counter == 3)

        // zero times
        Int(0).times { counter += 1 }
        #expect(counter == 3)
    }

    @Test func timesRethrows() throws {
        enum Boom: Error { case it }
        #expect(throws: Boom.it) {
            try Int(2).times { throw Boom.it }
        }
    }

    @Test func timesWorksOnOtherIntegers() {
        var sum = 0
        UInt(4).times { sum += 1 }
        #expect(sum == 4)
    }
}

@Suite("Optional gap-fillers")
struct OptionalNebulaTests {
    @Test func orReturnsWrappedOrFallback() {
        let some: Int? = 5
        let none: Int? = nil
        #expect(some.or(0) == 5)
        #expect(none.or(0) == 0)
    }

    @Test func orEvaluatesFallbackLazily() {
        var sideEffect = 0
        func inc() -> Int { sideEffect += 1; return 0 }
        // `inc()` is the autoclosure expression — wrapped, not invoked unless
        // the fallback is needed.
        let some: Int? = 5
        _ = some.or(inc())
        #expect(sideEffect == 0) // fallback not evaluated when wrapped
        let none: Int? = nil
        _ = none.or(inc())
        #expect(sideEffect == 1)
    }

    @Test func orThrowReturnsWrapped() throws {
        let some: Int? = 5
        #expect(try some.orThrow() == 5)
    }

    @Test func orThrowThrowsNebulaNilErrorOnNil() {
        let none: Int? = nil
        #expect(throws: NebulaNilError.self) {
            _ = try none.orThrow()
        }
    }

    @Test func orThrowThrowsCustomError() {
        struct CustomErr: Error {}
        let none: Int? = nil
        #expect(throws: CustomErr.self) {
            _ = try none.orThrow(CustomErr())
        }
    }

    @Test func isNilOrEmpty() {
        let none: [Int]? = nil
        let empty: [Int]? = []
        let some: [Int]? = [1]
        #expect(none.isNilOrEmpty)
        #expect(empty.isNilOrEmpty)
        #expect(!some.isNilOrEmpty)
        // String is a Collection.
        let noneStr: String? = nil
        let emptyStr: String? = ""
        let someStr: String? = "x"
        #expect(noneStr.isNilOrEmpty)
        #expect(emptyStr.isNilOrEmpty)
        #expect(!someStr.isNilOrEmpty)
    }
}

@Suite("UUID gap-fillers")
struct UUIDNebulaTests {
    @Test func shortStringIs8HexChars() {
        let id = UUID()
        #expect(id.shortString.count == 8)
        #expect(id.uuidString.hasPrefix(id.shortString))
    }

    @Test func isValidAcceptsAndRejects() {
        #expect(UUID.isValid("12345678-1234-1234-1234-123456789012"))
        #expect(!UUID.isValid("12345678123412341234123456789012")) // 32-hex no-dash rejected by Foundation
        #expect(!UUID.isValid("not-a-uuid"))
        #expect(!UUID.isValid(""))
    }
}

@Suite("NebulaNilError")
struct NebulaNilErrorTests {
    @Test func isSendableError() {
        let e = NebulaNilError()
        // Conformance to Error is compile-checked by throwing it.
        #expect(throws: NebulaNilError.self) {
            throw e
        }
    }
}