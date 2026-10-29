import Foundation

package final class TrackerEventQueue {
    private let lock = NSLock()
    private var events: [TrackerEvent] = []
    private static let maxSize = 1_000

    package var count: Int {
        lock.withLock {
            events.count
        }
    }

    package init() {}

    @discardableResult
    package func append(_ event: TrackerEvent) -> [TrackerEvent] {
        lock.withLock {
            events.append(event)
            return trimToMaxSize(Self.maxSize)
        }
    }

    package func snapshot() -> [TrackerEvent] {
        lock.withLock {
            events
        }
    }

    package func clear() {
        lock.withLock {
            events.removeAll()
        }
    }

    package func remove(ids: Set<String>) {
        guard !ids.isEmpty else {
            return
        }

        lock.withLock {
            events.removeAll { ids.contains($0.id) }
        }
    }

    @discardableResult
    package func prepend(_ eventsToRestore: [TrackerEvent]) -> [TrackerEvent] {
        lock.withLock {
            events = eventsToRestore + events
            return trimToMaxSize(Self.maxSize)
        }
    }

    private func trimToMaxSize(_ maxSize: Int) -> [TrackerEvent] {
        let limit = max(maxSize, 0)
        guard events.count > limit else {
            return []
        }

        let droppedCount = events.count - limit
        let droppedEvents = Array(events.prefix(droppedCount))
        events.removeFirst(droppedCount)
        return droppedEvents
    }
}
