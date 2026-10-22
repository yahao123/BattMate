// Sources/BattMateCore/PollScheduler.swift
import Foundation
import AppKit

public final class PollScheduler {
    public var onTick: (() -> Void)?
    private var timer: Timer?
    private var interval: TimeInterval = 30

    public init() {}

    public func start(interval: TimeInterval) {
        self.interval = interval
        restartTimer()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(handleSleep),
                           name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(handleWake),
                           name: NSWorkspace.didWakeNotification, object: nil)
    }

    public func restart(interval: TimeInterval) {
        self.interval = interval
        restartTimer()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    public func pollNow() {
        onTick?()
    }

    private func restartTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollNow()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func handleSleep() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func handleWake() {
        restartTimer()
        pollNow()
    }
}
