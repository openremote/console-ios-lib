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

struct ESPProvisionURLResolver {
    private static let realmQueryKey = "realm"
    private static let realmPathAllowedCharacters: CharacterSet = {
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "/%")
        return allowedCharacters
    }()

    private let userDefaults: UserDefaults?

    init(userDefaults: UserDefaults? = UserDefaults(suiteName: DefaultsKey.groupEntitlement)) {
        self.userDefaults = userDefaults
    }

    func realm(currentURL: URL?, targetUrl: String?, baseUrl: String?) -> String {
        if let realm = realmFromURLs(currentURL: currentURL, targetUrl: targetUrl, baseUrl: baseUrl) {
            return realm
        }

        if let realm = userDefaults?.string(forKey: DefaultsKey.realmKey),
           !realm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return realm
        }

        return "master"
    }

    func apiURL(baseUrl: String, realm: String) -> URL? {
        guard let appUrl = makeURL(from: baseUrl),
              var components = URLComponents(url: appUrl, resolvingAgainstBaseURL: false),
              let encodedRealm = realm.addingPercentEncoding(withAllowedCharacters: Self.realmPathAllowedCharacters) else {
            return nil
        }

        components.percentEncodedPath = "/api/\(encodedRealm)"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    func apiURL(currentURL: URL?, targetUrl: String?, baseUrl: String?, realm: String) -> URL? {
        let urls = [
            baseUrl.flatMap { makeURL(from: $0) },
            currentURL,
            targetUrl.flatMap { makeURL(from: $0) }
        ]

        for url in urls {
            guard let url,
                  let apiURL = apiURL(baseUrl: url.absoluteString, realm: realm) else {
                continue
            }
            return apiURL
        }

        return nil
    }

    private func realmFromURLs(currentURL: URL?, targetUrl: String?, baseUrl: String?) -> String? {
        let urls = [
            currentURL,
            targetUrl.flatMap { makeURL(from: $0) },
            baseUrl.flatMap { makeURL(from: $0) }
        ]

        for url in urls {
            guard let url,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let realm = components.queryItems?.first(where: { $0.name == Self.realmQueryKey })?.value,
                  !realm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            return realm
        }

        return nil
    }

    private func makeURL(from urlString: String) -> URL? {
        URL(string: urlString) ?? urlString.stringByURLEncoding().flatMap { URL(string: $0) }
    }
}
