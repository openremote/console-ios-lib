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
import os

public enum ConfigManagerState: Equatable {
    case selectDomain
    case selectApp(String, [String]?) // baseURL, list of apps to choose from
    case selectRealm(String, String, [String]?) // baseURL, app, list of realms to choose from
    case complete(ProjectConfig)
}

public enum ConfigManagerError: Error {
    case invalidState
    case communicationError
    case couldNotLoadAppConfig
}

public typealias ApiManagerFactory = (String) throws -> ApiManager


public class ConfigManager {
    
    private var apiManagerFactory: ApiManagerFactory
    private var apiManager: ApiManager?
    
    public private(set) var globalAppInfos : [String:ORAppInfo] = [:] // app infos from the top level consoleConfig information
    public private(set) var appInfos : [String:ORAppInfo] = [:] // app infos from each specific app info.json

    public private(set) var state = ConfigManagerState.selectDomain
    
    public init(apiManagerFactory: @escaping ApiManagerFactory) {
        self.apiManagerFactory = apiManagerFactory
    }

    public func setDomain(domain: String) async throws -> ConfigManagerState  {
        switch state {
        case .selectDomain:
            let baseUrl = domain.buildBaseUrlFromDomain()
            let url = baseUrl.appending("/api/master")

            apiManager = try apiManagerFactory(url)

            guard let api = apiManager else {
                throw ConfigManagerError.communicationError
            }
            
            do {
                let cc: ORConsoleConfig
                do {
                    cc = try await api.getConsoleConfig() ?? ORConsoleConfig()
                    if let apps = cc.apps {
                        globalAppInfos = apps
                    }
                } catch ApiManagerError.notFound {
                    cc = ORConsoleConfig()
                } catch ApiManagerError.communicationError(let httpStatusCode) where httpStatusCode == 404 || httpStatusCode == 403 { // 403 is for backwards compatibility of older manager
                    cc = ORConsoleConfig()
                } catch ApiManagerError.communicationError(let httpStatusCode) {
                    throw ApiManagerError.communicationError(httpStatusCode)
                }
                
                if let selectedApp = cc.app {
                    
                    // TODO: we should potentially set the realms, either from console config or from specific app config
                    
                    
                    state = .selectRealm(baseUrl, selectedApp, nil)
                    return state
                }
                
                if cc.showAppTextInput {
                    state = .selectApp(baseUrl, nil)
                    return state
                }
                
                // allowedApps == nil -> get list of apps
                if cc.allowedApps == nil || cc.allowedApps!.isEmpty {
                    do {
                        let apps = try await api.getApps()
                        let filteredApps = await filterPotentialApps(apiManager: api, potentialApps: apps)
                        if let fa = filteredApps, fa.count == 1, let appName = fa.first {
                            state = .selectRealm(baseUrl, appName, nil)
                        } else if let fa = filteredApps, fa.count > 1 {
                            state = .selectApp(baseUrl, filteredApps)
                        } else {
                            state = .selectRealm(baseUrl, "manager", nil )
                        }
                        
                    } catch ApiManagerError.notFound {
                        if cc.showRealmTextInput {
                            state = .selectRealm(baseUrl, "manager", nil)
                        } else {
                            state = .complete(ProjectConfig(domain: baseUrl, app: "manager", realm: nil))
                        }
                    } catch ApiManagerError.communicationError(let httpStatusCode) where httpStatusCode == 404 || httpStatusCode == 403 { // 403 is for backwards compatibility of older manager
                        if cc.showRealmTextInput {
                            state = .selectRealm(baseUrl, "manager", nil)
                        } else {
                            state = .complete(ProjectConfig(domain: baseUrl, app: "manager", realm: nil))
                        }
                    }
                } else {
                    let filteredApps = await filterPotentialApps(apiManager: api, potentialApps: cc.allowedApps)
                    if let fa = filteredApps, fa.count == 1, let appName = fa.first {
                        state = .selectRealm(baseUrl, appName, nil)
                    } else {
                        state = .selectApp(baseUrl, filteredApps)
                    }
                }
                return state
            } catch {
                ORLogger.config.error("SetDomain -> error: \(error)")
                throw ConfigManagerError.couldNotLoadAppConfig
            }
        case .selectApp,
                .selectRealm,
                .complete:
            throw ConfigManagerError.invalidState
        }
        
    }

    private func filterPotentialApps(apiManager: ApiManager, potentialApps: [String]?) async -> [String]? {
        var filteredApps : [String]?
        if let appNames = potentialApps {
            filteredApps = []
            for appName in appNames {
                if let appInfo = globalAppInfos[appName] {
                    if !appInfo.consoleAppIncompatible {
                        filteredApps!.append(appName)
                    }
                } else {
                    do {
                        if let appInfo = try await apiManager.getAppInfo(appName: appName) {
                            if !appInfo.consoleAppIncompatible {
                                appInfos[appName] = appInfo
                                filteredApps!.append(appName)
                            }
                        } else {
                            filteredApps!.append(appName)
                        }
                    } catch {
                        // We couldn't fetch app info, just include app in list
                        filteredApps!.append(appName)
                    }
                }
            }
        }
        return filteredApps
    }
    
    public func setApp(app: String) throws -> ConfigManagerState {
        switch state {
        case .selectDomain,
                .selectRealm,
                .complete:
            throw ConfigManagerError.invalidState
        case .selectApp(let baseURL, _):
            if let appInfo = globalAppInfos[app] {
                self.state = .selectRealm(baseURL, app, appInfo.realms)
            } else if let appInfo = appInfos[app] {
                self.state = .selectRealm(baseURL, app, appInfo.realms)
            } else if let appInfo = globalAppInfos["default"] {
                self.state = .selectRealm(baseURL, app, appInfo.realms)
            } else {
                self.state = .selectRealm(baseURL, app, nil)
            }
            return state
        }
    }
    
    public func setRealm(realm: String?) throws -> ConfigManagerState {
        switch state {
        case .selectDomain,
                .selectApp:
            throw ConfigManagerError.invalidState
        case .complete(let project):
            
            // TODO: should set the providers on the project config
            
            self.state = .complete(ProjectConfig(domain: project.baseURL, app: project.app, realm: realm))
        case .selectRealm(let baseURL, let app, _):
            
            // TODO: should set the providers on the project config
            
            
            self.state = .complete(ProjectConfig(domain: baseURL, app: app, realm: realm))
        }
        return state
    }
    
}
