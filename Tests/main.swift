// Tests/main.swift —— 轻量测试运行器（CLT 无 XCTest/SwiftPM，自建最小断言框架）
import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private var tests: [(name: String, run: () throws -> Void)] = []

func registerTest(_ name: String, _ run: @escaping () throws -> Void) {
    tests.append((name, run))
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ context: String = "") throws {
    if actual != expected {
        throw TestFailure(message: "期望 \(expected)，实际 \(actual) \(context)")
    }
}

func expectTrue(_ condition: Bool, _ context: String = "") throws {
    if !condition { throw TestFailure(message: "应为 true \(context)") }
}

func expectFalse(_ condition: Bool, _ context: String = "") throws {
    if condition { throw TestFailure(message: "应为 false \(context)") }
}

func expectNil<T>(_ value: T?, _ context: String = "") throws {
    if value != nil { throw TestFailure(message: "应为 nil，实际 \(value!) \(context)") }
}

@discardableResult
func expectNotNil<T>(_ value: T?, _ context: String = "") throws -> T {
    guard let v = value else { throw TestFailure(message: "不应为 nil \(context)") }
    return v
}

func expectThrows<T>(_ context: String = "", _ expression: @autoclosure () throws -> T) throws {
    var threw = false
    do { _ = try expression() } catch { threw = true }
    if !threw { throw TestFailure(message: "应抛错却正常返回 \(context)") }
}

func tempTestDir(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("battmate-test-\(label)-\(UUID().uuidString)", isDirectory: true)
}

// ---- 各测试组注册 ----
registerSanityTests()
registerPMSetOutputParserTests()
registerSettingsStoreTests()
registerAlertEngineTests()
registerSSHBatteryReaderTests()
registerSystemUsageParserTests()
registerTopProcessParserTests()
registerMetricsHistoryTests()
registerNotifierTests()
registerAppLogTests()
registerStatusReportTests()
registerPollSchedulerTests()
registerStatusTitleFormatterTests()
registerTunnelTests()

// ---- 运行 ----
var failedCount = 0
for test in tests {
    do {
        try test.run()
        print("✅ \(test.name)")
    } catch {
        failedCount += 1
        print("❌ \(test.name): \(error)")
    }
}
print("共 \(tests.count) 个测试，失败 \(failedCount)")
if failedCount > 0 {
    exit(1)
}
