//
//  Task.swift
//  GoogleReporter
//
//  Created by Dung Vu on 1/10/18.
//

import Foundation

typealias Parameters = [ReportTask]
public typealias ParameterContent = [String: String]
fileprivate let baseURL: URL = "https://www.google-analytics.com/"
internal enum Send {
    case one(ParameterContent)
    case multiple([ParameterContent])
    
    var path: String {
        switch self {
        case .one:
            return "collect"
        case .multiple:
            return "batch"
        }
    }
    
    var method: String {
        return "POST"
    }
    
    var request: URLRequest {
        switch self {
        case .one(let parameters):
            // Embed url
            var componets = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
            componets?.queryItems = parameters.map({ URLQueryItem(name: $0.0, value: $0.1) })
            guard let url =  componets?.url else {
                fatalError("Error create Url post")
            }
            return URLRequest(url: url)
            
        case .multiple(let allValues):
            // Using body
            let url = baseURL.appendingPathComponent(path)
            var request = URLRequest(url: url)
            request.httpMethod = method
            
            // body
            let query = allValues.map({ $0.map({ URLQueryItem(name: $0.0, value: $0.1).query }).joined(separator: "&") }).joined(separator: "\n")
            request.httpBody = query.data(using: .utf8)
            return request
        }
    }
}

struct ReportTask: Codable, Hashable {
    var hashValue: Int {
        return self.identify
    }
    // Using for find
    let identify: Int
    // Keep save content
    let content: ParameterContent
    init(_ content: ParameterContent) {
        self.content = content
        self.identify = Int(Date().timeIntervalSince1970)
    }
}

func ==(lhs: ReportTask, rhs: ReportTask) -> Bool {
    return lhs.identify == rhs.identify
}
