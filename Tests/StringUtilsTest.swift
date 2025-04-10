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

struct StringUtilsTest {

    @Test func fqdnWithScheme() async throws {
        #expect("http://www.example.com".buildBaseUrlFromDomain() == "http://www.example.com")
        #expect("https://www.example.com".buildBaseUrlFromDomain() == "https://www.example.com")
    }

    @Test func fqdnNoScheme() async throws {
        #expect("www.example.com".buildBaseUrlFromDomain() == "https://www.example.com")
    }

    @Test func fqdnAndPortWithScheme() async throws {
        #expect("http://www.example.com:8080".buildBaseUrlFromDomain() == "http://www.example.com:8080")
        #expect("https://www.example.com:443".buildBaseUrlFromDomain() == "https://www.example.com:443")
    }

    @Test func fqdnAndPortNoScheme() async throws {
        #expect("www.example.com:8080".buildBaseUrlFromDomain() == "https://www.example.com:8080")
    }

    @Test func hostnameNoScheme() async throws {
        #expect("example".buildBaseUrlFromDomain() == "https://example.openremote.app")
    }

    @Test func ipAddressWithScheme () async throws {
        #expect("http://192.168.1.1".buildBaseUrlFromDomain() == "http://192.168.1.1")
    }

    @Test func ipAddressAndPortWithScheme () async throws {
        #expect("http://192.168.1.1:8080".buildBaseUrlFromDomain() == "http://192.168.1.1:8080")
    }

    @Test func ipAddressNoScheme () async throws {
        #expect("192.168.1.1".buildBaseUrlFromDomain() == "https://192.168.1.1")
    }

    @Test func ipAddressAndPortNoScheme () async throws {
        #expect("192.168.1.1:8080".buildBaseUrlFromDomain() == "https://192.168.1.1:8080")
    }

    @Test func ipv6AddressWithScheme () async throws {
        #expect("http://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]".buildBaseUrlFromDomain() == "http://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]")
    }

    @Test func ipv6AddressAndPortWithScheme () async throws {
        #expect("http://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]:8080".buildBaseUrlFromDomain() == "http://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]:8080")
    }

    @Test func ipv6AddressNoScheme () async throws {
        #expect("2001:0db8:85a3:0000:0000:8a2e:0370:7334".buildBaseUrlFromDomain() == "https://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]")
        #expect("[2001:0db8:85a3:0000:0000:8a2e:0370:7334]".buildBaseUrlFromDomain() == "https://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]")
    }

    @Test func ipv6AddressAndPortNoScheme () async throws {
        #expect("[2001:0db8:85a3:0000:0000:8a2e:0370:7334]:8080".buildBaseUrlFromDomain() == "https://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]:8080")
    }

    @Test func ipv6CompressedAddressWithScheme () async throws {
        #expect("http://[2001:db8:85a3::8a2e:370:7334]".buildBaseUrlFromDomain() == "http://[2001:db8:85a3::8a2e:370:7334]")
    }

    @Test func ipv6CompressedAddressAndPortWithScheme () async throws {
        #expect("http://[2001:db8:85a3::8a2e:370:7334]:8080".buildBaseUrlFromDomain() == "http://[2001:db8:85a3::8a2e:370:7334]:8080")
    }

    @Test func ipv6CompressedAddressNoScheme () async throws {
        #expect("2001:db8:85a3::8a2e:370:7334".buildBaseUrlFromDomain() == "https://[2001:db8:85a3::8a2e:370:7334]")
        #expect("[2001:db8:85a3::8a2e:370:7334]".buildBaseUrlFromDomain() == "https://[2001:db8:85a3::8a2e:370:7334]")
    }

    @Test func ipv6CompressedAddressAndPortNoScheme () async throws {
        #expect("[2001:db8:85a3::8a2e:370:7334]:8080".buildBaseUrlFromDomain() == "https://[2001:db8:85a3::8a2e:370:7334]:8080")
    }
}
