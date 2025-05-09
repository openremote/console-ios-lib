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

import Testing

@testable import ORLib

@Suite
struct ConfigManagerTest {

    let configManager = ConfigManager(apiManagerFactory: { url in
        FileApiManager(baseUrl: url)
    })

    @Test func test0() async throws {
        var state = try await configManager.setDomain(domain: "test0")
        #expect(state == ConfigManagerState.selectRealm("https://test0.openremote.app", "manager", nil))
        state = try configManager.setRealm(realm: "master")
        #expect(state == ConfigManagerState.complete(ProjectConfig(domain: "https://test0.openremote.app", app: "manager", realm: "master")))
    }

    @Test func test1() async throws {
        let state = try await configManager.setDomain(domain: "test1")
            #expect(state == ConfigManagerState.complete(ProjectConfig(domain: "https://test1.openremote.app", app: "manager", realm: nil)))
    }

    @Test func test2() async throws {
        var state = try await configManager.setDomain(domain: "test2")
        #expect(state == ConfigManagerState.selectRealm("https://test2.openremote.app", "Console 1", nil))
        state = try configManager.setRealm(realm: nil)
        #expect(state == ConfigManagerState.complete(ProjectConfig(domain: "https://test2.openremote.app", app: "Console 1", realm: nil)))
    }

    @Test func test3() async throws {
        var state = try await configManager.setDomain(domain: "test3")
        #expect(state == ConfigManagerState.selectRealm("https://test3.openremote.app", "Console 1", nil))
        state = try configManager.setRealm(realm: "master")
        #expect(state == ConfigManagerState.complete(ProjectConfig(domain: "https://test3.openremote.app", app: "Console 1", realm: "master")))
    }

    @Test func test4() async throws {
        var state = try await configManager.setDomain(domain: "test4")
        #expect(state == ConfigManagerState.selectApp("https://test4.openremote.app", ["Console 1", "Console 2"]))
        state = try configManager.setApp(app: "Console 1")
        #expect(state == ConfigManagerState.selectRealm("https://test4.openremote.app", "Console 1", nil))
        state = try configManager.setRealm(realm: nil)
        #expect(state == ConfigManagerState.complete(ProjectConfig(domain: "https://test4.openremote.app", app: "Console 1", realm: nil)))
    }

    @Test func test5() async throws {
        var state = try await configManager.setDomain(domain: "test5")
        #expect(state == ConfigManagerState.selectApp("https://test5.openremote.app", nil))
        state = try configManager.setApp(app: "Console")
        #expect(state == ConfigManagerState.selectRealm("https://test5.openremote.app", "Console", nil))
        state = try configManager.setRealm(realm: "master")
        #expect(state == ConfigManagerState.complete(ProjectConfig(domain: "https://test5.openremote.app", app: "Console", realm: "master")))
    }

    @Test func test6() async throws {
        var state = try await configManager.setDomain(domain: "test6")
        #expect(state == ConfigManagerState.selectApp("https://test6.openremote.app", ["Console 1", "Console 2"]))
        state = try configManager.setApp(app: "Console 2")
        #expect(state == ConfigManagerState.selectRealm("https://test6.openremote.app", "Console 2", nil))
        state = try configManager.setRealm(realm: "master")
        #expect(state == ConfigManagerState.complete(ProjectConfig(domain: "https://test6.openremote.app", app: "Console 2", realm: "master")))
    }
    
    @Test func test7() async throws {
        var state = try await configManager.setDomain(domain: "test7")
        #expect(state == ConfigManagerState.selectApp("https://test7.openremote.app", ["Console 1", "Console 2"]))
        state = try configManager.setApp(app: "Console 1")
        #expect(state == ConfigManagerState.selectRealm("https://test7.openremote.app", "Console 1", ["master1", "master2"]))
        state = try configManager.setRealm(realm: "master1")
        #expect(state == ConfigManagerState.complete(ProjectConfig(domain: "https://test7.openremote.app", app: "Console 1", realm: "master1")))
    }

    @Test func test8() async throws {
        var state = try await configManager.setDomain(domain: "test8")
        #expect(state == ConfigManagerState.selectApp("https://test8.openremote.app", ["Console 1", "Console 2"]))
        state = try configManager.setApp(app: "Console 1")
        #expect(state == ConfigManagerState.selectRealm("https://test8.openremote.app", "Console 1", ["master1", "master2"]))
        state = try configManager.setRealm(realm: "master1")
        #expect(state == ConfigManagerState.complete(ProjectConfig(domain: "https://test8.openremote.app", app: "Console 1", realm: "master1")))
    }

    
    @Test func test8_GoBack() async throws {
        var state = try await configManager.setDomain(domain: "test8")
        #expect(state == ConfigManagerState.selectApp("https://test8.openremote.app", ["Console 1", "Console 2"]))
        state = try configManager.setApp(app: "Console 1")
        #expect(state == ConfigManagerState.selectRealm("https://test8.openremote.app", "Console 1", ["master1", "master2"]))
        state = try configManager.setRealm(realm: "master1")
        #expect(state == ConfigManagerState.complete(ProjectConfig(domain: "https://test8.openremote.app", app: "Console 1", realm: "master1")))
        state = try configManager.setRealm(realm: "master2")
        #expect(state == ConfigManagerState.complete(ProjectConfig(domain: "https://test8.openremote.app", app: "Console 1", realm: "master2")))
    }
    
    @Test func test9() async throws {
        var state = try await configManager.setDomain(domain: "test9")
        #expect(state == ConfigManagerState.selectApp("https://test9.openremote.app", ["Console 1", "Console 2"]))
        state = try configManager.setApp(app: "Console 1")
        #expect(state == ConfigManagerState.selectRealm("https://test9.openremote.app", "Console 1", ["master1", "master2"]))
        state = try configManager.setRealm(realm: "master1")
        #expect(state == ConfigManagerState.complete(ProjectConfig(domain: "https://test9.openremote.app", app: "Console 1", realm: "master1")))
    }

    @Test func test10() async throws {
        var state = try await configManager.setDomain(domain: "test10")
        #expect(state == ConfigManagerState.selectApp("https://test10.openremote.app", ["Console 1", "Console 2"]))
        state = try configManager.setApp(app: "Console 1")
        #expect(state == ConfigManagerState.selectRealm("https://test10.openremote.app", "Console 1", ["master3", "master4"]))
        state = try configManager.setRealm(realm: "master3")
        #expect(state == ConfigManagerState.complete(ProjectConfig(domain: "https://test10.openremote.app", app: "Console 1", realm: "master3")))
    }

    @Test func test11() async throws {
        var state = try await configManager.setDomain(domain: "test11")
        #expect(state == ConfigManagerState.selectRealm("https://test11.openremote.app", "Console 2", nil))
        state = try configManager.setRealm(realm: "master3")
        #expect(state == ConfigManagerState.complete(ProjectConfig(domain: "https://test11.openremote.app", app: "Console 2", realm: "master3")))
    }

    @Test func test12() async throws {
        var state = try await configManager.setDomain(domain: "test12")
        #expect(state == ConfigManagerState.selectApp("https://test12.openremote.app", ["Console 1", "Console 2"]))
        state = try configManager.setApp(app: "Console 1")
        #expect(state == ConfigManagerState.selectRealm("https://test12.openremote.app", "Console 1", nil))
        state = try configManager.setRealm(realm: "master1")
        #expect(state == ConfigManagerState.complete(ProjectConfig(domain: "https://test12.openremote.app", app: "Console 1", realm: "master1")))
    }

    @Test func test13() async throws {
        var state = try await configManager.setDomain(domain: "test13")
        #expect(state == ConfigManagerState.selectRealm("https://test13.openremote.app", "Console 1", nil))
        state = try configManager.setRealm(realm: "master")
        #expect(state == ConfigManagerState.complete(ProjectConfig(domain: "https://test13.openremote.app", app: "Console 1", realm: "master")))
    }

}
