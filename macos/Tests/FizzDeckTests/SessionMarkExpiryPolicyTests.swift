import Foundation
import XCTest
@testable import FizzDeck

final class SessionMarkExpiryPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func mark(
        daysAgo: Int,
        pinned: Bool = false,
        kind: SessionMarkKind = .gitSnapshot
    ) -> SessionMark {
        SessionMark(
            projectPath: "/tmp/expiry",
            createdAt: now.addingTimeInterval(-Double(daysAgo) * 24 * 60 * 60),
            kind: kind,
            snapshotSHA: kind == .gitSnapshot ? String(repeating: "a", count: 40) : nil,
            pinned: pinned
        )
    }

    func testWarnsOnlyDuringFinalFourDays() {
        XCTAssertEqual(SessionMarkExpiryPolicy.state(for: mark(daysAgo: 9), now: now), .stable)
        XCTAssertEqual(
            SessionMarkExpiryPolicy.state(for: mark(daysAgo: 10), now: now),
            .expiring(daysRemaining: 4)
        )
        XCTAssertEqual(
            SessionMarkExpiryPolicy.state(for: mark(daysAgo: 13), now: now),
            .expiring(daysRemaining: 1)
        )
        XCTAssertEqual(SessionMarkExpiryPolicy.state(for: mark(daysAgo: 14), now: now), .expired)
        XCTAssertEqual(SessionMarkExpiryPolicy.state(for: mark(daysAgo: 15), now: now), .expired)
    }

    func testPinnedPureAndUnavailableMarksNeverWarn() {
        XCTAssertEqual(
            SessionMarkExpiryPolicy.state(for: mark(daysAgo: 10, pinned: true), now: now),
            .stable
        )
        XCTAssertEqual(
            SessionMarkExpiryPolicy.state(
                for: mark(daysAgo: 10, kind: .pureMark),
                now: now
            ),
            .stable
        )
        XCTAssertEqual(
            SessionMarkExpiryPolicy.state(
                for: mark(daysAgo: 10),
                now: now,
                available: false
            ),
            .unavailable
        )
    }
}
