import XCTest
@testable import FizzDeck

final class PortConflictServiceTests: XCTestCase {
    func testParseOccupantsDeduplicatesPIDAndKeepsNames() {
        let output = """
        p101
        cnode
        p202
        cpython3
        p101
        cnode
        """

        let occupants = PortConflictService.parseOccupants(output)

        XCTAssertEqual(
            occupants,
            [
                PortOccupant(pid: 101, name: "node"),
                PortOccupant(pid: 202, name: "python3"),
            ]
        )
    }

    func testParseOccupantsRejectsInvalidPIDsAndFallsBackToUnknownName() {
        let output = """
        p1
        croot
        p404
        p505
        cworker
        pABC
        cignored
        """

        let occupants = PortConflictService.parseOccupants(output)

        XCTAssertEqual(
            occupants,
            [
                PortOccupant(pid: 404, name: "未知进程"),
                PortOccupant(pid: 505, name: "worker"),
            ]
        )
    }

    func testOccupantSummaryIncludesProcessAndPID() {
        let conflict = PortConflict(
            port: 5173,
            occupants: [PortOccupant(pid: 42, name: "node")],
            note: nil
        )

        XCTAssertEqual(conflict.occupantSummary, "node · PID 42")
    }

    func testTerminateRejectsEmptyConfirmedTargets() async {
        let conflict = PortConflict(port: 5173, occupants: [], note: "unknown")

        let result = await PortConflictService.terminateConfirmed(conflict)

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.message.contains("没有可结束的 PID"), result.message)
    }
}
