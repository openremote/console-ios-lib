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

struct DeviceProvisionAPIREST: DeviceProvisionAPI {

    init(apiURL: URL) {
        self.apiURL = apiURL
    }

    private var apiURL: URL

    func provision(modelName: String, deviceId: String, password: String, token: String) async throws -> String {
        /*
         curl -v http://localhost:8080/api/master/rest/battery -d'{
         "model": 0,
         "deviceId": "123456789ABC",
         "password": "s3cr3t"
         }' -H'Content-type: application/json' -H "Authorization: Bearer $ACCESS_TOKEN"
         */

        let url: URL
        if #available(iOS 16.0, *) {
            url = apiURL.appending(path: "/rest/device")
        } else {
            url = apiURL.appendingPathComponent("/rest/device")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            request.httpBody = try JSONEncoder().encode(ProvisionRequestBody(modelName: modelName, deviceId: deviceId, password: password))
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                ORLogger.espprovisioning.error("Received a non HTTP response")
                throw DeviceProvisionAPIError.communicationError("Invalid response format")
            }
            guard (200...299).contains(response.statusCode) else {
                ORLogger.espprovisioning.warning("HTTP call error, status code \(response.statusCode)")
                switch response.statusCode {
                case 401:
                    throw DeviceProvisionAPIError.unauthorized
                case 409:
                    throw DeviceProvisionAPIError.businessError
                default:
                    throw DeviceProvisionAPIError.unknownError
                }
            }
            if let mimeType = response.mimeType,
                mimeType == "application/json",
                let dataString = String(data: data, encoding: .utf8) {
                ORLogger.espprovisioning.info("Received JSON response from server \(dataString)")
                    let assetId = try JSONDecoder().decode(ProvisionResponseBody.self, from: data).assetId
                    return assetId
            }
        } catch {
            ORLogger.espprovisioning.error("\(error.localizedDescription)")
            throw DeviceProvisionAPIError.genericError(error)
        }
        throw DeviceProvisionAPIError.unknownError
    }

    struct ProvisionRequestBody: Encodable {
        var modelName: String
        var deviceId: String
        var password: String
    }

    struct ProvisionResponseBody: Decodable {
        var assetId: String
    }
}

enum DeviceProvisionAPIError: Error {
    case unauthorized
    case communicationError(String)
    case businessError
    case genericError(Error)
    case unknownError
}
