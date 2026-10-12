/*
 * Copyright 2026, OpenRemote Inc.
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
import UserNotifications
@testable import ORLib

@MainActor
struct PushNotificationProviderTest {

    @Test func cachedTokenCompletesImmediately() async throws {
        let (provider, _, userDefaults) = try makeProvider()
        userDefaults.set("rotated", forKey: DefaultsKey.fcmTokenKey)
        let start = Date()

        let token = await waitForToken(provider, timeout: 5)

        #expect(token == "rotated")
        #expect(Date().timeIntervalSince(start) < 1)
    }

    @Test func postedTokenCompletesBeforeDeadline() async throws {
        let (provider, center, _) = try makeProvider()
        let start = Date()
        postToken("token1", on: center, after: 0.1)

        let token = await waitForToken(provider, timeout: 5)

        #expect(token == "token1")
        #expect(Date().timeIntervalSince(start) < 1)
    }

    @Test func noTokenCompletesWithNilAtDeadline() async throws {
        let (provider, _, _) = try makeProvider()

        let token = await waitForToken(provider, timeout: 0.1)

        #expect(token == nil)
    }

    /// Apps that still store the token in their own MessagingDelegate never post `Notifications.pushTokenUpdated`
    @Test func tokenStoredWithoutNotificationIsUsedAtDeadline() async throws {
        let (provider, _, userDefaults) = try makeProvider()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            userDefaults.set("token2", forKey: DefaultsKey.fcmTokenKey)
        }

        let token = await waitForToken(provider, timeout: 0.2)

        #expect(token == "token2")
    }

    @Test func completesOnlyOnce() async throws {
        let (provider, center, _) = try makeProvider()
        var completions: [String?] = []

        provider.waitForToken(until: Date().addingTimeInterval(0.1)) { completions.append($0) }
        try await Task.sleep(nanoseconds: 300_000_000)
        center.post(name: Notifications.pushTokenUpdated, object: nil, userInfo: [PushNotificationProvider.tokenKey: "late"])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(completions.count == 1)
        #expect(completions.first == .some(nil))
    }

    @Test func authorizedRegistersAndRepliesWithToken() async throws {
        let authorization = FakeAuthorization(status: .authorized)
        let (provider, center, _) = try makeProvider(authorization)
        postToken("token1", on: center, after: 0.1)

        let response = await enable(provider)

        #expect(authorization.registerCount == 1)
        #expect(authorization.requestCount == 0)
        #expect(response[DefaultsKey.hasPermissionKey] as? Bool == true)
        #expect(token(in: response) == "token1")
    }

    @Test func deniedRepliesImmediatelyWithCachedTokenWithoutRegistering() async throws {
        let authorization = FakeAuthorization(status: .denied)
        let (provider, _, userDefaults) = try makeProvider(authorization)
        userDefaults.set("cached", forKey: DefaultsKey.fcmTokenKey)

        let response = await enable(provider)

        #expect(authorization.registerCount == 0)
        #expect(authorization.requestCount == 0)
        #expect(response[DefaultsKey.hasPermissionKey] as? Bool == false)
        #expect(token(in: response) == "cached")
    }

    @Test func notDeterminedRepliesWithTokenBeforeThePromptIsAnswered() async throws {
        // The user never answers the prompt
        let authorization = FakeAuthorization(status: .notDetermined, grant: nil)
        let (provider, center, _) = try makeProvider(authorization)
        postToken("token1", on: center, after: 0.1)

        let response = await enable(provider)

        #expect(authorization.registerCount == 1)
        #expect(authorization.requestCount == 1)
        #expect(response[DefaultsKey.hasPermissionKey] as? Bool == true)
        #expect(token(in: response) == "token1")
    }

    @Test func notDeterminedReportsDenialGivenBeforeTheToken() async throws {
        let authorization = FakeAuthorization(status: .notDetermined, grant: false)
        let (provider, center, _) = try makeProvider(authorization)
        postToken("token1", on: center, after: 0.1)

        let response = await enable(provider)

        #expect(authorization.registerCount == 1)
        #expect(response[DefaultsKey.hasPermissionKey] as? Bool == false)
        #expect(token(in: response) == "token1")
    }

    private func enable(_ provider: PushNotificationProvider) async -> [String: Any] {
        await withCheckedContinuation { continuation in
            provider.enable(consoleId: nil) { continuation.resume(returning: $0) }
        }
    }

    private func token(in response: [String: Any]) -> String? {
        (response[DefaultsKey.dataKey] as? [String: String?])?[PushNotificationProvider.tokenKey] ?? nil
    }

    private func postToken(_ token: String, on center: NotificationCenter, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            center.post(name: Notifications.pushTokenUpdated, object: nil, userInfo: [PushNotificationProvider.tokenKey: token])
        }
    }

    private func waitForToken(_ provider: PushNotificationProvider, timeout: TimeInterval) async -> String? {
        await withCheckedContinuation { continuation in
            provider.waitForToken(until: Date().addingTimeInterval(timeout)) { continuation.resume(returning: $0) }
        }
    }

    private func makeProvider(
        _ authorization: FakeAuthorization = FakeAuthorization(status: .notDetermined)
    ) throws -> (PushNotificationProvider, NotificationCenter, UserDefaults) {
        let userDefaults = try #require(TemporaryUserDefaults())
        let center = NotificationCenter()
        let provider = PushNotificationProvider(
            center: center,
            userdefaults: userDefaults,
            authorizationStatus: { $0(authorization.status) },
            requestAuthorization: { completion in
                authorization.requestCount += 1
                if let grant = authorization.grant {
                    completion(grant)
                }
            },
            register: { authorization.registerCount += 1 }
        )
        return (provider, center, userDefaults)
    }
}

/// Stands in for the system notification permission and remote notification registration
private final class FakeAuthorization {
    let status: UNAuthorizationStatus
    /// The user's answer to the permission prompt, nil when they never answer
    let grant: Bool?
    var requestCount = 0
    var registerCount = 0

    init(status: UNAuthorizationStatus, grant: Bool? = nil) {
        self.status = status
        self.grant = grant
    }
}
