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

enum HttpMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case batch = "BATCH"
}

public class HttpApiManager: NSObject, ApiManager {

    private let baseUrl: URL;

    public init(baseUrl: String) throws {
        guard let url = URL(string: baseUrl) else {
            throw ApiManagerError.invalidUrl
        }
        self.baseUrl = url
        super.init()
    }

    public static var accessToken: String?

    let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["Content-Type": "application/json", "Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    public func getConsoleConfig(callback: ResponseBlock<ORConsoleConfig>?) {
        var urlRequest = URLRequest(url: self.baseUrl.appendingPathComponent("apps").appendingPathComponent("consoleConfig"))
        urlRequest.httpMethod = HttpMethod.get.rawValue

        session.dataTask(with: urlRequest, completionHandler: { responseData, response, error in
            let httpStatusCode = (response as? HTTPURLResponse)?.statusCode ?? 500

            if httpStatusCode == 404 {
                callback?(httpStatusCode, nil, ApiManagerError.notFound);
                return
            }
            
            if httpStatusCode != 200 {
                callback?(httpStatusCode, nil, ApiManagerError.communicationError(httpStatusCode));
                return
            }

            guard let responseData = responseData else {
                callback?(httpStatusCode, nil, error);
                return
            }

            guard let responseModel = try? self.decoder.decode(ORConsoleConfig.self, from: responseData) else {
                print("Couldn't parse response: \(String(data: responseData, encoding: .utf8)!)")
                callback?(httpStatusCode, nil,  error);
                return;
            }

            callback?(httpStatusCode, responseModel, nil)
        }).resume()
    }
    
    public func getConsoleConfig() async throws -> ORConsoleConfig? {
        var urlRequest = URLRequest(url: self.baseUrl.appendingPathComponent("apps").appendingPathComponent("consoleConfig"))
        urlRequest.httpMethod = HttpMethod.get.rawValue

        return try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: urlRequest, completionHandler: { responseData, response, error in
                let httpStatusCode = (response as? HTTPURLResponse)?.statusCode ?? 500

                if httpStatusCode == 404 {
                    continuation.resume(throwing: ApiManagerError.notFound)
                    return
                }
               
                if httpStatusCode != 200 {
                    continuation.resume(throwing: ApiManagerError.communicationError(httpStatusCode))
                    return
                }
                
                guard let responseData = responseData else {
                    continuation.resume(throwing: ApiManagerError.communicationError(httpStatusCode))
                    return
                }
                
                guard let responseModel = try? self.decoder.decode(ORConsoleConfig.self, from: responseData) else {
                    print("Couldn't parse response: \(String(data: responseData, encoding: .utf8)!)")
                    continuation.resume(throwing: ApiManagerError.parsingError(httpStatusCode))
                    return
                }

                continuation.resume(returning: responseModel)
            }).resume()
        }
    }
    
    public func getApps(callback: ResponseBlock<[String]>?) {
        var urlRequest = URLRequest(url: self.baseUrl.appendingPathComponent("apps"))
        urlRequest.httpMethod = HttpMethod.get.rawValue

        session.dataTask(with: urlRequest, completionHandler: { responseData, response, error in
            let httpStatusCode = (response as? HTTPURLResponse)?.statusCode ?? 500

            if httpStatusCode == 404 {
                callback?(httpStatusCode, nil, ApiManagerError.notFound);
                return
            }

            if httpStatusCode != 200 {
                callback?(httpStatusCode, nil, ApiManagerError.communicationError(httpStatusCode));
                return
            }

            guard let responseData = responseData else {
                callback?(httpStatusCode, nil, error);
                return
            }

            guard let responseModel = try? self.decoder.decode([String].self, from: responseData) else {
                print("Couldn't parse response: \(String(data: responseData, encoding: .utf8)!)")
                callback?(httpStatusCode, nil,  error);
                return;
            }

            callback?(httpStatusCode, responseModel, nil)
        }).resume()
    }
    
    public func getApps() async throws -> [String]? {
        var urlRequest = URLRequest(url: self.baseUrl.appendingPathComponent("apps"))
        urlRequest.httpMethod = HttpMethod.get.rawValue

        return try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: urlRequest, completionHandler: { responseData, response, error in
                let httpStatusCode = (response as? HTTPURLResponse)?.statusCode ?? 500

                if httpStatusCode == 404 {
                    continuation.resume(throwing: ApiManagerError.notFound)
                    return
                }

                if httpStatusCode != 200 {
                    continuation.resume(throwing: ApiManagerError.communicationError(httpStatusCode))
                    return
                }
                
                guard let responseData = responseData else {
                    continuation.resume(throwing: ApiManagerError.communicationError(httpStatusCode))
                    return
                }

                guard let responseModel = try? self.decoder.decode([String].self, from: responseData) else {
                    print("Couldn't parse response: \(String(data: responseData, encoding: .utf8)!)")
                    continuation.resume(throwing: ApiManagerError.parsingError(httpStatusCode))
                    return
                }

                continuation.resume(returning: responseModel)
            }).resume()
        }
    }

    
    public func getAppInfo(appName: String) async throws -> ORAppInfo? {
        var urlRequest = URLRequest(url: self.baseUrl.appendingPathComponent("apps").appendingPathComponent(appName).appendingPathComponent("info.json"))
        urlRequest.httpMethod = HttpMethod.get.rawValue

        return try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: urlRequest, completionHandler: { responseData, response, error in
                let httpStatusCode = (response as? HTTPURLResponse)?.statusCode ?? 500

                if httpStatusCode == 404 {
                    continuation.resume(throwing: ApiManagerError.notFound)
                    return
                }
                
                if httpStatusCode != 200 {
                    continuation.resume(throwing: ApiManagerError.communicationError(httpStatusCode))
                    return
                }
                
                guard let responseData = responseData else {
                    continuation.resume(throwing: ApiManagerError.communicationError(httpStatusCode))
                    return
                }

                guard let responseModel = try? self.decoder.decode(ORAppInfo.self, from: responseData) else {
                    print("Couldn't parse response: \(String(data: responseData, encoding: .utf8)!)")
                    continuation.resume(throwing: ApiManagerError.parsingError(httpStatusCode))
                    return
                }

                continuation.resume(returning: responseModel)
            }).resume()
        }
    }

    //REST METHODS
    private func createRequest(method: HttpMethod, pathComponents:[String], queryParameters: [String: Any]? = nil) -> URLRequest {
        var url: URL
        if let urlParameters = queryParameters, var components = URLComponents(url: baseUrl, resolvingAgainstBaseURL: false) {
            components.queryItems = urlParameters.map {
                URLQueryItem(name: $0, value: String(describing: $1))
            }
            url = components.url!
        } else {
            url = baseUrl
        }

        for pathComponent in pathComponents {
            url = url.appendingPathComponent(pathComponent)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue

        if let accessToken = HttpApiManager.accessToken {
            urlRequest.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        return urlRequest
    }

    private func get<T: Decodable>(pathComponents: [String], queryParameters: [String: Any]? = nil, callback: ResponseBlock<T>?) {
        let urlRequest = self.createRequest(method: .get, pathComponents: pathComponents, queryParameters: queryParameters)

        session.dataTask(with: urlRequest, completionHandler: { responseData, response, error in
            let httpStatusCode = (response as? HTTPURLResponse)?.statusCode ?? 500

            if httpStatusCode == 404 {
                callback?(httpStatusCode, nil, ApiManagerError.notFound);
                return
            }

            if httpStatusCode != 200 {
                callback?(httpStatusCode, nil, ApiManagerError.communicationError(httpStatusCode));
                return
            }

            guard let responseData = responseData else {
                callback?(httpStatusCode, nil, error);
                return
            }

            guard let responseModel = try? self.decoder.decode(T.self, from: responseData) else {
                print("Couldn't parse response: \(String(data: responseData, encoding: .utf8)!)")
                callback?(httpStatusCode, nil,  error);
                return;
            }

            callback?(httpStatusCode, responseModel, nil)
        }).resume()
    }

    private func put<T : Encodable, R : Decodable> (pathComponents:[String], item:T, callback: ResponseBlock<R>?) {
        let urlRequest = createRequest(method: .put, pathComponents: pathComponents)

        guard let data = try? encoder.encode(item) else {
            callback?(500, nil , nil)
            return
        }

        session.uploadTask(with: urlRequest, from: data, completionHandler:  { responseData, response, error in
            let httpStatusCode = (response as? HTTPURLResponse)?.statusCode ?? 500

            guard let responseData = responseData else {
                callback?(httpStatusCode, nil, error);
                return
            }

            guard let responseModel = try? self.decoder.decode(R.self, from: responseData) else {
                print("Couldn't parse response: \(String(data: responseData, encoding: .utf8)!)")
                callback?(httpStatusCode, nil, error);
                return;
            }

            callback?(httpStatusCode, responseModel, nil)
        }).resume()
    }

    private func post<T : Encodable, R : Decodable> (pathComponents:[String], item:T, callback: ResponseBlock<R>?) {
        let urlRequest = createRequest(method: .post, pathComponents: pathComponents)

        guard let data = try? encoder.encode(item) else {
            callback?(500, nil , nil)
            return
        }

        session.uploadTask(with: urlRequest, from: data, completionHandler:  { responseData, response, error in
            let httpStatusCode = (response as? HTTPURLResponse)?.statusCode ?? 500

            if httpStatusCode == 404 {
                callback?(httpStatusCode, nil, ApiManagerError.notFound);
                return
            }

            if httpStatusCode != 200 {
                callback?(httpStatusCode, nil, ApiManagerError.communicationError(httpStatusCode));
                return
            }

            guard let responseData = responseData else {
                callback?(httpStatusCode, nil, error);
                return
            }

            guard let responseModel = try? self.decoder.decode(R.self, from: responseData) else {
                print("Couldn't parse response: \(String(data: responseData, encoding: .utf8)!)")
                callback?(httpStatusCode, nil, error);
                return;
            }

            callback?(httpStatusCode, responseModel, nil)
        }).resume()
    }
}
