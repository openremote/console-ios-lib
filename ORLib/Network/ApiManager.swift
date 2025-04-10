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

import Foundation

public typealias ResponseBlock<T: Codable> = (_ statusCode: Int, _ object: T?, _ error: Error?) -> ()

public enum ApiManagerError: Error {
    case notFound
    case communicationError(Int)
    case parsingError(Int)
}

public protocol ApiManager {
    
    func getConsoleConfig(callback: ResponseBlock<ORConsoleConfig>?)

    func getConsoleConfig() async throws -> ORConsoleConfig?
    
    func getApps(callback: ResponseBlock<[String]>?)
    
    func getApps() async throws -> [String]?
    
    func getAppInfo(appName: String) async throws -> ORAppInfo?

}
