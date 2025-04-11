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

import Testing
@testable import ORLib

/// Tests to understand how URL parsing works
struct URLTest {

    @Test func FQDNWithScheme() async throws {
        let url = URL(string: "https://www.example.com")
        #expect(url != nil)
        #expect(url!.host == "www.example.com")
        #expect(url!.scheme == "https")
        #expect(url!.port == nil)
    }

    @Test func FQDNWithCustomScheme() async throws {
        let url = URL(string: "myscheme://www.example.com")
        #expect(url != nil)
        #expect(url!.host == "www.example.com")
        #expect(url!.scheme == "myscheme")
        #expect(url!.port == nil)
    }

    @Test func FQDNWithSchemeAndPort() async throws {
        let url = URL(string: "https://www.example.com:1234")
        #expect(url != nil)
        #expect(url!.host == "www.example.com")
        #expect(url!.scheme == "https")
        #expect(url!.port == 1234)
    }

    @Test func FQDNNoScheme() async throws {
        let url = URL(string: "www.example.com")
        #expect(url != nil)
        #expect(url!.host == nil)
        #expect(url!.scheme == nil)
        #expect(url!.port == nil)
    }

    @Test func hostnameWithScheme() async throws {
        let url = URL(string: "http://example")
        #expect(url != nil)
        #expect(url!.host == "example")
        #expect(url!.scheme == "http")
        #expect(url!.port == nil)
    }

    @Test func hostnameNoScheme() async throws {
        let url = URL(string: "example")
        #expect(url != nil)
        #expect(url!.host == nil)
        #expect(url!.scheme == nil)
        #expect(url!.port == nil)
    }

    @Test func ipWithScheme() async throws {
        let url = URL(string: "http://192.168.1.1")
        #expect(url != nil)
        #expect(url!.host == "192.168.1.1")
        #expect(url!.scheme == "http")
        #expect(url!.port == nil)
    }

    @Test func ipNoScheme() async throws {
        let url = URL(string: "192.168.1.1")
        #expect(url != nil)
        #expect(url!.host == nil)
        #expect(url!.scheme == nil)
        #expect(url!.port == nil)
    }

    /// !  URL does not validate it's an IP address
    @Test func invalidIpNoScheme() async throws {
        let url = URL(string: "432.168.1.1")
        #expect(url != nil)
        #expect(url!.host == nil)
        #expect(url!.scheme == nil)
        #expect(url!.port == nil)
    }
}
