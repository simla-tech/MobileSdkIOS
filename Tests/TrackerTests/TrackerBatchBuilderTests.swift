import Foundation
import XCTest
@testable import Tracker

final class TrackerBatchBuilderTests: XCTestCase {
    func testPacksByBytesInsteadOfEventCount() throws {
        let events = [event("a", bytes: 600_000), event("b", bytes: 300_000), event("c", bytes: 300_000)]
        let batches = try TrackerBatchBuilder.batches(events)
        XCTAssertEqual(batches.map { $0.map(\.id) }, [["a", "b"], ["c"]])
        for batch in batches {
            XCTAssertLessThanOrEqual(try JSONEncoder().encode(batch).count, TrackerBatchBuilder.targetSize)
        }
        XCTAssertEqual(batches.flatMap { $0 }, events)
    }

    func testOversizedEventRemainsWholeAndDoesNotBlockOtherBatches() throws {
        let events = [event("before", bytes: 10), event("large", bytes: 3_000_000), event("after", bytes: 10)]
        let batches = try TrackerBatchBuilder.batches(events)
        XCTAssertEqual(batches.map { $0.map(\.id) }, [["before"], ["large"], ["after"]])
        XCTAssertEqual(batches.flatMap { $0 }, events)
        XCTAssertGreaterThan(try JSONEncoder().encode(batches[1]).count, TrackerBatchBuilder.requestLimit)
    }

    func testUsesEncodedBytesIncludingEscapesAndArrayPunctuation() throws {
        let events = (0..<3).map { TrackerEvent(id: "\($0)", type: "click", pageTitle: "Привет 🌍\n\"/", timestamp: "1") }
        let exactTwo = try JSONEncoder().encode(Array(events.prefix(2))).count
        XCTAssertEqual(try TrackerBatchBuilder.batches(events, targetSize: exactTwo).map(\.count), [2, 1])
        XCTAssertEqual(try TrackerBatchBuilder.batches(events, targetSize: exactTwo - 1).map(\.count), [1, 1, 1])
        XCTAssertTrue(try TrackerBatchBuilder.batches([]).isEmpty)
    }

    private func event(_ id: String, bytes: Int) -> TrackerEvent {
        TrackerEvent(id: id, type: "click", pageTitle: String(repeating: "a", count: bytes), timestamp: "1")
    }
}
