import Foundation

/// The `limit` most recently used values, by key, and nothing older.
///
/// What the slide keeps its workspace pictures in. A picture is tens of megabytes — one per
/// visited workspace per display would be a few hundred — and the ones worth having are the
/// workspaces the user moves between, which a swipe only ever does one step at a time: the
/// one just left, and the one or two beside it. Recency is a good enough guess at that, and
/// the number is the whole of the footprint, which is why it is a count rather than a byte
/// budget: three pictures is three pictures on any display, and the display decides the rest.
/// Pure so that the eviction order is in the selftest; the pictures themselves are the app
/// layer's and never come here.
public struct RecentCache<Key: Hashable, Value> {
    public let limit: Int
    private var values: [Key: Value] = [:]
    /// Least recently used first.
    private var order: [Key] = []

    public init(limit: Int) {
        self.limit = max(0, limit)
    }

    public var count: Int { values.count }

    /// Every key held, least recently used first.
    public var keys: [Key] { order }

    /// The value for `key`, and using it makes it the most recent.
    public mutating func lookup(_ key: Key) -> Value? {
        guard let value = values[key] else { return nil }
        touch(key)
        return value
    }

    /// The value for `key` without changing its place in the order.
    public func peek(_ key: Key) -> Value? { values[key] }

    /// Keeps `value` under `key` as the most recent, forgetting the least recent until no more
    /// than `limit` are held. A limit of zero keeps nothing.
    public mutating func insert(_ value: Value, for key: Key) {
        values[key] = value
        touch(key)
        while order.count > limit, let oldest = order.first {
            order.removeFirst()
            values.removeValue(forKey: oldest)
        }
    }

    public mutating func remove(_ key: Key) {
        values.removeValue(forKey: key)
        order.removeAll { $0 == key }
    }

    public mutating func removeAll() {
        values.removeAll()
        order.removeAll()
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
