//
//  URLComponents+Nebula.swift
//  Nebula
//
//  Fluent value-type `.with*` builders over `URLComponents` for query items,
//  mirroring the Cosmos sibling's `CosmosConfiguration.with*` shape WITHOUT
//  SwiftUI — each builder returns a new `URLComponents` (the struct's
//  mutating setters are used on a copy). Pure value transforms: no locks, no
//  shared state. See vault/01-fundamentos/nebula-data-url-extensions.md.
//
//  Verified against the Xcode 27 Beta 3 SDK
//  (Foundation.swiftmodule/arm64e-apple-macos.swiftinterface):
//  - `URLComponents` is `@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0,
//    *)` `Sendable` `Hashable` `Equatable` (line 13194) — below the `.v26` floor.
//  - `queryItems` (line 13305) and `percentEncodedQueryItems` (line 13310) are
//    both below floor. This file uses the decoded `queryItems` form; consumers
//    pass plain strings and `URLComponents` re-percent-encodes on `url` access.
//

import Foundation

extension URLComponents {
    /// Returns a copy with `queryItem` appended to the query.
    ///
    /// Fluent, non-mutating counterpart to the query-item verbs on ``URL``. A
    /// duplicate `name` is NOT replaced — use ``nebulaSettingQueryItem(_:)``.
    public func nebulaWith(queryItem: URLQueryItem) -> URLComponents {
        var copy = self
        var items = copy.queryItems ?? []
        items.append(queryItem)
        copy.queryItems = items
        return copy
    }

    /// Returns a copy with `queryItems` appended to the query.
    public func nebulaWith(queryItems: [URLQueryItem]) -> URLComponents {
        var copy = self
        var items = copy.queryItems ?? []
        items.append(contentsOf: queryItems)
        copy.queryItems = items
        return copy
    }

    /// Returns a copy with `item` replacing any existing query item of the
    /// same `name` (set semantics), or appended if none exists.
    ///
    /// All same-name items are removed and `item` is appended.
    public func nebulaSettingQueryItem(_ item: URLQueryItem) -> URLComponents {
        var copy = self
        var items = copy.queryItems ?? []
        items.removeAll { $0.name == item.name }
        items.append(item)
        copy.queryItems = items
        return copy
    }

    /// Returns a copy with every query item named `name` removed (no-op if
    /// none exists).
    public func nebulaRemovingQueryItem(named name: String) -> URLComponents {
        var copy = self
        guard var items = copy.queryItems, !items.isEmpty else { return copy }
        items.removeAll { $0.name == name }
        copy.queryItems = items.isEmpty ? nil : items
        return copy
    }

    /// Returns a copy with `query` appended as query items, in sorted-key
    /// order for deterministic output.
    public func nebulaWith(query: [String: String]) -> URLComponents {
        let items = query.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return nebulaWith(queryItems: items)
    }
}