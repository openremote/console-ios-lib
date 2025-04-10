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

extension String {

    func stringByURLEncoding() -> String? {
        let characters = CharacterSet.urlQueryAllowed.union(CharacterSet(charactersIn: "#"))
        guard let encodedString = self.addingPercentEncoding(withAllowedCharacters: characters) else {
            return nil
        }
        return encodedString
    }

    /// There is no validation that the generated string represents a valid URL.
    /// For instance, no validation is performed on the port if one is provided.
    func buildBaseUrlFromDomain() -> String {
        do {
            let pattern = "^(?:([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6}))$"
            let ipv6NoSchemeNoPort = try NSRegularExpression(pattern: pattern)
            let numberOfMatches = ipv6NoSchemeNoPort.numberOfMatches(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count))
            if numberOfMatches == 1 {
                return "https://[\(self)]"
            }
        } catch let error as NSError {
            print("Error creating NSRegularExpression: \(error)")
        }

        let numberOfMatches: Int
        do {
            let schemePrefix = try NSRegularExpression(pattern: "^[a-zA-Z]+://.*$")
            numberOfMatches = schemePrefix.numberOfMatches(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count))
        } catch let error as NSError {
            numberOfMatches = 0
            print("Error creating NSRegularExpression: \(error)")
        }
        if numberOfMatches == 1 {
            if self.firstIndex(of: ".") != nil || self.firstIndex(of: "[") != nil {
                return self
            } else {
                return "\(self).openremote.app"
            }
        } else if self.firstIndex(of: ".") != nil || self.firstIndex(of: "[") != nil {
            return "https://\(self)"
        }
        return "https://\(self).openremote.app"
    }

}
