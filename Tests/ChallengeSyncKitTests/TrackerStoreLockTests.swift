import Foundation
import Testing
@testable import ChallengeSyncKit

@Test func sharedLockExcludesASeparateProcess() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("shared.lock")
    let ready = root.appendingPathComponent("ready")
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    child.arguments = ["-c", """
import fcntl, pathlib, sys, time
with open(sys.argv[1], 'a') as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    pathlib.Path(sys.argv[2]).write_text('ready')
    time.sleep(0.8)
""", file.path, ready.path]
    try child.run()
    defer { if child.isRunning { child.terminate() }; child.waitUntilExit() }
    let deadline = Date().addingTimeInterval(10)
    while !FileManager.default.fileExists(atPath: ready.path), Date() < deadline {
        Thread.sleep(forTimeInterval: 0.01)
    }
    #expect(FileManager.default.fileExists(atPath: ready.path))
    let start = Date()
    try TrackerStoreLock(file: file).withLock { }
    #expect(Date().timeIntervalSince(start) > 0.5)
    child.waitUntilExit()
    #expect(child.terminationStatus == 0)
}
