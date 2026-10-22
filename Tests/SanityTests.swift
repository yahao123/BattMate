// Tests/SanityTests.swift
import Foundation

func testToolchainSanity() throws {
    try expectTrue(true, "工具链自检")
}

func registerSanityTests() {
    registerTest("工具链自检", testToolchainSanity)
}
