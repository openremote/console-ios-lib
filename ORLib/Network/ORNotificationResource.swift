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

import UIKit

public class ORNotificationResource: NSObject, URLSessionDelegate {

    public static let sharedInstance = ORNotificationResource()
    
    private override init() {
        super.init()
    }

    public func notificationDelivered(notificationId : Int64, targetId : String) {
        if let userdefaults = UserDefaults(suiteName: DefaultsKey.groupEntitlement),
           let host = userdefaults.string(forKey: DefaultsKey.hostKey),
           let realm = userdefaults.string(forKey: DefaultsKey.realmKey) {
            let url = host.appending("/api/\(realm)")
            guard let urlRequest = URL(string: "\(url)/notification/\(notificationId)/delivered?targetId=\(targetId)") else { return }
            let request = NSMutableURLRequest(url: urlRequest)
            request.httpMethod = "PUT"
            let sessionConfiguration = URLSessionConfiguration.default
            let session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue : nil)
            let reqDataTask = session.dataTask(with: request as URLRequest, completionHandler: { (data, response, error) in
                DispatchQueue.main.async {
                    if (error != nil) {
                        NSLog("error %@", (error! as NSError).localizedDescription)
                        let error = NSError(domain: "", code: 0, userInfo:  [
                            NSLocalizedDescriptionKey :  NSLocalizedString("ErrorCallingAPI", value: "Could not get data", comment: "")
                        ])
                        print(error)
                    }
                }
            })
            reqDataTask.resume()
        }
    }

    public func notificationAcknowledged(notificationId : Int64, targetId : String, acknowledgement: String) {
        if let userdefaults = UserDefaults(suiteName: DefaultsKey.groupEntitlement),
           let host = userdefaults.string(forKey: DefaultsKey.hostKey),
           let realm = userdefaults.string(forKey: DefaultsKey.realmKey) {
            let url = host.appending("/api/\(realm)")
            guard let urlRequest = URL(string: "\(url)/notification/\(notificationId)/acknowledged?targetId=\(targetId)") else { return }
            let request = NSMutableURLRequest(url: urlRequest)
            request.httpMethod = "PUT"

            if let json = try? JSONSerialization.data(withJSONObject: ["acknowledgement": acknowledgement], options: []) {
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = json
            }
            let sessionConfiguration = URLSessionConfiguration.default
            let session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue : nil)
            let reqDataTask = session.dataTask(with: request as URLRequest, completionHandler: { (data, response, error) in
                DispatchQueue.main.async {
                    if (error != nil) {
                        NSLog("error %@", (error! as NSError).localizedDescription)
                        let error = NSError(domain: "", code: 0, userInfo:  [
                            NSLocalizedDescriptionKey :  NSLocalizedString("ErrorCallingAPI", value: "Could not get data", comment: "")
                        ])
                        print(error)
                    }
                }
            })
            reqDataTask.resume()
        }
    }
}
