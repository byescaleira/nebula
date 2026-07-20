//
//  AuroraRepositoryTests.swift
//  AuroraTests
//
//  Wave N3 — tests for `AuroraRepository<Mapping>` (the `@ModelActor`-backed
//  adapter conforming to Nebula's `NebulaRepository` ports) over an in-memory
//  `ModelContainer`. Each test builds a fresh container (no on-disk state) and
//  round-trips `save` / `find` / `stream` / `count` / `delete` through the
//  port existentials to prove the adapter satisfies Nebula's Foundation-only
//  seams. See vault/03-padroes/nebula-data-network-architecture.md.
//

import Foundation
import SwiftData
import Testing
import Nebula
@testable import Aurora

// MARK: - Fixtures (mirror the AuroraExample)

@Model
final class NoteRecord {
    @Attribute(.unique) var uid: UUID
    var text: String
    init(uid: UUID, text: String) { self.uid = uid; self.text = text }
}

struct Note: NebulaEntity, Equatable {
    typealias ID = NebulaID<Note>
    let id: ID
    var text: String
}

enum NoteMapping: AuroraEntityMapping, Sendable {
    typealias Model = NoteRecord
    typealias Entity = Note

    static func toEntity(_ model: NoteRecord) -> Note {
        Note(id: Note.ID(rawValue: model.uid), text: model.text)
    }
    static func insert(_ entity: Note, in context: ModelContext) -> NoteRecord {
        let record = NoteRecord(uid: entity.id.rawValue, text: entity.text)
        context.insert(record)
        return record
    }
    static func update(_ model: NoteRecord, from entity: Note) {
        model.text = entity.text
    }
    static func descriptor(for id: Note.ID) -> FetchDescriptor<NoteRecord> {
        let raw = id.rawValue
        return FetchDescriptor(predicate: #Predicate { $0.uid == raw })
    }
    static func descriptor() -> FetchDescriptor<NoteRecord> {
        FetchDescriptor()
    }
}

@Suite("AuroraRepository CRUD")
struct AuroraRepositoryCRUDTests {

    private func makeRepo() throws -> AuroraRepository<NoteMapping> {
        let container = try ModelContainer(
            for: NoteRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return AuroraRepository<NoteMapping>(modelContainer: container)
    }

    @Test func saveInsertsAndFindReturns() async throws {
        let repo = try makeRepo()
        let note = Note(id: .init(), text: "hello")
        try await repo.save(note)
        let fetched = try await repo.find(id: note.id)
        #expect(fetched == note)
    }

    @Test func saveIsAddOrReplaceById() async throws {
        let repo = try makeRepo()
        let id = Note.ID()
        try await repo.save(Note(id: id, text: "first"))
        try await repo.save(Note(id: id, text: "second"))   // same id → replace
        #expect(try await repo.count() == 1)
        let fetched = try await repo.find(id: id)
        #expect(fetched?.text == "second")
    }

    @Test func findAbsentReturnsNil() async throws {
        let repo = try makeRepo()
        #expect(try await repo.find(id: .init()) == nil)
    }

    @Test func countReflectsSaves() async throws {
        let repo = try makeRepo()
        #expect(try await repo.count() == 0)
        try await repo.save(Note(id: .init(), text: "a"))
        try await repo.save(Note(id: .init(), text: "b"))
        #expect(try await repo.count() == 2)
    }

    @Test func streamYieldsAllEntities() async throws {
        let repo = try makeRepo()
        let ids = (0..<3).map { _ in Note.ID() }
        for id in ids { try await repo.save(Note(id: id, text: id.description)) }
        var seen: Set<Note.ID> = []
        for try await note in repo.stream() { seen.insert(note.id) }
        #expect(seen == Set(ids))
    }

    @Test func streamIsEmptyWhenStoreIsEmpty() async throws {
        let repo = try makeRepo()
        var count = 0
        for try await _ in repo.stream() { count += 1 }
        #expect(count == 0)
    }

    @Test func deleteRemovesEntity() async throws {
        let repo = try makeRepo()
        let note = Note(id: .init(), text: "gone")
        try await repo.save(note)
        #expect(try await repo.count() == 1)
        try await repo.delete(note.id)
        #expect(try await repo.count() == 0)
        #expect(try await repo.find(id: note.id) == nil)
    }

    @Test func deleteAbsentIsNoOp() async throws {
        let repo = try makeRepo()
        try await repo.save(Note(id: .init(), text: "kept"))
        try await repo.delete(Note.ID())   // absent id
        #expect(try await repo.count() == 1)   // the kept note is untouched
    }
}

@Suite("AuroraRepository port conformance")
struct AuroraRepositoryPortTests {

    private func makeRepo() throws -> AuroraRepository<NoteMapping> {
        let container = try ModelContainer(
            for: NoteRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return AuroraRepository<NoteMapping>(modelContainer: container)
    }

    @Test func satisfiesReadOnlyPort() async throws {
        let repo = try makeRepo()
        try await repo.save(Note(id: .init(), text: "x"))
        // Assigning to the existential is the compile-time conformance proof
        // (calling `stream()`/`count()` through `any NebulaReadOnlyRepository` is
        // disallowed in Swift 6.2 — `Element` is an opaque associatedtype — so
        // the assertions run through the concrete type). The cast-back is the
        // runtime proof that the existential wraps the adapter.
        let readOnly: any NebulaReadOnlyRepository = repo
        #expect((readOnly as? AuroraRepository<NoteMapping>) != nil)
        #expect(try await repo.count() == 1)
        var streamed = 0
        for try await _ in repo.stream() { streamed += 1 }
        #expect(streamed == 1)
    }

    @Test func satisfiesWritableAndDeletablePorts() async throws {
        let repo = try makeRepo()
        let note = Note(id: .init(), text: "w")
        let writable: any NebulaWritableRepository = repo
        let deletable: any NebulaDeletableRepository = repo
        #expect((writable as? AuroraRepository<NoteMapping>) != nil)
        #expect((deletable as? AuroraRepository<NoteMapping>) != nil)
        try await repo.save(note)
        try await repo.delete(note.id)
        #expect(try await repo.count() == 0)
    }

    @Test func satisfiesKeyedPort() async throws {
        let repo = try makeRepo()
        let note = Note(id: .init(), text: "k")
        try await repo.save(note)
        let keyed: any NebulaKeyedRepository = repo
        #expect((keyed as? AuroraRepository<NoteMapping>) != nil)
        #expect(try await repo.find(id: note.id) == note)
    }
}

@Suite("AuroraRepository Sendable")
struct AuroraRepositorySendableTests {

    @Test func usableAcrossTaskBoundary() async throws {
        let container = try ModelContainer(
            for: NoteRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repo = AuroraRepository<NoteMapping>(modelContainer: container)
        let note = Note(id: .init(), text: "across")
        try await repo.save(note)
        // Capturing the Sendable repository in a child Task is the whole point.
        let fetched: Note? = try await Task {
            try await repo.find(id: note.id)
        }.value
        #expect(fetched == note)
    }
}