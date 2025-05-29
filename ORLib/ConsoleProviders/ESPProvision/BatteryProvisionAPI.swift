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

struct BatteryProvisionAPIREST: BatteryProvisionAPI {
    private static let logger = Logger(
           subsystem: Bundle.main.bundleIdentifier!,
           category: String(describing: ESPProvisionProvider.self)
       )

    init(apiURL: URL) {
        self.apiURL = apiURL
    }

    private var apiURL: URL

    func provision(deviceId: String, password: String, token: String) async throws -> String {
        /*
         curl -v http://localhost:8080/api/master/rest/battery -d'{
         "model": 0,
         "deviceId": "123456789ABC",
         "password": "s3cr3t"
         }' -H'Content-type: application/json' -H "Authorization: Bearer $ACCESS_TOKEN"
         */

        let url: URL
        if #available(iOS 16.0, *) {
            url = apiURL.appending(path: "/rest/battery")
        } else {
            url = apiURL.appendingPathComponent("/rest/battery")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            request.httpBody = try JSONEncoder().encode(ProvisionRequestBody(deviceId: deviceId, password: password))
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                Self.logger.error("Received a non HTTP response")
                throw BatteryProvisionAPIError.communicationError("Invalid response format")
            }
            guard (200...299).contains(response.statusCode) else {
                Self.logger.info("HTTP call error, status code \(response.statusCode)")
                switch response.statusCode {
                case 401:
                    throw BatteryProvisionAPIError.unauthorized
                case 409:
                    throw BatteryProvisionAPIError.businessError
                default:
                    throw BatteryProvisionAPIError.unknownError
                }
            }
            if let mimeType = response.mimeType,
                mimeType == "application/json",
                let dataString = String(data: data, encoding: .utf8) {
                   Self.logger.info("Received JSON response from server \(dataString)")
                    let assetId = try JSONDecoder().decode(ProvisionResponseBody.self, from: data).assetId
                    return assetId
            }
        } catch {
            print(error.localizedDescription)
            throw BatteryProvisionAPIError.genericError(error)
        }
        throw BatteryProvisionAPIError.unknownError
    }

    struct ProvisionRequestBody: Encodable {
        var deviceId: String
        var password: String
    }

    struct ProvisionResponseBody: Decodable {
        var assetId: String
    }
}

enum BatteryProvisionAPIError: Error {
    case unauthorized
    case communicationError(String)
    case businessError
    case genericError(Error)
    case unknownError
}
