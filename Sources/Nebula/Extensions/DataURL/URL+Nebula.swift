//
//  URL+Nebula.swift
//  Nebula
//
//  `URL` gap-fillers: single-item query append (Foundation ships
//  `appending(queryItems:)` for arrays only), set/remove/get query items by
//  name, dictionary→query append, and a trap-free resolving helper. All
//  transforms go through `URLComponents(url:resolvingAgainstBaseURL:)` and
//  return a fresh `URL?` (nil on parse failure). Pure value-type extensions —
//  `URL`/`URLComponents` are already `Sendable`, so Nebula additions derive
//  `Sendable` with no `@unchecked` and no shared state. See
//  vault/01-fundamentos/nebula-data-url-extensions.md.
//
//  Verified against the Xcode 27 Beta 3 SDK
//  (Foundation.swiftmodule/arm64e-apple-macos.swiftinterface):
//  - `URL` is `@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)`
//    `Sendable` (line 12843); `URLComponents` likewise (line 13194);
//    `URLQueryItem` likewise (line 13349). All below the `.v26` floor.
//  - `URLComponents.init?(url:resolvingAgainstBaseURL:)` is baseline (line 13198,
//    no `@available`) — the failable path that justifies the `URL?` returns here.
//  - `URLComponents.queryItems` is `@available(macOS 10.10, iOS 8.0, watchOS 2.0,
//    tvOS 9.0, *)` (line 13305); `percentEncodedQueryItems` is
//    `@available(macOS 10.13, iOS 11.0, tvOS 11.0, watchOS 4.0, *)` (line 13310) —
//    both below floor. This file uses `queryItems` (decoded form) so callers
//    pass plain strings; `URLComponents` re-percent-encodes on `url` access.
//  - `URL.appending(queryItems:)` is `@available(macOS 13.0, iOS 16.0, tvOS 16.0,
//    watchOS 9.0, *)` (line 13060), array-only — there is no single-item
//    `appending(queryItem:)` (verified by grep), which justifies
//    ``nebulaAppending(queryItem:)``.
//  - Legacy `appendingPathComponent` / `fileURLWithPath` are deprecated
//    (`message: "Use appending(path:directoryHint:) instead"` /
//    `"Use init(filePath:directoryHint:relativeTo:) instead"`, lines 12849–
//    12872, 12985–12990) — NOT used here.
//

import Foundation

extension URL {
    // MARK: - Query item helpers

    /// Returns this URL with `queryItem` appended to the query, or `nil` if
    /// `self` cannot be parsed by `URLComponents`.
    ///
    /// Fills the single-item gap: Foundation's `URL.appending(queryItems:)`
    /// (iOS 16+/macOS 13+, below floor) accepts an **array** only — there is no
    /// single-item `appending(queryItem:)` (verified by grep on
    /// `Foundation.swiftinterface`). The new item is appended after any
    /// existing items; a duplicate `name` is NOT replaced — use
    /// ``nebulaSettingQueryItem(_:)`` for replace semantics.
    public func nebulaAppending(queryItem: URLQueryItem) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else { return nil }
        var items = components.queryItems ?? []
        items.append(queryItem)
        components.queryItems = items
        return components.url
    }

    /// Returns this URL with `items` appended to the query, or `nil` if `self`
    /// cannot be parsed by `URLComponents`.
    ///
    /// Thin ergonomic over `URL.appending(queryItems:)` that returns `nil` on
    /// parse failure (the native API returns a non-optional `URL` but assumes
    /// a valid receiver). Prefer the native API directly when `self` is known
    /// valid.
    public func nebulaAppendingQueryItems(_ items: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else { return nil }
        var existing = components.queryItems ?? []
        existing.append(contentsOf: items)
        components.queryItems = existing
        return components.url
    }

    /// Returns this URL with `item` replacing any existing query item of the
    /// same `name`, or appended if none exists; `nil` if `self` cannot be
    /// parsed.
    ///
    /// If multiple items share `item.name`, ALL are replaced by the single
    /// `item` (set semantics). This matches the common "upsert a query
    /// parameter" need that `appending(queryItems:)` alone does not cover.
    public func nebulaSettingQueryItem(_ item: URLQueryItem) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else { return nil }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == item.name }
        items.append(item)
        components.queryItems = items
        return components.url
    }

    /// Returns this URL with every query item named `name` removed, or `nil`
    /// if `self` cannot be parsed. Returns `self`'s reconstruction unchanged if
    /// no such item exists.
    public func nebulaRemovingQueryItem(named name: String) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else { return nil }
        guard var items = components.queryItems, !items.isEmpty else { return components.url }
        items.removeAll { $0.name == name }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }

    /// Returns the first query item named `name`, or `nil` if there is none
    /// (or `self` cannot be parsed).
    public func nebulaQueryItem(named name: String) -> URLQueryItem? {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: true) else { return nil }
        return components.queryItems?.first { $0.name == name }
    }

    /// Returns this URL with the `query` dictionary appended as query items,
    /// or `nil` if `self` cannot be parsed.
    ///
    /// Dictionary keys are appended in **sorted** order for deterministic
    /// output (a `Dictionary<String, String>` has no defined iteration order).
    /// Values are passed as plain strings; `URLComponents` percent-encodes them
    /// on `url` access.
    public func nebulaAppending(query: [String: String]) -> URL? {
        let items = query.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return nebulaAppendingQueryItems(items)
    }

    // MARK: - Resolving

    /// Returns `self` resolved against `base`, or `self` if `base` is `nil`.
    ///
    /// Thin ergonomic over `URLComponents(url:resolvingAgainstBaseURL:)` +
    /// `URLComponents.url(relativeTo:)` (Foundation line 13201, baseline — no
    /// deprecation). Returns `nil` if `self` cannot be parsed by
    /// `URLComponents`.
    public func nebulaResolving(against base: URL?) -> URL? {
        guard let base else { return self }
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: true) else { return nil }
        return components.url(relativeTo: base)
    }
}