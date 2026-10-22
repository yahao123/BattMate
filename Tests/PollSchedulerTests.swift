// Tests/PollSchedulerTests.swift
import Foundation

func testSchedulerPollNowInvokesHandler() throws {
    let scheduler = PollScheduler()
    var count = 0
    scheduler.onTick = { count += 1 }
    scheduler.pollNow()
    scheduler.pollNow()
    try expectEqual(count, 2)
}

func testSchedulerStopDoesNotCrash() throws {
    // stop() 必须可重复调用且不崩溃（Timer 尚未触发，不依赖 RunLoop）
    let scheduler = PollScheduler()
    scheduler.onTick = {}
    scheduler.start(interval: 15)
    scheduler.stop()
    scheduler.stop()
    try expectTrue(true)
}

func registerPollSchedulerTests() {
    registerTest("调度：pollNow 触发回调", testSchedulerPollNowInvokesHandler)
    registerTest("调度：stop 可重复调用", testSchedulerStopDoesNotCrash)
}
