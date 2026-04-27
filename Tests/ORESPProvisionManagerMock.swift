/*
 * Copyright 2017, OpenRemote Inc.
 *
 * See the CONTRIBUTORS.txt file in the distribution for a
 * full listing of individual contributors.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

@testable import ESPProvision
import Foundation
import Testing

@testable import ORLib

private final class ManualDeviceScanController {
    private let lock = NSLock()
    private var manualMode = false
    private var pendingRequests = [CheckedContinuation<[ORESPDevice], Error>]()
    private var enqueuedRequestCount = 0
    private var requestWaiters = [(targetCount: Int, continuation: CheckedContinuation<Void, Never>)]()

    func setManualMode(_ manualMode: Bool) {
        lock.lock()
        self.manualMode = manualMode
        lock.unlock()
    }

    func isManualModeEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return manualMode
    }

    func enqueuePendingRequest(_ continuation: CheckedContinuation<[ORESPDevice], Error>) {
        var waitersToResume = [CheckedContinuation<Void, Never>]()

        lock.lock()
        pendingRequests.append(continuation)
        enqueuedRequestCount += 1
        let readyWaiters = requestWaiters.filter { enqueuedRequestCount >= $0.targetCount }
        requestWaiters.removeAll { enqueuedRequestCount >= $0.targetCount }
        waitersToResume = readyWaiters.map(\.continuation)
        lock.unlock()

        for continuation in waitersToResume {
            continuation.resume()
        }
    }

    func dequeuePendingRequest() -> CheckedContinuation<[ORESPDevice], Error>? {
        lock.lock()
        defer { lock.unlock() }
        guard !pendingRequests.isEmpty else {
            return nil
        }
        return pendingRequests.removeFirst()
    }

    func drainPendingRequests() -> [CheckedContinuation<[ORESPDevice], Error>] {
        lock.lock()
        defer { lock.unlock() }
        let continuations = pendingRequests
        pendingRequests.removeAll()
        return continuations
    }

    func waitForEnqueuedRequests(atLeast targetCount: Int) async {
        if hasEnqueuedRequests(atLeast: targetCount) {
            return
        }

        await withCheckedContinuation { continuation in
            lock.lock()
            if enqueuedRequestCount >= targetCount {
                lock.unlock()
                continuation.resume()
                return
            }
            requestWaiters.append((targetCount, continuation))
            lock.unlock()
        }
    }

    private func hasEnqueuedRequests(atLeast targetCount: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return enqueuedRequestCount >= targetCount
    }
}

final class ORESPProvisionManagerMock: ORESPProvisionManager {
    private actor DeviceScanCompletionTracker {
        private var startedScanCount = 0
        private var completedScanCount = 0
        private var startWaiters = [(targetCount: Int, continuation: CheckedContinuation<Void, Never>)]()
        private var waiters = [(targetCount: Int, continuation: CheckedContinuation<Void, Never>)]()

        func markScanStarted() {
            startedScanCount += 1

            let readyWaiters = startWaiters.filter { startedScanCount >= $0.targetCount }
            startWaiters.removeAll { startedScanCount >= $0.targetCount }

            for waiter in readyWaiters {
                waiter.continuation.resume()
            }
        }

        func markScanCompleted() {
            completedScanCount += 1

            let readyWaiters = waiters.filter { completedScanCount >= $0.targetCount }
            waiters.removeAll { completedScanCount >= $0.targetCount }

            for waiter in readyWaiters {
                waiter.continuation.resume()
            }
        }

        func waitForStartedScans(atLeast targetCount: Int) async {
            if startedScanCount >= targetCount {
                return
            }

            await withCheckedContinuation { continuation in
                startWaiters.append((targetCount, continuation))
            }
        }

        func waitForCompletedScans(atLeast targetCount: Int) async {
            if completedScanCount >= targetCount {
                return
            }

            await withCheckedContinuation { continuation in
                waiters.append((targetCount, continuation))
            }
        }
    }

    var searchESPDevicesCallCount = 0
    var stopESPDevicesSearchCallCount = 0

    var manualDeviceScans = false {
        didSet {
            manualDeviceScanController.setManualMode(manualDeviceScans)
        }
    }

    var mockDevices = [ORESPDeviceMock()]
    private let deviceScanCompletionTracker = DeviceScanCompletionTracker()
    private let manualDeviceScanController = ManualDeviceScanController()

    func searchESPDevices(devicePrefix: String, transport: ESPTransport, security: ESPSecurity) async throws -> [ORESPDevice] {
        searchESPDevicesCallCount += 1
        await deviceScanCompletionTracker.markScanStarted()
        if manualDeviceScanController.isManualModeEnabled() {
            do {
                let devices = try await withCheckedThrowingContinuation { continuation in
                    manualDeviceScanController.enqueuePendingRequest(continuation)
                }
                await deviceScanCompletionTracker.markScanCompleted()
                return devices
            } catch {
                await deviceScanCompletionTracker.markScanCompleted()
                throw error
            }
        }
        await deviceScanCompletionTracker.markScanCompleted()
        return mockDevices
    }

    func stopESPDevicesSearch() {
        stopESPDevicesSearchCallCount += 1
        let pendingRequests = manualDeviceScanController.drainPendingRequests()
        for continuation in pendingRequests {
            continuation.resume(returning: mockDevices)
        }
    }

    func waitForDeviceSearchRequests(atLeast requestCount: Int) async {
        await manualDeviceScanController.waitForEnqueuedRequests(atLeast: requestCount)
    }

    func waitForCompletedDeviceSearchRequests(atLeast requestCount: Int) async {
        await deviceScanCompletionTracker.waitForCompletedScans(atLeast: requestCount)
    }

    func completeNextDeviceScan(with devices: [ORESPDevice]? = nil) {
        guard let continuation = manualDeviceScanController.dequeuePendingRequest() else {
            Issue.record("No pending device scan to complete")
            return
        }
        continuation.resume(returning: devices ?? mockDevices)
    }

    func failNextDeviceScan(with error: Error) {
        guard let continuation = manualDeviceScanController.dequeuePendingRequest() else {
            Issue.record("No pending device scan to fail")
            return
        }
        continuation.resume(throwing: error)
    }
}
