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
import os

@testable import ORLib

struct MockResponse {
    var mockData: Data?
    var mockError: ESPSessionError?
    var delay: TimeInterval

    init(mockData: Data? = nil, mockError: ESPSessionError? = nil, delay: TimeInterval = 0) {
        self.mockData = mockData
        self.mockError = mockError
        self.delay = delay
    }
}

private final class ManualWifiScanController {
    typealias CompletionHandler = ([ESPWifiNetwork]?, ESPWiFiScanError?) -> Void

    private let lock = NSLock()
    private var manualMode = false
    private var pendingScans = [CompletionHandler]()
    private var enqueuedScanCount = 0
    private var scanWaiters = [(targetCount: Int, continuation: CheckedContinuation<Void, Never>)]()

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

    func enqueuePendingScan(_ completionHandler: @escaping CompletionHandler) {
        var waitersToResume = [CheckedContinuation<Void, Never>]()

        lock.lock()
        pendingScans.append(completionHandler)
        enqueuedScanCount += 1
        let readyWaiters = scanWaiters.filter { enqueuedScanCount >= $0.targetCount }
        scanWaiters.removeAll { enqueuedScanCount >= $0.targetCount }
        waitersToResume = readyWaiters.map(\.continuation)
        lock.unlock()

        for continuation in waitersToResume {
            continuation.resume()
        }
    }

    func dequeuePendingScan() -> CompletionHandler? {
        lock.lock()
        defer { lock.unlock() }
        guard !pendingScans.isEmpty else {
            return nil
        }
        return pendingScans.removeFirst()
    }

    func waitForEnqueuedScans(atLeast targetCount: Int) async {
        if hasEnqueuedScans(atLeast: targetCount) {
            return
        }

        await withCheckedContinuation { continuation in
            lock.lock()
            if enqueuedScanCount >= targetCount {
                lock.unlock()
                continuation.resume()
                return
            }
            scanWaiters.append((targetCount, continuation))
            lock.unlock()
        }
    }

    private func hasEnqueuedScans(atLeast targetCount: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return enqueuedScanCount >= targetCount
    }
}

private final class SendDataController {
    typealias CompletionHandler = (Data?, ESPSessionError?) -> Void

    private struct PendingRequest {
        let completionHandler: CompletionHandler
    }

    private let lock = NSLock()
    private var manualMode = false
    private var pendingRequests = [PendingRequest]()
    private var pendingRequestWaiters = [(targetCount: Int, continuation: CheckedContinuation<Void, Never>)]()
    private var mockResponses = [MockResponse]()
    private var mockResponsesIndex: [MockResponse].Index? = nil

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

    func resetMockResponses() {
        lock.lock()
        mockResponses = []
        mockResponsesIndex = nil
        lock.unlock()
    }

    func addMockResponse(_ response: MockResponse) {
        lock.lock()
        mockResponses.append(response)
        lock.unlock()
    }

    func enqueuePendingRequest(_ completionHandler: @escaping CompletionHandler) {
        var waitersToResume = [CheckedContinuation<Void, Never>]()

        lock.lock()
        pendingRequests.append(PendingRequest(completionHandler: completionHandler))
        let pendingRequestCount = pendingRequests.count
        let readyWaiters = pendingRequestWaiters.filter { pendingRequestCount >= $0.targetCount }
        pendingRequestWaiters.removeAll { pendingRequestCount >= $0.targetCount }
        waitersToResume = readyWaiters.map(\.continuation)
        lock.unlock()

        for continuation in waitersToResume {
            continuation.resume()
        }
    }

    func waitForPendingRequests(atLeast targetCount: Int) async {
        if hasPendingRequests(atLeast: targetCount) {
            return
        }

        await withCheckedContinuation { continuation in
            lock.lock()
            if pendingRequests.count >= targetCount {
                lock.unlock()
                continuation.resume()
                return
            }
            pendingRequestWaiters.append((targetCount, continuation))
            lock.unlock()
        }
    }

    private func hasPendingRequests(atLeast targetCount: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return pendingRequests.count >= targetCount
    }

    func dequeuePendingRequest() -> CompletionHandler? {
        lock.lock()
        defer { lock.unlock() }
        guard !pendingRequests.isEmpty else {
            return nil
        }
        return pendingRequests.removeFirst().completionHandler
    }

    func getNextMockResponse() -> MockResponse? {
        lock.lock()
        defer { lock.unlock() }
        if mockResponses.isEmpty {
            return nil
        }
        if let currentIndex = mockResponsesIndex {
            let nextIndex = mockResponses.index(after: currentIndex)
            if nextIndex >= mockResponses.endIndex {
                mockResponsesIndex = mockResponses.startIndex
            } else {
                mockResponsesIndex = nextIndex
            }
        } else {
            mockResponsesIndex = mockResponses.startIndex
        }
        return mockResponses[mockResponsesIndex!]
    }
}

private actor WifiScanCompletionTracker {
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

class ORESPDeviceMock: ORESPDevice {

    private let manualWifiScanController = ManualWifiScanController()
    private let sendDataController = SendDataController()
    private let wifiScanCompletionTracker = WifiScanCompletionTracker()

    var scanWifiListCallCount = 0
    var networks = [ESPWifiNetwork(ssid: "SSID-1", rssi: -50)]
    var manualWifiScans = false {
        didSet {
            manualWifiScanController.setManualMode(manualWifiScans)
        }
    }
    var manualSendDataResponses = false {
        didSet {
            sendDataController.setManualMode(manualSendDataResponses)
        }
    }

    var provisionError: ESPProvisionError?
    var provisionCalledCount = 0
    var provisionCalledParameters: (String?, String?)?

    var receivedData: [Data] = []

    init(name: String) {
        self.name = name
    }

    convenience init() {
        self.init(name: "TestDevice")
    }

    var bleDelegate: (any ESPBLEDelegate)?

    var name: String

    func resetMockResponses() {
        sendDataController.resetMockResponses()
    }

    func addMockData(_ data: Data, delay: TimeInterval = 0) {
        sendDataController.addMockResponse(MockResponse(mockData: data, delay: delay))
    }

    func addMockError(_ error: ESPSessionError, delay: TimeInterval = 0) {
        sendDataController.addMockResponse(MockResponse(mockError: error, delay: delay))
    }

    func connect(delegate: (any ESPDeviceConnectionDelegate)?, completionHandler: @escaping (ESPSessionStatus) -> Void) {
        // TODO: instrument so can set the status to return
        completionHandler(.connected)
    }

    func disconnect() {
        // TODO: could have a counter here ?
        ORLogger.test.info("device - disconnect")

    }

    func scanWifiList(completionHandler: @escaping ([ESPWifiNetwork]?, ESPWiFiScanError?) -> Void) {
        scanWifiListCallCount += 1
        let scanResult = (networks, error: Optional<ESPWiFiScanError>.none)
        let usesManualWifiScans = manualWifiScanController.isManualModeEnabled()
        Task {
            await wifiScanCompletionTracker.markScanStarted()

            if usesManualWifiScans {
                manualWifiScanController.enqueuePendingScan(completionHandler)
                return
            }

            await wifiScanCompletionTracker.markScanCompleted()
            completionHandler(scanResult.0, scanResult.error)
        }
    }

    func completeNextWifiScan(networks: [ESPWifiNetwork]? = nil, error: ESPWiFiScanError? = nil) {
        guard let completionHandler = manualWifiScanController.dequeuePendingScan() else {
            Issue.record("No pending wifi scan to complete")
            return
        }
        let resolvedNetworks = networks ?? self.networks

        Task {
            await wifiScanCompletionTracker.markScanCompleted()
            completionHandler(resolvedNetworks, error)
        }
    }

    func waitForWifiScanStarts(atLeast startedScanCount: Int) async {
        await manualWifiScanController.waitForEnqueuedScans(atLeast: startedScanCount)
    }

    func waitForWifiScanCompletions(atLeast completedScanCount: Int) async {
        await wifiScanCompletionTracker.waitForCompletedScans(atLeast: completedScanCount)
    }

    func waitForPendingSendDataRequests(atLeast requestCount: Int) async {
        await sendDataController.waitForPendingRequests(atLeast: requestCount)
    }

    func completeNextSendDataRequest(data: Data? = nil, error: ESPSessionError? = nil) {
        guard let completionHandler = sendDataController.dequeuePendingRequest() else {
            Issue.record("No pending sendData request to complete")
            return
        }
        completionHandler(data, error)
    }

    func provision(ssid: String?, passPhrase: String?, threadOperationalDataset: Data?, completionHandler: @escaping (ESPProvisionStatus) -> Void) {
        provisionCalledCount += 1
        provisionCalledParameters = (ssid, passPhrase)
        if let provisionError {
            completionHandler(.failure(provisionError))
        } else {
            completionHandler(.configApplied)
            completionHandler(.success)
        }
    }

    func sendData(path: String, data: Data, completionHandler: @escaping (Data?, ESPSessionError?) -> Void) {
        receivedData.append(data)
        if sendDataController.isManualModeEnabled() {
            sendDataController.enqueuePendingRequest(completionHandler)
            return
        }

        let response = sendDataController.getNextMockResponse()
        guard let response else {
            completionHandler(nil, nil)
            return
        }

        if response.delay == 0 {
            completionHandler(response.mockData, response.mockError)
            return
        }

        Task {
            try await Task.sleep(nanoseconds: UInt64(response.delay * Double(NSEC_PER_SEC)))
            completionHandler(response.mockData, response.mockError)
        }
    }
}
