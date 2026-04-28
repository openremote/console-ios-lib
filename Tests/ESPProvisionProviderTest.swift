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

private final class CallbackRecorder {
    private enum WaitCondition {
        case action(name: String, count: Int)
        case orderedActions([String])
    }

    private struct WaitResult {
        let matchedMessages: [[String:Any]]
        let allMessagesAtMatchTime: [[String:Any]]
    }

    private let lock = NSLock()
    private var messages = [[String:Any]]()
    private var waitCondition: WaitCondition?
    private var continuation: CheckedContinuation<WaitResult, Never>?

    func record(_ data: [String:Any]) {
        var continuationToResume: CheckedContinuation<WaitResult, Never>?
        var waitResult: WaitResult?

        lock.lock()
        messages.append(data)
        if let waitCondition,
           let continuation,
           let matchedMessages = matchedMessages(for: waitCondition, in: messages) {
            self.waitCondition = nil
            self.continuation = nil
            continuationToResume = continuation
            waitResult = WaitResult(matchedMessages: matchedMessages, allMessagesAtMatchTime: messages)
        }
        lock.unlock()

        if let continuationToResume, let waitResult {
            continuationToResume.resume(returning: waitResult)
        }
    }

    func waitForFirstMessage(matchingAction action: String, after trigger: @escaping () -> Void) async -> [String:Any] {
        let messages = await waitForMessages(matchingAction: action, count: 1, after: trigger)
        return messages[0]
    }

    func waitForMessages(matchingAction action: String, count: Int, after trigger: (() -> Void)? = nil) async -> [[String:Any]] {
        let waitResult = await wait(until: .action(name: action, count: count), after: trigger)
        return waitResult.matchedMessages
    }

    func waitForMessages(matchingActions actions: [String], after trigger: (() -> Void)? = nil) async -> [[String:Any]] {
        let waitResult = await wait(until: .orderedActions(actions), after: trigger)
        recordUnexpectedMessages(in: waitResult.allMessagesAtMatchTime, whileMatchingActions: actions)
        return waitResult.matchedMessages
    }

    func messageCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return messages.count
    }

    private func wait(until waitCondition: WaitCondition, after trigger: (() -> Void)? = nil) async -> WaitResult {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let matchedMessages = matchedMessages(for: waitCondition, in: messages) {
                let waitResult = WaitResult(matchedMessages: matchedMessages, allMessagesAtMatchTime: messages)
                lock.unlock()
                continuation.resume(returning: waitResult)
                return
            }
            self.waitCondition = waitCondition
            self.continuation = continuation
            lock.unlock()

            trigger?()
        }
    }

    private func matchedMessages(for waitCondition: WaitCondition, in recordedMessages: [[String:Any]]) -> [[String:Any]]? {
        switch waitCondition {
        case let .action(name, count):
            let matchingMessages = recordedMessages.filter { ($0["action"] as? String) == name }
            guard matchingMessages.count >= count else {
                return nil
            }
            return Array(matchingMessages.prefix(count))

        case let .orderedActions(actions):
            return orderedMessages(matchingActions: actions, in: recordedMessages)
        }
    }

    private func orderedMessages(matchingActions actions: [String], in recordedMessages: [[String:Any]]) -> [[String:Any]]? {
        var matchingMessages = [[String:Any]]()
        var actionIndex = 0

        for message in recordedMessages {
            guard actionIndex < actions.count else {
                break
            }

            if (message["action"] as? String) == actions[actionIndex] {
                matchingMessages.append(message)
                actionIndex += 1
            }
        }

        return actionIndex == actions.count ? matchingMessages : nil
    }

    private func recordUnexpectedMessages(in recordedMessages: [[String:Any]], whileMatchingActions actions: [String]) {
        var actionIndex = 0

        for message in recordedMessages {
            guard actionIndex < actions.count else {
                break
            }

            if (message["action"] as? String) == actions[actionIndex] {
                actionIndex += 1
            } else {
                Issue.record("Received an unexpected action: \(message)")
            }
        }
    }
}

struct ESPProvisionProviderTest {

    // MARK: device scan

    @Test func searchDeviceSuccess() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)
        defer { provider.stopDevicesScan() }

        let callbackRecorder = CallbackRecorder()
        provider.sendDataCallback = { data in
            callbackRecorder.record(data)
        }

        let receivedData = await callbackRecorder.waitForFirstMessage(matchingAction: Actions.startBleScan) {
            provider.startDevicesScan()
        }

        await espProvisionMock.waitForCompletedDeviceSearchRequests(atLeast: 3)

        #expect(espProvisionMock.searchESPDevicesCallCount >= 3)
        #expect(callbackRecorder.messageCount() == 1)

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.startBleScan)

        try #require(receivedData["devices"] as? [[String:Any]] != nil)
        let devices = receivedData["devices"] as! [[String:Any]]
        #expect(devices.count == 1)
        let device = devices.first!
        #expect(device["name"] as? String == "TestDevice")
        #expect(device["id"] != nil)
    }

    @Test func searchDevicesMultipleBatches() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        espProvisionMock.manualDeviceScans = true

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)
        defer { provider.stopDevicesScan() }

        let callbackRecorder = CallbackRecorder()
        provider.sendDataCallback = { data in
            callbackRecorder.record(data)
        }

        provider.startDevicesScan()
        await espProvisionMock.waitForDeviceSearchRequests(atLeast: 1)
        espProvisionMock.completeNextDeviceScan()

        let firstReceivedMessages = await callbackRecorder.waitForMessages(matchingAction: Actions.startBleScan, count: 1)
        let firstReceivedData = firstReceivedMessages[0]

        espProvisionMock.mockDevices.append(ORESPDeviceMock(name: "TestDevice2"))
        await espProvisionMock.waitForDeviceSearchRequests(atLeast: 2)
        espProvisionMock.completeNextDeviceScan()

        let receivedMessages = await callbackRecorder.waitForMessages(matchingAction: Actions.startBleScan, count: 2)
        let receivedData = receivedMessages[1]

        #expect(espProvisionMock.searchESPDevicesCallCount >= 2)
        #expect(callbackRecorder.messageCount() == 2)

        #expect(firstReceivedData["provider"] as? String == Providers.espprovision)
        #expect(firstReceivedData["action"] as? String == Actions.startBleScan)

        #expect(firstReceivedData["devices"] as? [[String:Any]] != nil)
        var devices = firstReceivedData["devices"] as! [[String:Any]]
        #expect(devices.count == 1)
        let device = devices.first!
        #expect(device["name"] as? String == "TestDevice")
        #expect(device["id"] != nil)

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.startBleScan)

        try #require(receivedData["devices"] as? [[String:Any]] != nil)
        devices = receivedData["devices"] as! [[String:Any]]
        #expect(devices.count == 2)

        #expect(devices.first!["name"] as? String == "TestDevice")
        #expect(devices.first!["id"] != nil)
        #expect(devices.last!["name"] as? String == "TestDevice2")
        #expect(devices.last!["id"] != nil)
    }

    @Test func testDisableStopsDeviceSearch() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        espProvisionMock.manualDeviceScans = true

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        var receivedDeviceInformation = false
        provider.startDevicesScan()
        #expect(provider.bleScanning)
        provider.sendDataCallback = { _ in
            receivedDeviceInformation = true
        }
        await espProvisionMock.waitForDeviceSearchRequests(atLeast: 1)

        let receivedData = await waitForMessage(provider: provider, expectingAction: Actions.stopBleScan) {
            _ = provider.disable()
        }

        #expect(espProvisionMock.stopESPDevicesSearchCallCount == 1)
        #expect(provider.bleScanning == false)
        #expect(receivedDeviceInformation == false)

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.stopBleScan)
        #expect(receivedData["devices"] == nil)
        #expect(receivedData.count == 2)
    }

    @Test func testStopDeviceSearch() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        espProvisionMock.manualDeviceScans = true

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        var receivedDeviceInformation = false
        provider.startDevicesScan()
        #expect(provider.bleScanning)
        provider.sendDataCallback = { _ in
            receivedDeviceInformation = true
        }
        await espProvisionMock.waitForDeviceSearchRequests(atLeast: 1)

        let receivedData = await waitForMessage(provider: provider, expectingAction: Actions.stopBleScan) {
            provider.stopDevicesScan()
        }

        #expect(espProvisionMock.searchESPDevicesCallCount == 1)
        #expect(espProvisionMock.stopESPDevicesSearchCallCount == 1)
        #expect(receivedDeviceInformation == false)
        #expect(provider.bleScanning == false)

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.stopBleScan)
        #expect((receivedData["devices"] as? [String:Any]) == nil)
        #expect(receivedData.count == 2)
    }

    @Test func testStopDeviceSearchNotStarted() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        let receivedData = await waitForMessage(provider: provider, expectingAction: Actions.stopBleScan) {
            provider.stopDevicesScan()
        }

        #expect(espProvisionMock.searchESPDevicesCallCount == 0)
        #expect(espProvisionMock.stopESPDevicesSearchCallCount == 1)
        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.stopBleScan)
        #expect((receivedData["devices"] as? [String:Any]) == nil)
        #expect(receivedData.count == 2)
        #expect(provider.bleScanning == false)
    }

    @Test func searchDevicesTimesout() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        espProvisionMock.manualDeviceScans = true
        espProvisionMock.mockDevices = []
        let timeSource = TestTimeSource()

        let provider = ESPProvisionProvider(searchDeviceTimeout: 0.2, timeSource: timeSource)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        let callbackRecorder = CallbackRecorder()
        provider.sendDataCallback = { data in
            callbackRecorder.record(data)
        }

        provider.startDevicesScan()
        #expect(provider.bleScanning)
        await espProvisionMock.waitForDeviceSearchRequests(atLeast: 1)
        timeSource.advance(by: 0.3)
        espProvisionMock.completeNextDeviceScan(with: [])

        let receivedMessages = await callbackRecorder.waitForMessages(matchingAction: Actions.stopBleScan, count: 1)
        let receivedData = receivedMessages[0]

        #expect(espProvisionMock.searchESPDevicesCallCount == 1)
        #expect(callbackRecorder.messageCount() == 1)
        #expect(provider.bleScanning == false)

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.stopBleScan)
        #expect(receivedData["errorCode"] as? Int == ESPProviderErrorCode.timeoutError.rawValue)
    }

    @Test func searchDevicesMaximumIteration() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        espProvisionMock.manualDeviceScans = true
        espProvisionMock.mockDevices = []

        let provider = ESPProvisionProvider(searchDeviceTimeout: 120, searchDeviceMaxIterations: 5)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        let callbackRecorder = CallbackRecorder()
        provider.sendDataCallback = { data in
            callbackRecorder.record(data)
        }

        provider.startDevicesScan()
        #expect(provider.bleScanning)
        for i in 1...5 {
            await espProvisionMock.waitForDeviceSearchRequests(atLeast: i)
            espProvisionMock.completeNextDeviceScan(with: [])
        }

        let receivedMessages = await callbackRecorder.waitForMessages(matchingAction: Actions.stopBleScan, count: 1)
        let receivedData = receivedMessages[0]

        #expect(espProvisionMock.searchESPDevicesCallCount == 5)
        #expect(callbackRecorder.messageCount() == 1)
        #expect(provider.bleScanning == false)

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.stopBleScan)
        #expect(receivedData["errorCode"] as? Int == ESPProviderErrorCode.timeoutError.rawValue)
    }

    @Test func multipleSearchDevices() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        espProvisionMock.manualDeviceScans = true

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)
        defer { provider.stopDevicesScan() }

        let callbackRecorder = CallbackRecorder()
        provider.sendDataCallback = { data in
            callbackRecorder.record(data)
        }

        provider.startDevicesScan()
        await espProvisionMock.waitForDeviceSearchRequests(atLeast: 1)
        espProvisionMock.completeNextDeviceScan()

        let firstReceivedMessages = await callbackRecorder.waitForMessages(matchingAction: Actions.startBleScan, count: 1)
        let firstReceivedData = firstReceivedMessages[0]

        #expect(espProvisionMock.searchESPDevicesCallCount >= 1)
        #expect(callbackRecorder.messageCount() == 1)

        #expect(firstReceivedData["provider"] as? String == Providers.espprovision)
        #expect(firstReceivedData["action"] as? String == Actions.startBleScan)

        try #require(firstReceivedData["devices"] as? [[String:Any]] != nil)
        var devices = firstReceivedData["devices"] as! [[String:Any]]
        #expect(devices.count == 1)
        var device = devices.first!
        #expect(device["name"] as? String == "TestDevice")
        #expect(device["id"] != nil)

        // Calling it a second time while the first is still on-going
        provider.startDevicesScan()
        await espProvisionMock.waitForDeviceSearchRequests(atLeast: 2)
        espProvisionMock.completeNextDeviceScan()

        let receivedMessages = await callbackRecorder.waitForMessages(matchingAction: Actions.startBleScan, count: 2)
        let receivedData = receivedMessages[1]

        #expect(espProvisionMock.searchESPDevicesCallCount >= 2)
        #expect(callbackRecorder.messageCount() == 2)

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.startBleScan)

        try #require(receivedData["devices"] as? [[String:Any]] != nil)
        devices = receivedData["devices"] as! [[String:Any]]
        #expect(devices.count == 1)
        device = devices.first!
        #expect(device["name"] as? String == "TestDevice")
        #expect(device["id"] != nil)
    }

    // MARK: Device connection

    @Test func connectToDevice() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        let device = await getDevice(provider: provider)
        #expect(provider.bleScanning)

        let receivedMessages = await waitForMessages(provider: provider, expectingActions: [Actions.stopBleScan, Actions.connectToDevice]) {
            provider.connectTo(deviceId: device["id"] as! String)
        }
        #expect(provider.bleScanning == false)

        #expect(espProvisionMock.stopESPDevicesSearchCallCount == 1)

        #expect(receivedMessages.count == 2)

        var receivedData = receivedMessages[0]
        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.stopBleScan)

        receivedData = receivedMessages[1]
        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.connectToDevice)
        #expect(receivedData["id"] as? String == device["id"] as? String)
        #expect(receivedData["status"] as? String == ESPProviderConnectToDeviceStatus.connected)
    }

    @Test func connectToDeviceFailsForInvalidId() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        _ = await getDevice(provider: provider)
        #expect(provider.bleScanning)

        let callbackRecorder = CallbackRecorder()
        provider.sendDataCallback = { data in
            callbackRecorder.record(data)
        }

        let receivedData = await callbackRecorder.waitForFirstMessage(matchingAction: Actions.connectToDevice) {
            provider.connectTo(deviceId: "INVALID_ID")
        }

        #expect(espProvisionMock.stopESPDevicesSearchCallCount == 1)
        #expect(provider.bleScanning == false)

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.connectToDevice)
        #expect(receivedData["status"] as? String == ESPProviderConnectToDeviceStatus.connectionError)
        #expect(receivedData["errorCode"] as? Int == ESPProviderErrorCode.unknownDevice.rawValue)
    }


    // TODO: test different connection failures
    // TODO: test disconnection (wanted or not)

    // TODO: start device scan after wifi search

    // MARK: Wifi scan

    @Test func startWifiScanNotConnected() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max, searchWifiTimeout: 1, searchWifiMaxIterations: Int.max)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        _ = await getDevice(provider: provider)

        provider.stopDevicesScan()

        let receivedData = await waitForMessage(provider: provider, expectingAction: Actions.stopWifiScan) {
            provider.startWifiScan()
        }
        #expect(provider.wifiScanning == false)

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.stopWifiScan)
        #expect(receivedData["errorCode"] as? Int == ESPProviderErrorCode.notConnected.rawValue)
    }

    @Test func wifiScan() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        let mockDevice = ORESPDeviceMock()
        mockDevice.manualWifiScans = true
        espProvisionMock.mockDevices = [mockDevice]

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max, searchWifiTimeout: 1, searchWifiMaxIterations: Int.max)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        let device = await getDevice(provider: provider)

        try await connectToDevice(provider: provider, deviceId: device["id"] as! String)
        defer { provider.stopWifiScan() }

        let callbackRecorder = CallbackRecorder()
        provider.sendDataCallback = { data in
            callbackRecorder.record(data)
        }

        provider.startWifiScan()
        await mockDevice.waitForWifiScanStarts(atLeast: 1)
        mockDevice.completeNextWifiScan()

        let receivedMessages = await callbackRecorder.waitForMessages(matchingAction: Actions.startWifiScan, count: 1)
        let receivedData = receivedMessages[0]

        await mockDevice.waitForWifiScanStarts(atLeast: 2)
        mockDevice.completeNextWifiScan()
        await mockDevice.waitForWifiScanStarts(atLeast: 3)
        mockDevice.completeNextWifiScan()
        await mockDevice.waitForWifiScanCompletions(atLeast: 3)

        #expect(mockDevice.scanWifiListCallCount >= 3)
        #expect(provider.wifiScanning)

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.startWifiScan)

        try #require(receivedData["networks"] as? [[String:Any]] != nil)
        let networks = receivedData["networks"] as! [[String:Any]]
        #expect(networks.count == 1)
        let network = networks.first!
        #expect(network["ssid"] as? String == "SSID-1")
        #expect(network["signalStrength"] as? Int32 == -50)
        #expect(callbackRecorder.messageCount() == 1)
    }

    @Test func wifiScanUpdatedRssi() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        let mockDevice = ORESPDeviceMock()
        mockDevice.manualWifiScans = true
        mockDevice.networks = [ESPWifiNetwork(ssid: "SSID-1", rssi: -50)]
        espProvisionMock.mockDevices = [mockDevice]

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max, searchWifiTimeout: 1, searchWifiMaxIterations: Int.max)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        let device = await getDevice(provider: provider)

        try await connectToDevice(provider: provider, deviceId: device["id"] as! String)
        defer { provider.stopWifiScan() }

        let callbackRecorder = CallbackRecorder()
        provider.sendDataCallback = { data in
            callbackRecorder.record(data)
        }

        provider.startWifiScan()
        await mockDevice.waitForWifiScanStarts(atLeast: 1)
        mockDevice.completeNextWifiScan()

        let firstReceivedMessages = await callbackRecorder.waitForMessages(matchingAction: Actions.startWifiScan, count: 1)
        let firstReceivedData = firstReceivedMessages[0]

        mockDevice.networks = [ESPWifiNetwork(ssid: "SSID-1", rssi: -60)]
        await mockDevice.waitForWifiScanStarts(atLeast: 2)
        mockDevice.completeNextWifiScan()
        let receivedMessages = await callbackRecorder.waitForMessages(matchingAction: Actions.startWifiScan, count: 2)
        let receivedData = receivedMessages[1]

        await mockDevice.waitForWifiScanStarts(atLeast: 3)
        mockDevice.completeNextWifiScan()
        await mockDevice.waitForWifiScanCompletions(atLeast: 3)

        #expect(mockDevice.scanWifiListCallCount >= 3)
        #expect(provider.wifiScanning)

        #expect(firstReceivedData["provider"] as? String == Providers.espprovision)
        #expect(firstReceivedData["action"] as? String == Actions.startWifiScan)

        try #require(firstReceivedData["networks"] as? [[String:Any]] != nil)
        let networks = firstReceivedData["networks"] as! [[String:Any]]
        #expect(networks.count == 1)
        let network = networks.first!
        #expect(network["ssid"] as? String == "SSID-1")
        #expect(network["signalStrength"] as? Int32 == -50)

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.startWifiScan)

        try #require(receivedData["networks"] as? [[String:Any]] != nil)
        let networks2 = receivedData["networks"] as! [[String:Any]]
        #expect(networks2.count == 1)
        let network2 = networks2.first!
        #expect(network2["ssid"] as? String == "SSID-1")
        #expect(network2["signalStrength"] as? Int32 == -60)
        #expect(callbackRecorder.messageCount() == 2)
    }

    @Test func wifiScanTimesout() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        let mockDevice = ORESPDeviceMock()
        mockDevice.manualWifiScans = true
        mockDevice.networks = []
        espProvisionMock.mockDevices = [mockDevice]
        let timeSource = TestTimeSource()

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max, searchWifiTimeout: 0.2, timeSource: timeSource)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        let device = await getDevice(provider: provider)

        try await connectToDevice(provider: provider, deviceId: device["id"] as! String)

        let callbackRecorder = CallbackRecorder()
        provider.sendDataCallback = { data in
            callbackRecorder.record(data)
        }

        provider.startWifiScan()
        #expect(provider.wifiScanning)
        await mockDevice.waitForWifiScanStarts(atLeast: 1)
        timeSource.advance(by: 0.3)
        mockDevice.completeNextWifiScan(networks: [])

        let receivedMessages = await callbackRecorder.waitForMessages(matchingAction: Actions.stopWifiScan, count: 1)
        let receivedData = receivedMessages[0]

        #expect(mockDevice.scanWifiListCallCount == 1)
        #expect(callbackRecorder.messageCount() == 1)
        #expect(provider.wifiScanning == false)

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.stopWifiScan)
        #expect(receivedData["errorCode"] as? Int == ESPProviderErrorCode.timeoutError.rawValue)
    }

    @Test func wifiScanMaximumIterations() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        let mockDevice = ORESPDeviceMock()
        mockDevice.manualWifiScans = true
        mockDevice.networks = []
        espProvisionMock.mockDevices = [mockDevice]

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max, searchWifiTimeout: 120, searchWifiMaxIterations: 5)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        let device = await getDevice(provider: provider)

        try await connectToDevice(provider: provider, deviceId: device["id"] as! String)

        let callbackRecorder = CallbackRecorder()
        provider.sendDataCallback = { data in
            callbackRecorder.record(data)
        }

        provider.startWifiScan()
        #expect(provider.wifiScanning)
        for i in 1...5 {
            await mockDevice.waitForWifiScanStarts(atLeast: i)
            mockDevice.completeNextWifiScan(networks: [])
        }

        let receivedMessages = await callbackRecorder.waitForMessages(matchingAction: Actions.stopWifiScan, count: 1)
        let receivedData = receivedMessages[0]

        #expect(mockDevice.scanWifiListCallCount == 5)
        #expect(callbackRecorder.messageCount() == 1)
        #expect(provider.wifiScanning == false)

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.stopWifiScan)
        #expect(receivedData["errorCode"] as? Int == ESPProviderErrorCode.timeoutError.rawValue)
    }

    @Test func testStopWifiScan() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        let mockDevice = ORESPDeviceMock()
        mockDevice.manualWifiScans = true
        espProvisionMock.mockDevices = [mockDevice]

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max, searchWifiTimeout: 1, searchWifiMaxIterations: Int.max)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        let device = await getDevice(provider: provider)

        try await connectToDevice(provider: provider, deviceId: device["id"] as! String)

        var receivedDeviceInformation = false
        provider.startWifiScan()
        #expect(provider.wifiScanning)
        provider.sendDataCallback = { _ in
            receivedDeviceInformation = true
        }
        await mockDevice.waitForWifiScanStarts(atLeast: 1)

        let receivedData = await waitForMessage(provider: provider, expectingAction: Actions.stopWifiScan) {
            provider.stopWifiScan()
        }
        #expect(mockDevice.scanWifiListCallCount == 1)
        // There's not scan stop operation of device, can't validate that
        #expect(receivedDeviceInformation == false)
        #expect(provider.wifiScanning == false)

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.stopWifiScan)
        #expect((receivedData["networks"] as? [String:Any]) == nil)
        #expect(receivedData.count == 2)
    }

    @Test func testStopWifiScanNotStarted() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        let mockDevice = ORESPDeviceMock()
        espProvisionMock.mockDevices = [mockDevice]

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max, searchWifiTimeout: 1, searchWifiMaxIterations: Int.max)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        let device = await getDevice(provider: provider)

        try await connectToDevice(provider: provider, deviceId: device["id"] as! String)

        var receivedDeviceInformation = false
        provider.sendDataCallback = { _ in
            receivedDeviceInformation = true
        }
        provider.stopWifiScan()

        #expect(mockDevice.scanWifiListCallCount == 0)
        // There's not scan stop operation of device, can't validate that
        #expect(receivedDeviceInformation == false)
        #expect(provider.wifiScanning == false)
    }

    // TODO: connect to device during wifi search -> what's the expect behaviour for same device or different device
    // TODO: if connect to different device and restart a wifi scan, should receive potentially different list

    // TODO: start device scan during wifi search

    @Test func sendWifiConfigurationSuccess() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        let mockDevice = ORESPDeviceMock()
        mockDevice.manualWifiScans = true
        espProvisionMock.mockDevices = [mockDevice]

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max, searchWifiTimeout: 1, searchWifiMaxIterations: Int.max)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        let device = await getDevice(provider: provider)

        try await connectToDevice(provider: provider, deviceId: device["id"] as! String)
        let callbackRecorder = CallbackRecorder()
        provider.sendDataCallback = { data in
            callbackRecorder.record(data)
        }

        provider.startWifiScan()
        #expect(provider.wifiScanning)
        await mockDevice.waitForWifiScanStarts(atLeast: 1)
        mockDevice.completeNextWifiScan()

        let firstReceivedMessages = await callbackRecorder.waitForMessages(matchingAction: Actions.startWifiScan, count: 1)
        var receivedData = firstReceivedMessages[0]

        let network = (receivedData["networks"] as! [[String:Any]]).first!

        let receivedMessages = await waitForMessages(provider: provider, expectingActions: [Actions.stopWifiScan, Actions.sendWifiConfiguration]) {
            provider.sendWifiConfiguration(ssid: network["ssid"] as? String ?? "", password: "s3cr3t")
        }

        #expect(receivedMessages.count == 2)

        receivedData = receivedMessages[0]
        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.stopWifiScan)
        #expect(receivedData.count == 2)

        receivedData = receivedMessages[1]
        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.sendWifiConfiguration)
        #expect(receivedData["connected"] as? Bool == true)

        #expect(mockDevice.provisionCalledCount == 1)
        #expect(mockDevice.provisionCalledParameters != nil)
        #expect(mockDevice.provisionCalledParameters!.0 == "SSID-1")
        #expect(mockDevice.provisionCalledParameters!.1 == "s3cr3t")
        #expect(provider.wifiScanning == false)
    }

    @Test(arguments: [
        (ESPProvisionError.sessionError, ESPProviderErrorCode.communicationError),
        (ESPProvisionError.configurationError(ESPProvisionError.unknownError), ESPProviderErrorCode.wifiConfigurationError),
        (ESPProvisionError.wifiStatusError(ESPProvisionError.unknownError), ESPProviderErrorCode.wifiConfigurationError),
        (ESPProvisionError.wifiStatusDisconnected, ESPProviderErrorCode.wifiConfigurationError),
        (ESPProvisionError.wifiStatusAuthenticationError, ESPProviderErrorCode.wifiAuthenticationError),
        (ESPProvisionError.wifiStatusNetworkNotFound, ESPProviderErrorCode.wifiNetworkNotFound),
        (ESPProvisionError.wifiStatusUnknownError, ESPProviderErrorCode.wifiCommunicationError),
        (ESPProvisionError.threadStatusError(ESPProvisionError.unknownError), ESPProviderErrorCode.genericError),
        (ESPProvisionError.threadStatusDettached, ESPProviderErrorCode.genericError),
        (ESPProvisionError.threadDatasetInvalid, ESPProviderErrorCode.genericError),
        (ESPProvisionError.threadStatusNetworkNotFound, ESPProviderErrorCode.genericError),
        (ESPProvisionError.threadStatusUnknownError, ESPProviderErrorCode.genericError),
        (ESPProvisionError.unknownError, ESPProviderErrorCode.genericError)
    ])
    func sendWifiConfigurationProvisionErrors(errorTupple: (ESPProvisionError, ESPProviderErrorCode)) async throws {
        let (provisionError, providerErrorCode) = errorTupple
        let espProvisionMock = ORESPProvisionManagerMock()
        let mockDevice = ORESPDeviceMock()
        mockDevice.manualWifiScans = true
        mockDevice.provisionError = provisionError
        espProvisionMock.mockDevices = [mockDevice]

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max, searchWifiTimeout: 1, searchWifiMaxIterations: Int.max)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        let device = await getDevice(provider: provider)

        try await connectToDevice(provider: provider, deviceId: device["id"] as! String)
        let callbackRecorder = CallbackRecorder()
        provider.sendDataCallback = { data in
            callbackRecorder.record(data)
        }

        provider.startWifiScan()
        #expect(provider.wifiScanning)
        await mockDevice.waitForWifiScanStarts(atLeast: 1)
        mockDevice.completeNextWifiScan()

        let firstReceivedMessages = await callbackRecorder.waitForMessages(matchingAction: Actions.startWifiScan, count: 1)
        var receivedData = firstReceivedMessages[0]

        let network = (receivedData["networks"] as! [[String:Any]]).first!

        let receivedMessages = await waitForMessages(provider: provider, expectingActions: [Actions.stopWifiScan, Actions.sendWifiConfiguration]) {
            provider.sendWifiConfiguration(ssid: network["ssid"] as? String ?? "", password: "s3cr3t")
        }

        #expect(receivedMessages.count == 2)

        receivedData = receivedMessages[0]
        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.stopWifiScan)
        #expect(receivedData.count == 2)

        receivedData = receivedMessages[1]
        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.sendWifiConfiguration)
        #expect(receivedData["connected"] as? Bool != nil)
        #expect(receivedData["connected"] as? Bool == false)
        #expect(receivedData["errorCode"] as? Int == providerErrorCode.rawValue)

        #expect(mockDevice.provisionCalledCount == 1)
        #expect(mockDevice.provisionCalledParameters != nil)
        #expect(mockDevice.provisionCalledParameters!.0 == "SSID-1")
        #expect(mockDevice.provisionCalledParameters!.1 == "s3cr3t")
        #expect(provider.wifiScanning == false)
    }

    @Test func sendWifiConfigurationNotConnected() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        let mockDevice = ORESPDeviceMock()
        espProvisionMock.mockDevices = [mockDevice]

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max, searchWifiTimeout: 1, searchWifiMaxIterations: Int.max)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        _ = await getDevice(provider: provider)

        provider.stopDevicesScan()

        let receivedData = await waitForMessage(provider: provider, expectingAction: Actions.sendWifiConfiguration) {
            provider.sendWifiConfiguration(ssid: "SSID-1", password: "s3cr3t")
        }

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.sendWifiConfiguration)
        #expect(receivedData["errorCode"] as? Int == ESPProviderErrorCode.notConnected.rawValue)
    }

    // MARK: Provision


    @Test func provisionDeviceSuccess() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        let mockDevice = ORESPDeviceMock()
        mockDevice.manualSendDataResponses = true

        var expectedDeviceInfo = Response.DeviceInfo()
        expectedDeviceInfo.deviceID = "123456789ABC"
        expectedDeviceInfo.modelName = "My Battery"

        var expectedOpenRemoteConfig = Response.OpenRemoteConfig()
        expectedOpenRemoteConfig.status = .success

        var expectedBackendConnectionStatus = Response.BackendConnectionStatus()
        expectedBackendConnectionStatus.status = .connected

        espProvisionMock.mockDevices = [mockDevice]

        let deviceProvisionAPIMock = DeviceProvisionAPIMock()
        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max,
                                            searchWifiTimeout: 1, searchWifiMaxIterations: Int.max,
                                            deviceProvisionAPI: deviceProvisionAPIMock)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        let device = await getDevice(provider: provider)

        try await connectToDevice(provider: provider, deviceId: device["id"] as! String)

        let callbackRecorder = CallbackRecorder()
        provider.sendDataCallback = { data in
            callbackRecorder.record(data)
        }

        provider.provisionDevice(userToken: "OAUTH_TOKEN")

        var request = try await waitForNextPendingRequest(on: mockDevice, requestIndex: 0)
        #expect(request.id == "0")
        #expect(request.body == .deviceInfo(Request.DeviceInfo()))
        mockDevice.completeNextSendDataRequest(data: ORConfigChannelTest.responseData(body: .deviceInfo(expectedDeviceInfo)))

        request = try await waitForNextPendingRequest(on: mockDevice, requestIndex: 1)
        #expect(request.id == "1")
        if case let .openRemoteConfig(openRemoteConfig) = request.body {
            #expect(openRemoteConfig.realm == "master")
            #expect(openRemoteConfig.mqttBrokerURL == "mqtts://localhost:8883")
            #expect(openRemoteConfig.user == expectedDeviceInfo.deviceID.lowercased(with: Locale(identifier: "en")))
            #expect(openRemoteConfig.mqttPassword == deviceProvisionAPIMock.receivedPassword)
            #expect(openRemoteConfig.assetID == "AssetID")
        } else {
            Issue.record("Received an unexpected response: \(request)")
        }
        mockDevice.completeNextSendDataRequest(data: ORConfigChannelTest.responseData(id: "1", body: .openRemoteConfig(expectedOpenRemoteConfig)))

        request = try await waitForNextPendingRequest(on: mockDevice, requestIndex: 2)
        #expect(request.id == "2")
        #expect(request.body == .backendConnectionStatus(Request.BackendConnectionStatus()))
        mockDevice.completeNextSendDataRequest(data: ORConfigChannelTest.responseData(id: "2", body: .backendConnectionStatus(expectedBackendConnectionStatus)))

        let receivedMessages = await callbackRecorder.waitForMessages(matchingAction: Actions.provisionDevice, count: 1)
        let receivedData = receivedMessages[0]

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.provisionDevice)
        #expect(receivedData["connected"] as? Bool == true)
        #expect(callbackRecorder.messageCount() == 1)

        #expect(mockDevice.receivedData.count == 3)

        #expect(deviceProvisionAPIMock.provisionCallCount == 1)
        #expect(deviceProvisionAPIMock.receivedModelName == expectedDeviceInfo.modelName)
        #expect(deviceProvisionAPIMock.receivedDeviceId == expectedDeviceInfo.deviceID)
        #expect(deviceProvisionAPIMock.receivedPassword != nil)
        #expect(deviceProvisionAPIMock.receivedToken == "OAUTH_TOKEN")
    }

    @Test func provisionDeviceSuccessAfterMultipleStatusRequest() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        let mockDevice = ORESPDeviceMock()
        mockDevice.manualSendDataResponses = true

        var expectedDeviceInfo = Response.DeviceInfo()
        expectedDeviceInfo.deviceID = "123456789ABC"
        expectedDeviceInfo.modelName = "My Battery"

        var expectedOpenRemoteConfig = Response.OpenRemoteConfig()
        expectedOpenRemoteConfig.status = .success

        var expectedBackendConnectionStatusSuccess = Response.BackendConnectionStatus()
        expectedBackendConnectionStatusSuccess.status = .connected

        var expectedBackendConnectionStatusFailure = Response.BackendConnectionStatus()
        expectedBackendConnectionStatusFailure.status = .disconnected

        espProvisionMock.mockDevices = [mockDevice]

        let deviceProvisionAPIMock = DeviceProvisionAPIMock()
        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max,
                                            searchWifiTimeout: 1, searchWifiMaxIterations: Int.max,
                                            deviceProvisionAPI: deviceProvisionAPIMock)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        let device = await getDevice(provider: provider)

        try await connectToDevice(provider: provider, deviceId: device["id"] as! String)

        let callbackRecorder = CallbackRecorder()
        provider.sendDataCallback = { data in
            callbackRecorder.record(data)
        }

        provider.provisionDevice(userToken: "OAUTH_TOKEN")

        var request = try await waitForNextPendingRequest(on: mockDevice, requestIndex: 0)
        #expect(request.id == "0")
        #expect(request.body == .deviceInfo(Request.DeviceInfo()))
        mockDevice.completeNextSendDataRequest(data: ORConfigChannelTest.responseData(body: .deviceInfo(expectedDeviceInfo)))

        request = try await waitForNextPendingRequest(on: mockDevice, requestIndex: 1)
        #expect(request.id == "1")
        if case let .openRemoteConfig(openRemoteConfig) = request.body {
            #expect(openRemoteConfig.realm == "master")
            #expect(openRemoteConfig.mqttBrokerURL == "mqtts://localhost:8883")
            #expect(openRemoteConfig.user == expectedDeviceInfo.deviceID.lowercased(with: Locale(identifier: "en")))
            #expect(openRemoteConfig.mqttPassword == deviceProvisionAPIMock.receivedPassword)
            #expect(openRemoteConfig.assetID == "AssetID")
        } else {
            Issue.record("Received an unexpected response: \(request)")
        }
        mockDevice.completeNextSendDataRequest(data: ORConfigChannelTest.responseData(id: "1", body: .openRemoteConfig(expectedOpenRemoteConfig)))

        for i in 2...4 {
            request = try await waitForNextPendingRequest(on: mockDevice, requestIndex: i)
            #expect(request.id == String(i))
            #expect(request.body == .backendConnectionStatus(Request.BackendConnectionStatus()))

            let response = i == 4
                ? ORConfigChannelTest.responseData(id: "4", body: .backendConnectionStatus(expectedBackendConnectionStatusSuccess))
                : ORConfigChannelTest.responseData(id: String(i), body: .backendConnectionStatus(expectedBackendConnectionStatusFailure))
            mockDevice.completeNextSendDataRequest(data: response)
        }

        let receivedMessages = await callbackRecorder.waitForMessages(matchingAction: Actions.provisionDevice, count: 1)
        let receivedData = receivedMessages[0]

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.provisionDevice)
        #expect(receivedData["connected"] as? Bool == true)
        #expect(callbackRecorder.messageCount() == 1)

        try #require(mockDevice.receivedData.count == 5)

        #expect(deviceProvisionAPIMock.provisionCallCount == 1)
        #expect(deviceProvisionAPIMock.receivedModelName == expectedDeviceInfo.modelName)
        #expect(deviceProvisionAPIMock.receivedDeviceId == expectedDeviceInfo.deviceID)
        #expect(deviceProvisionAPIMock.receivedPassword != nil)
        #expect(deviceProvisionAPIMock.receivedToken == "OAUTH_TOKEN")
    }

    @Test func provisionDeviceFailureTimeout() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        let mockDevice = ORESPDeviceMock()
        mockDevice.manualSendDataResponses = true

        var expectedDeviceInfo = Response.DeviceInfo()
        expectedDeviceInfo.deviceID = "123456789ABC"
        expectedDeviceInfo.modelName = "My Battery"

        var expectedOpenRemoteConfig = Response.OpenRemoteConfig()
        expectedOpenRemoteConfig.status = .success

        var expectedBackendConnectionStatusFailure = Response.BackendConnectionStatus()
        expectedBackendConnectionStatusFailure.status = .disconnected

        espProvisionMock.mockDevices = [mockDevice]
        let timeSource = TestTimeSource()

        let deviceProvisionAPIMock = DeviceProvisionAPIMock()
        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max,
                                            searchWifiTimeout: 1, searchWifiMaxIterations: Int.max,
                                            deviceProvisionAPI: deviceProvisionAPIMock, backendConnectionTimeout: 0.5,
                                            timeSource: timeSource)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        let device = await getDevice(provider: provider)

        try await connectToDevice(provider: provider, deviceId: device["id"] as! String)

        let callbackRecorder = CallbackRecorder()
        provider.sendDataCallback = { data in
            callbackRecorder.record(data)
        }

        provider.provisionDevice(userToken: "OAUTH_TOKEN")

        var request = try await waitForNextPendingRequest(on: mockDevice, requestIndex: 0)
        #expect(request.id == "0")
        #expect(request.body == .deviceInfo(Request.DeviceInfo()))
        mockDevice.completeNextSendDataRequest(data: ORConfigChannelTest.responseData(body: .deviceInfo(expectedDeviceInfo)))

        request = try await waitForNextPendingRequest(on: mockDevice, requestIndex: 1)
        #expect(request.id == "1")
        if case let .openRemoteConfig(openRemoteConfig) = request.body {
            #expect(openRemoteConfig.realm == "master")
            #expect(openRemoteConfig.mqttBrokerURL == "mqtts://localhost:8883")
            #expect(openRemoteConfig.user == expectedDeviceInfo.deviceID.lowercased(with: Locale(identifier: "en")))
            #expect(openRemoteConfig.mqttPassword == deviceProvisionAPIMock.receivedPassword)
            #expect(openRemoteConfig.assetID == "AssetID")

        } else {
            Issue.record("Received an unexpected response: \(request)")
        }
        mockDevice.completeNextSendDataRequest(data: ORConfigChannelTest.responseData(id: "1", body: .openRemoteConfig(expectedOpenRemoteConfig)))

        request = try await waitForNextPendingRequest(on: mockDevice, requestIndex: 2)
        #expect(request.id == "2")
        #expect(request.body == .backendConnectionStatus(Request.BackendConnectionStatus()))
        timeSource.advance(by: 0.6)
        mockDevice.completeNextSendDataRequest(data: ORConfigChannelTest.responseData(id: "2", body: .backendConnectionStatus(expectedBackendConnectionStatusFailure)))

        let receivedMessages = await callbackRecorder.waitForMessages(matchingAction: Actions.provisionDevice, count: 1)
        let receivedData = receivedMessages[0]

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.provisionDevice)
        #expect(receivedData["connected"] as? Bool != nil)
        #expect(receivedData["connected"] as? Bool == false)
        #expect(receivedData["errorCode"] as? Int == ESPProviderErrorCode.timeoutError.rawValue)
        #expect(callbackRecorder.messageCount() == 1)

        #expect(mockDevice.receivedData.count == 3)

        #expect(deviceProvisionAPIMock.provisionCallCount == 1)
        #expect(deviceProvisionAPIMock.receivedModelName == expectedDeviceInfo.modelName)
        #expect(deviceProvisionAPIMock.receivedDeviceId == expectedDeviceInfo.deviceID)
        #expect(deviceProvisionAPIMock.receivedPassword != nil)
        #expect(deviceProvisionAPIMock.receivedToken == "OAUTH_TOKEN")
    }

    @Test func provisionDeviceNotConnected() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        let mockDevice = ORESPDeviceMock()
        espProvisionMock.mockDevices = [mockDevice]

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max, searchWifiTimeout: 1, searchWifiMaxIterations: Int.max)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        _ = await getDevice(provider: provider)

        let receivedData = await waitForMessage(provider: provider, expectingAction: Actions.provisionDevice) {
            provider.provisionDevice(userToken: "OAUTH_TOKEN")
        }

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.provisionDevice)
        #expect(receivedData["errorCode"] as? Int == ESPProviderErrorCode.notConnected.rawValue)
    }

    // MARK: Exit provisioning

    @Test func exitProvisioningSuccess() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()
        let mockDevice = ORESPDeviceMock()
        mockDevice.manualSendDataResponses = true

        espProvisionMock.mockDevices = [mockDevice]

        let deviceProvisionAPIMock = DeviceProvisionAPIMock()
        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max,
                                            searchWifiTimeout: 1, searchWifiMaxIterations: Int.max,
                                            deviceProvisionAPI: deviceProvisionAPIMock)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        let device = await getDevice(provider: provider)

        try await connectToDevice(provider: provider, deviceId: device["id"] as! String)

        let callbackRecorder = CallbackRecorder()
        provider.sendDataCallback = { data in
            callbackRecorder.record(data)
        }

        provider.exitProvisioning()
        _ = try await waitForNextPendingRequest(on: mockDevice, requestIndex: 0)
        mockDevice.completeNextSendDataRequest(data: ORConfigChannelTest.responseData(body: .exitProvisioning(Response.ExitProvisioning())))

        let receivedMessages = await callbackRecorder.waitForMessages(matchingAction: Actions.exitProvisioning, count: 1)
        let receivedData = receivedMessages[0]

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.exitProvisioning)
        #expect(receivedData["exit"] as? Bool == true)
    }

    @Test func exitProvisioningNotConnected() async throws {
        let espProvisionMock = ORESPProvisionManagerMock()

        let provider = ESPProvisionProvider(searchDeviceTimeout: 1, searchDeviceMaxIterations: Int.max, searchWifiTimeout: 1, searchWifiMaxIterations: Int.max)
        _ = provider.initialize()
        _ = await enable(provider: provider)
        provider.setProvisionManager(espProvisionMock)

        _ = await getDevice(provider: provider)

        provider.stopDevicesScan()

        let receivedData = await waitForMessage(provider: provider, expectingAction: Actions.exitProvisioning) {
            provider.exitProvisioning()
        }

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.exitProvisioning)
        #expect(receivedData["exit"] as? Bool == false)
        #expect(receivedData["errorCode"] as? Int == ESPProviderErrorCode.notConnected.rawValue)
    }

    // MARK: helpers

    private func waitForNextPendingRequest(on mockDevice: ORESPDeviceMock, requestIndex: Int) async throws -> Request {
        await mockDevice.waitForPendingSendDataRequests(atLeast: 1)
        return try Request(serializedBytes: mockDevice.receivedData[requestIndex])
    }

    private func enable(provider: ESPProvisionProvider) async -> Bool {
        let receivedData = await waitForMessage(provider: provider, expectingAction: Actions.providerEnable) {
            provider.enable()
        }

        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.providerEnable)
        return (receivedData["success"] as! Bool)
    }

    private func getDevice(provider: ESPProvisionProvider) async -> [String: Any] {
        let receivedData = await waitForMessage(provider: provider, expectingAction: Actions.startBleScan) {
            provider.startDevicesScan()
        }

        return (receivedData["devices"] as! [[String:Any]]).first!
    }

    private func connectToDevice(provider: ESPProvisionProvider, deviceId: String) async throws {
        let receivedMessages = await waitForMessages(provider: provider, expectingActions: [Actions.stopBleScan, Actions.connectToDevice]) {
            provider.connectTo(deviceId: deviceId)
        }

        #expect(receivedMessages.count == 2)

        let receivedData = receivedMessages[0]
        #expect(receivedData["provider"] as? String == Providers.espprovision)
        #expect(receivedData["action"] as? String == Actions.stopBleScan)
        #expect(receivedData.count == 2)
    }

    private func waitForMessage(provider: ESPProvisionProvider, expectingAction action: String, afterCalling trigger: @escaping () -> Void) async -> [String:Any] {
        let callbackRecorder = CallbackRecorder()
        provider.sendDataCallback = { data in
            callbackRecorder.record(data)
        }

        let receivedMessages = await callbackRecorder.waitForMessages(matchingActions: [action], after: trigger)
        return receivedMessages[0]
    }

    private func waitForMessages(provider: ESPProvisionProvider, expectingActions actions: [String], afterCalling trigger: @escaping () -> Void) async -> [[String:Any]] {
        let callbackRecorder = CallbackRecorder()
        provider.sendDataCallback = { data in
            callbackRecorder.record(data)
        }

        return await callbackRecorder.waitForMessages(matchingActions: actions, after: trigger)
    }
}
