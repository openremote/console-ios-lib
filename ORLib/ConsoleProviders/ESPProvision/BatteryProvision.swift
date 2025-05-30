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
import os
import RandomPasswordGenerator

protocol BatteryProvisionAPI {
    func provision(deviceId: String, password: String, token: String) async throws -> String
}

class BatteryProvision {
    private static let logger = Logger(
           subsystem: Bundle.main.bundleIdentifier!,
           category: String(describing: ESPProvisionProvider.self)
       )

    private var deviceConnection: DeviceConnection?
    var callbackChannel: CallbackChannel?

    var apiURL: URL
    var batteryProvisionAPI: BatteryProvisionAPI

    var backendConnectionTimeout: TimeInterval = 60

    init (deviceConnection: DeviceConnection?, callbackChannel: CallbackChannel?, apiURL: URL) {
        self.deviceConnection = deviceConnection
        self.callbackChannel = callbackChannel
        self.apiURL = apiURL
        self.batteryProvisionAPI = BatteryProvisionAPIREST(apiURL: apiURL)
    }

    public func provision(userToken: String) async {
        guard deviceConnection?.isConnected ?? false else {
            sendProvisionDeviceStatus(connected: false, error: .notConnected, errorMessage: "No connection established to device")
            return
        }

        do {
            let deviceInfo = try await deviceConnection!.getDeviceInfo()
            Self.logger.info("Device ID retrieved from firmware: \(deviceInfo.deviceId)")

            let password = try generatePassword()

            let assetId = try await batteryProvisionAPI.provision(deviceId: deviceInfo.deviceId, password: password, token: userToken)
            let userName = deviceInfo.deviceId.lowercased(with: Locale(identifier: "en"))

            try await deviceConnection!.sendOpenRemoteConfig(mqttBrokerUrl: mqttURL, mqttUser: userName, mqttPassword: password, assetId: assetId)

            var status = BackendConnectionStatus.connecting
            // TODO: what about other status values ? Is status connecting while it connects ? or disconnected ? -> test with real device
            let startTime = Date.now
            while (status != .connected) {
                if Date.now.timeIntervalSince(startTime) > backendConnectionTimeout {
                    sendProvisionDeviceStatus(connected: false, error: .timeoutError, errorMessage: "Timeout waiting for backend to get connected")
                    return
                }
                status = try await deviceConnection!.getBackendConnectionStatus()
                Self.logger.info("ModuleOne reported connection status \(String(describing: status))")
            }

            // TODO: review, if we're out of the loop, this is always true

            if status == .connected {
                sendProvisionDeviceStatus(connected: true)
            }
        } catch let error as ESPProviderError {
            sendProvisionDeviceStatus(connected: false, error: error.errorCode, errorMessage: error.errorMessage)
        } catch let error as RandomPasswordGeneratorError {
            sendProvisionDeviceStatus(connected: false, error: .genericError, errorMessage: error.localizedDescription)
        } catch let error as BatteryProvisionAPIError {
            let (errorCode, errorMessage) = mapBatteryProvisionAPIError(error)
            sendProvisionDeviceStatus(connected: false, error: errorCode, errorMessage: errorMessage)
        } catch {
            sendProvisionDeviceStatus(connected: false, error: .genericError, errorMessage: error.localizedDescription)
        }
    }

    private func mapBatteryProvisionAPIError(_ error: BatteryProvisionAPIError) -> (ESPProviderErrorCode, String?) {
        switch error {
        case .businessError, .unknownError:
            return (ESPProviderErrorCode.genericError, nil)
        case .genericError(let error):
            return (ESPProviderErrorCode.genericError, error.localizedDescription)
        case .unauthorized:
            return (ESPProviderErrorCode.securityError, nil)
        case .communicationError(let errorMessage):
            return (ESPProviderErrorCode.communicationError, errorMessage)
        }
    }

    private func sendProvisionDeviceStatus(connected: Bool, error: ESPProviderErrorCode? = nil, errorMessage: String? = nil) {
        var data: [String: Any] = ["connected": connected]
        if let error {
            data["errorCode"] = error.rawValue
        }
        if let errorMessage {
            data["errorMessage"] = errorMessage
        }
        callbackChannel?.sendMessage(action: Actions.provisionDevice, data: data)
    }

    private func generatePassword() throws -> String {
        // Using https://github.com/yukanamori/RandomPasswordGenerator.git
        let generator = RandomPasswordGenerator(length: 16, characterTypes: [.digits, .uppercase, .lowercase])
        return try generator.generate()
    }

    private var mqttURL: String {
        // TODO: is this OK or do we want to get the mqtt url from the server

        return "mqtts://\(apiURL.host ?? "localhost"):8883"
    }
}
