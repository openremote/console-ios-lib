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

public struct ProjectConfig: Codable, Equatable {
    public var id: String
    var projectName = "TODO"

    public var domain: String
    public var app: String
    public var realm: String?
    
    public var providers: [String]?
    
    public var baseURL: String {
        return domain
    }
    
    public var targetUrl: String {
        let consoleProviders = self.providers?.joined(separator: " ") ?? "geofence push storage"
        if let realm = realm {
            return "\(baseURL)/\(app)/?realm=\(realm)&consoleProviders=\(consoleProviders)&consoleAutoEnable=true#!geofences"
        } else {
            return "\(baseURL)/\(app)/?consoleProviders=\(consoleProviders)&consoleAutoEnable=true#!geofences"
        }
        
        // TODO: what's that &consoleAutoEnable=true#!geofences part of the URL for ?
    }
    
    
    public init() {
        id = UUID().uuidString
        domain = "demo" // TODO: How to manage this ? Should we have a default init ?
        app = "manager"
    }
    
    public init(domain: String, app: String, realm: String?) {
        id = UUID().uuidString
        self.domain = domain
        self.app = app
        self.realm = realm
    }
    
    public static func ==(lhs: ProjectConfig, rhs: ProjectConfig) -> Bool {
        return lhs.domain == rhs.domain && lhs.app == rhs.app && lhs.realm == rhs.realm && lhs.providers == rhs.providers
    }

}
