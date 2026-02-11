/*
 * Copyright 2025, OpenRemote Inc.
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
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import Foundation
import CoreBluetooth
import ESPProvision
import os

typealias SendDataCallback = ([String: Any]) -> (Void)

class ESPProvisionProvider: NSObject {
    public static let espProvisionDisabledKey = "espProvisionDisabled"

    let userdefaults = UserDefaults(suiteName: DefaultsKey.groupEntitlement)
    let version = "beta"

    private var searchDeviceTimeout: TimeInterval = 120
    private var searchDeviceMaxIterations = 25

    private var searchWifiTimeout: TimeInterval = 120
    private var searchWifiMaxIterations = 25

    private let deviceRegistry: DeviceRegistry

    private var deviceConnection: DeviceConnection?

    private var wifiProvisioner: WifiProvisioner?

    private var apiURL = URL(string: "http://localhost:8080/api/master")!


    private var blePermissionsChecker: BLEPermissionsChecker?

    typealias DeviceProvisionFactory = () -> DeviceProvision
    private lazy var deviceProvisionFactory: DeviceProvisionFactory = {
        DeviceProvision(deviceConnection: self.deviceConnection, callbackChannel: self.callbackChannel, apiURL: self.apiURL)
    }

    private var callbackChannel: CallbackChannel?
    var sendDataCallback: SendDataCallback? {
        didSet {
            if let sendDataCallback {
                callbackChannel = CallbackChannel(sendDataCallback: sendDataCallback, provider: Providers.espprovision)
                deviceRegistry.callbackChannel = callbackChannel
                deviceConnection?.callbackChannel = callbackChannel
                wifiProvisioner?.callbackChannel = callbackChannel
            }
        }
    }

    public override init() {
        self.deviceRegistry = DeviceRegistry(searchDeviceTimeout: searchDeviceTimeout, searchDeviceMaxIterations: searchDeviceMaxIterations)
        super.init()
    }

    public convenience init(apiURL: URL = URL(string:"http://localhost:8080/api/master")!) {
        self.init()
        self.apiURL = apiURL
    }

    // MARK: Standard provider lifecycle

    public func initialize() -> [String: Any] {
        return [
            DefaultsKey.actionKey: Actions.providerInit,
            DefaultsKey.providerKey: Providers.espprovision,
            DefaultsKey.versionKey: version,
            DefaultsKey.requiresPermissionKey: true,
            DefaultsKey.hasPermissionKey: CBCentralManager.authorization == .allowedAlways,
            DefaultsKey.successKey: true,
            DefaultsKey.enabledKey: false,
            DefaultsKey.disabledKey: userdefaults?.bool(forKey: ESPProvisionProvider.espProvisionDisabledKey) ?? false
            // Question: this was BleProvider.bluetoothDisabledKey -> translates to bluetoothDisabled key -> is this the provider or BLE
        ]
    }

    public func enable() {
        deviceRegistry.enable()
        blePermissionsChecker = BLEPermissionsChecker(callbackChannel: callbackChannel)
        Task {
            let permission = await blePermissionsChecker?.checkPermissions()
            userdefaults?.removeObject(forKey: ESPProvisionProvider.espProvisionDisabledKey)
            userdefaults?.synchronize()

            callbackChannel?.sendMessage(action: Actions.providerEnable, data: [
                DefaultsKey.hasPermissionKey: permission ?? false,
                DefaultsKey.successKey: true
            ])
        }
    }

    public func disable() -> [String: Any] {
        deviceRegistry.disable()

        disconnectFromDevice()
        // This eventually calls ESPBLEDelegate.peripheralDisconnected that sets device, deviceId and configChannel to nil

        userdefaults?.set(true, forKey: ESPProvisionProvider.espProvisionDisabledKey)
        userdefaults?.synchronize()
        return [
            DefaultsKey.actionKey: Actions.providerDisable,
            DefaultsKey.providerKey: Providers.espprovision
        ]
    }

    // MARK: Device scan

    public func startDevicesScan(prefix: String? = nil) {
        deviceRegistry.startDevicesScan(prefix: prefix)
    }

    public func stopDevicesScan() {
        deviceRegistry.stopDevicesScan()
    }

    // MARK: Device connect/disconnect

    public func connectTo(deviceId idToConnectTo: String, pop: String? = nil, username: String? = nil) {
        if deviceConnection == nil {
            deviceConnection = DeviceConnection(deviceRegistry: deviceRegistry, callbackChannel: callbackChannel)
        }
        deviceConnection!.connectTo(deviceId: idToConnectTo, pop: pop, username: username)
    }

    public func disconnectFromDevice() {
        wifiProvisioner?.stopWifiScan()
        deviceConnection?.disconnectFromDevice()
    }

    public func exitProvisioning() {
        guard deviceConnection?.isConnected ?? false else {
            sendExitProvisioningError(.notConnected, errorMessage: "No connection established to device")
            return
        }
        Task {
            do {
                try await deviceConnection!.exitProvisioning()
                callbackChannel?.sendMessage(action: Actions.exitProvisioning, data: ["exit": true])
            } catch let error as ESPProviderError {
                sendExitProvisioningError(error.errorCode, errorMessage: error.errorMessage)
            } catch {
                sendExitProvisioningError(.genericError, errorMessage: error.localizedDescription)
            }
        }
    }

    private func sendExitProvisioningError(_ error: ESPProviderErrorCode, errorMessage: String?) {
        var data: [String: Any] = ["exit": false, "errorCode": error.rawValue]
        if let errorMessage {
            data["errorMessage"] = errorMessage
        }
        callbackChannel?.sendMessage(action: Actions.exitProvisioning, data: data)
    }

    // MARK: Wifi scan

    public func startWifiScan() {
        if wifiProvisioner == nil {
            wifiProvisioner = WifiProvisioner(deviceConnection: deviceConnection, callbackChannel: callbackChannel, searchWifiTimeout: searchWifiTimeout, searchWifiMaxIterations: searchWifiMaxIterations)
        }
        wifiProvisioner!.startWifiScan()
    }

    public func stopWifiScan() {
        wifiProvisioner?.stopWifiScan()
    }

    public func sendWifiConfiguration(ssid: String, password: String) {
        if wifiProvisioner == nil {
            wifiProvisioner = WifiProvisioner(deviceConnection: deviceConnection, callbackChannel: callbackChannel, searchWifiTimeout: searchWifiTimeout, searchWifiMaxIterations: searchWifiMaxIterations)
        }
        wifiProvisioner?.sendWifiConfiguration(ssid: ssid, password: password)
    }

    // MARK: OR Configuration

    public func provisionDevice(userToken: String) {
        guard deviceConnection?.isConnected ?? false else {
            sendProvisionDeviceError(.notConnected, errorMessage: "No connection established to device")
            return
        }
        Task {
            do {
                let deviceProvision = deviceProvisionFactory()

                try await deviceProvision.provision(userToken: userToken)
            } catch let error as ESPProviderError {
                sendExitProvisioningError(error.errorCode, errorMessage: error.errorMessage)
            } catch {
                sendExitProvisioningError(.genericError, errorMessage: error.localizedDescription)
            }
        }
    }

    private func sendProvisionDeviceError(_ error: ESPProviderErrorCode, errorMessage: String?) {
        var data: [String: Any] = ["errorCode": error.rawValue]
        if let errorMessage {
            data["errorMessage"] = errorMessage
        }
        callbackChannel?.sendMessage(action: Actions.provisionDevice, data: data)
    }
}


#if DEBUG
// TODO: see https://stackoverflow.com/a/60267724 for improvement
extension ESPProvisionProvider {
    public convenience init(searchDeviceTimeout: TimeInterval = 120, searchDeviceMaxIterations: Int = 25,
                            searchWifiTimeout: TimeInterval = 120, searchWifiMaxIterations: Int = 25,
                            deviceProvisionAPI: DeviceProvisionAPI? = nil, backendConnectionTimeout: TimeInterval? = nil,
                            apiURL: URL = URL(string:"http://localhost:8080/api/master")!) {
        self.init()
        self.searchDeviceTimeout = searchDeviceTimeout
        self.searchDeviceMaxIterations = searchDeviceMaxIterations
        self.deviceRegistry.searchDeviceMaxIterations = searchDeviceMaxIterations
        self.deviceRegistry.searchDeviceTimeout = searchDeviceTimeout

        self.searchWifiTimeout = searchWifiTimeout
        self.searchWifiMaxIterations = searchWifiMaxIterations

        self.deviceProvisionFactory = {
            let deviceProvision = DeviceProvision(deviceConnection: self.deviceConnection, callbackChannel: self.callbackChannel, apiURL: apiURL)
            if let deviceProvisionAPI {
                deviceProvision.deviceProvisionAPI = deviceProvisionAPI
            }
            if let backendConnectionTimeout {
                deviceProvision.backendConnectionTimeout = backendConnectionTimeout
            }
            return deviceProvision
        }
    }

    func setProvisionManager(_ provisionManager: ORESPProvisionManager) {
        self.deviceRegistry.provisionManager = provisionManager
    }

    var  bleScanning: Bool {
        self.deviceRegistry.bleScanning
    }

    var wifiScanning: Bool {
        self.wifiProvisioner?.wifiScanning ?? false
    }
}
#endif

public struct ESPProviderError: Error {
    var errorCode: ESPProviderErrorCode
    var errorMessage: String?
}

public enum ESPProviderErrorCode: Int {
    case unknownDevice = 100

    case bleCommunicationError = 200

    case notConnected = 300
    case communicationError = 301

    case securityError = 400

    case wifiConfigurationError = 500
    case wifiCommunicationError = 501
    case wifiAuthenticationError = 502
    case wifiNetworkNotFound = 503

    case timeoutError = 600

    case genericError = 10000
}

public enum ESPProviderConnectToDeviceStatus {
    public static let connected = "connected"
    public static let disconnected = "disconnected"
    public static let connectionError = "connectionError"
}
