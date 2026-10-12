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
import UIKit
import UserNotifications
@testable import ORLib

struct ORNotificationHandlerTest {

    private final class Recorder {
        var delivered: [(Int64, String)] = []
        var acknowledged: [(Int64, String, String)] = []
        var opened: [(URL, Bool)] = []
        var sent: [URLRequest] = []
        var postedTokens: [String] = []
    }

    /// Stands in for a console with a non-console screen (offline, QR scanner) presented on top of it
    private final class PresentingConsole: ORViewcontroller {
        let presented: UIViewController

        init(presenting presented: UIViewController) {
            self.presented = presented
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override var presentedViewController: UIViewController? { presented }
    }

    // MARK: - Token

    @Test func tokenIsStoredAndPosted() throws {
        let (handler, recorder, userDefaults) = try makeHandler()

        handler.didReceiveRegistrationToken("token1")

        #expect(userDefaults.string(forKey: DefaultsKey.fcmTokenKey) == "token1")
        #expect(recorder.postedTokens == ["token1"])
    }

    // MARK: - Will present

    @Test func willPresentMarksDelivered() throws {
        let (handler, recorder, userDefaults) = try makeHandler()
        userDefaults.set("console1", forKey: GeofenceProvider.consoleIdKey)

        handler.handleWillPresent(userInfo: [ActionType.notificationId: "42"])

        #expect(recorder.delivered.count == 1)
        #expect(recorder.delivered.first?.0 == 42)
        #expect(recorder.delivered.first?.1 == "console1")
    }

    // MARK: - Responses

    @Test(arguments: [false, true])
    func defaultActionOpensURL(inBrowser: Bool) throws {
        let (handler, recorder, _) = try makeHandler()
        var userInfo: [AnyHashable: Any] = [ActionType.appUrl: "https://example.com/page"]
        if inBrowser {
            userInfo[ActionType.openInBrowser] = true
        }

        handler.handleResponse(userInfo: userInfo, actionIdentifier: UNNotificationDefaultActionIdentifier)

        #expect(recorder.opened.count == 1)
        #expect(recorder.opened.first?.0.absoluteString == "https://example.com/page")
        #expect(recorder.opened.first?.1 == inBrowser)
        #expect(recorder.acknowledged.isEmpty)
    }

    @Test func relativeURLWithoutProjectOpensNothing() throws {
        let (handler, recorder, _) = try makeHandler()

        handler.handleResponse(userInfo: [ActionType.appUrl: "page"], actionIdentifier: UNNotificationDefaultActionIdentifier)

        #expect(recorder.opened.isEmpty)
    }

    @Test(arguments: [UNNotificationDismissActionIdentifier, ORNotificationHandler.declineActionIdentifier])
    func dismissIsAcknowledged(actionIdentifier: String) throws {
        let (handler, recorder, userDefaults) = try makeHandler()
        userDefaults.set("console1", forKey: GeofenceProvider.consoleIdKey)

        handler.handleResponse(userInfo: [ActionType.notificationId: "42", ActionType.appUrl: "https://example.com/page"],
                               actionIdentifier: actionIdentifier)

        #expect(recorder.acknowledged.count == 1)
        #expect(recorder.acknowledged.first?.2 == actionIdentifier)
        #expect(recorder.opened.isEmpty)
    }

    @Test func silentButtonSendsRequest() throws {
        let (handler, recorder, userDefaults) = try makeHandler()
        userDefaults.set("console1", forKey: GeofenceProvider.consoleIdKey)
        let buttons = """
            [{"title": "Turn off", "action": {"url": "https://example.com/api", "httpMethod": "PUT", "data": "{}", \
            "silent": true, "openInBrowser": false}}]
            """

        handler.handleResponse(userInfo: [ActionType.notificationId: "42", DefaultsKey.buttonsKey: buttons],
                               actionIdentifier: "Turn off")

        #expect(recorder.acknowledged.first?.2 == "Turn off")
        #expect(recorder.sent.count == 1)
        let request = try #require(recorder.sent.first)
        #expect(request.url?.absoluteString == "https://example.com/api")
        #expect(request.httpMethod == "PUT")
        #expect(request.httpBody == Data("{}".utf8))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(recorder.opened.isEmpty)
    }

    @Test func relativeButtonOpensInBrowserOnSelectedProject() throws {
        let (handler, recorder, userDefaults) = try makeHandler()
        let projectA = ProjectConfig(domain: "https://a.example.com", app: "manager", realm: nil)
        let projectB = ProjectConfig(domain: "https://b.example.com", app: "manager", realm: nil)
        try store([projectA, projectB], selected: projectB, in: userDefaults)
        let buttons = """
            [{"title": "Other", "action": {"url": "other", "silent": false, "openInBrowser": false}}, \
            {"title": "Open", "action": {"url": "page", "silent": false, "openInBrowser": true}}]
            """

        handler.handleResponse(userInfo: [DefaultsKey.buttonsKey: buttons], actionIdentifier: "Open")

        #expect(recorder.opened.count == 1)
        #expect(recorder.opened.first?.0.absoluteString == "https://b.example.com/console/page")
        #expect(recorder.opened.first?.1 == true)
        #expect(recorder.sent.isEmpty)
    }

    // MARK: - Console lookup

    @MainActor
    @Test func consoleUnderPresentedScreenIsFound() {
        let console = PresentingConsole(presenting: UIViewController())

        #expect(ORNotificationHandler.topORViewController(in: [console]) === console)
    }

    @MainActor
    @Test func firstRootWithConsoleIsUsed() {
        let console = ORViewcontroller()

        #expect(ORNotificationHandler.topORViewController(in: [UIViewController(), console, ORViewcontroller()]) === console)
    }

    // MARK: - Setup

    private func store(_ projects: [ProjectConfig], selected: ProjectConfig, in userDefaults: UserDefaults) throws {
        userDefaults.set(try JSONEncoder().encode(projects), forKey: DefaultsKey.projectsConfigurationKey)
        userDefaults.set(selected.id, forKey: DefaultsKey.projectKey)
    }

    private func makeHandler() throws -> (ORNotificationHandler, Recorder, UserDefaults) {
        let userDefaults = try #require(TemporaryUserDefaults())
        let recorder = Recorder()
        let center = NotificationCenter()
        center.addObserver(forName: Notifications.pushTokenUpdated, object: nil, queue: nil) { notification in
            if let token = notification.userInfo?[PushNotificationProvider.tokenKey] as? String {
                recorder.postedTokens.append(token)
            }
        }

        let handler = ORNotificationHandler(
            defaults: { userDefaults },
            center: center,
            delivered: { recorder.delivered.append(($0, $1)) },
            acknowledge: { recorder.acknowledged.append(($0, $1, $2)) },
            open: { recorder.opened.append(($0, $1)) },
            send: { recorder.sent.append($0) })
        return (handler, recorder, userDefaults)
    }
}
