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
@testable import ORLib

class FileApiManager: ApiManager {

    let decoder = JSONDecoder()

    private var fixture: Fixture
    
    public init(baseUrl: String) {
        let pattern = #"https://(?<domain>.*)\.openremote\.app"#
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsrange = NSRange(baseUrl.startIndex..<baseUrl.endIndex, in: baseUrl)
            if let match = regex.firstMatch(in: baseUrl, options: [], range: nsrange) {
                let nsrange = match.range(withName: "domain")
                if nsrange.location != NSNotFound, let range = Range(nsrange, in: baseUrl) {
                    let domain = baseUrl[range]
                    if let fixtureFile = Bundle(for: FileApiManager.self).url(forResource: String(domain), withExtension: "json") {
                        if let fixtureData = try? Data(contentsOf: fixtureFile as URL) {
                            do {
                                fixture = try self.decoder.decode(Fixture.self, from: fixtureData)
                                return
                            } catch {
                                ORLogger.test.error("\(error)")
                            }
                        }
                    }
                }
            }
        } catch {
            // Will use default value below
        }
        fixture = Fixture()
    }

    
    func getConsoleConfig(callback: ResponseBlock<ORConsoleConfig>?) {
    }

    public func getConsoleConfig() async throws -> ORConsoleConfig? {
        if let returnCode = fixture.consoleConfigReturnCode {
            throw ApiManagerError.communicationError(returnCode)
        }
        return fixture.consoleConfig
    }

    public func getApps(callback: ResponseBlock<[String]>?) {
    }
    
    public func getApps() async throws -> [String]? {
        if let returnCode = fixture.appsReturnCode {
            throw ApiManagerError.communicationError(returnCode)
        }
        return fixture.apps
    }

    public func getAppInfo(appName: String) async throws -> ORAppInfo? {
        if let returnCode = fixture.appsInfoReturnCode {
            throw ApiManagerError.communicationError(returnCode)
        }
        return fixture.appsInfo?[appName]
    }

}
