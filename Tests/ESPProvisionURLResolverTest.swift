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
import Testing
@testable import ORLib

struct ESPProvisionURLResolverTest {

    @Test func urlRealmWinsOverStoredRealm() throws {
        let (suiteName, userDefaults) = try makeUserDefaults()
        userDefaults.set("master", forKey: DefaultsKey.realmKey)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let resolver = ESPProvisionURLResolver(userDefaults: userDefaults)

        #expect(resolver.realm(currentURL: nil,
                               targetUrl: "https://example.com/manager/?realm=tenantA",
                               baseUrl: "https://example.com") == "tenantA")
    }

    @Test func currentURLWinsOverTargetUrlAndBaseUrl() throws {
        let (suiteName, userDefaults) = try makeUserDefaults()
        userDefaults.set("stored", forKey: DefaultsKey.realmKey)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let resolver = ESPProvisionURLResolver(userDefaults: userDefaults)

        #expect(resolver.realm(currentURL: URL(string: "https://example.com/manager/?realm=current"),
                               targetUrl: "https://example.com/manager/?realm=target",
                               baseUrl: "https://example.com/?realm=base") == "current")
    }

    @Test func blankUrlRealmFallsBackToStoredRealm() throws {
        let (suiteName, userDefaults) = try makeUserDefaults()
        userDefaults.set("stored", forKey: DefaultsKey.realmKey)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let resolver = ESPProvisionURLResolver(userDefaults: userDefaults)

        #expect(resolver.realm(currentURL: URL(string: "https://example.com/manager/?realm=%20"),
                               targetUrl: "https://example.com/manager/?realm=",
                               baseUrl: "https://example.com") == "stored")
    }

    @Test func missingUrlAndStoredRealmFallsBackToMaster() {
        let resolver = ESPProvisionURLResolver(userDefaults: nil)

        #expect(resolver.realm(currentURL: nil, targetUrl: nil, baseUrl: nil) == "master")
    }

    @Test func apiURLPreservesOriginAndRemovesAppPathQueryAndFragment() throws {
        let resolver = ESPProvisionURLResolver(userDefaults: nil)

        let apiURL = try #require(resolver.apiURL(baseUrl: "https://example.com:8443/manager/?realm=tenantA#fragment",
                                                 realm: "tenantA"))

        #expect(apiURL.absoluteString == "https://example.com:8443/api/tenantA")
    }

    @Test func apiURLEncodesRealmAsSinglePathSegment() throws {
        let resolver = ESPProvisionURLResolver(userDefaults: nil)

        let apiURL = try #require(resolver.apiURL(baseUrl: "https://example.com", realm: "tenant/a b%"))

        #expect(apiURL.absoluteString == "https://example.com/api/tenant%2Fa%20b%25")
    }

    private func makeUserDefaults() throws -> (suiteName: String, userDefaults: UserDefaults) {
        let suiteName = "ESPProvisionURLResolverTest.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return (suiteName, userDefaults)
    }
}
