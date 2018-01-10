//
//  GoogleReporter.swift
//  GoogleReporter
//
//  Created by Dung Vu on 22/05/2017.
//  Copyright © 2017 Dung Vu. All rights reserved.
//

import UIKit
import Foundation
import RxSwift
import RxCocoa

infix operator +
func +<T, V>(lhs: [T: V], rhs: [T: V]) -> [T: V] {
    var lhs = lhs
    rhs.forEach({ lhs[$0.key] = $0.value })
    return lhs
}

extension URLQueryItem {
    var query: String {
        return "\(self.name)=\(self.value ?? "")"
    }
}

extension Array {
    subscript(from maxItem: Int) -> [Element] {
        let nItems = Swift.min(self.count, maxItem)
        return Array(self[0..<nItems])
    }
}

func -=<E: Hashable>(lhs: inout [E], rhs:[E]) {
    guard lhs.count > 0, rhs.count > 0 else {
        return
    }
    var n = Set(lhs)
    defer {
        autoreleasepool { () -> () in
            n.removeAll()
        }
    }
    n.subtract(rhs)
    lhs = Array(n)
}

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


// I 'll go to upload
fileprivate class GoogleReporterUploadService {
    // Please check me
    var isUploading: Bool = false
    
    // Give me the tasks
    private func clientUpload(with request: URLRequest) -> Observable<Bool> {
        return URLSession.shared.rx.data(request: request)
            .map({ _ in return true })
            .do(onDispose: { [weak self] in
            self?.isUploading = false
        })
    }
    
    func upload(from tasks: Parameters?) -> Observable<Parameters> {
        guard let tasks = tasks, tasks.count > 0, !isUploading else {
            // No Task
            return Observable.empty()
        }
        
        let type: Send
        if (tasks.count == 1) {
            type = Send.one(tasks[0].content)
        }else {
            type = Send.multiple(tasks.map({ $0.content }))
        }
        
        self.isUploading = true
        return self.clientUpload(with: type.request).map({ _ in tasks }).catchErrorJustReturn([])
    }
}

fileprivate class ManagerGoogleReporterTasks {
    // Value tracking
    struct StaticConfig {
        // Maximum items 'll send
        static let maxItemsSend = 20
        // Buffer time send
        static let bufferSend: TimeInterval = 20
        // Max File prepare send
        static let maxItemsStorage = 40
    }
    
    // I have multiply task
    private var tasks: Variable<Parameters> = Variable(Parameters())
    private let fileURL: URL?
    private let disposeBag = DisposeBag()
    private let lock = NSLock()
    private let service = GoogleReporterUploadService()
    
    // Tracking
    init() {
        let m = FileManager.default
        fileURL = m.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("GA-Log.txt")
        LoadOldFile: if let f = fileURL {
            // Check file exist
            if !m.fileExists(atPath: f.path) {
                m.createFile(atPath: f.path, contents: nil, attributes: nil)
            }
            // Load old data
            guard let attsFile = try? m.attributesOfItem(atPath: f.path) else {
                break LoadOldFile
            }
            
            let size = attsFile[FileAttributeKey.size] as? Double ?? 0
            guard size > 0 else { break LoadOldFile }
            let decoder = JSONDecoder()
            do{
                let data = try Data(contentsOf: f)
                let values = try decoder.decode(Parameters.self, from: data)
                tasks.value = values
            } catch {
                print(error.localizedDescription)
                // try to remove file because it has old system
                try? m.removeItem(at: f)
                // Create a new
                m.createFile(atPath: f.path, contents: nil, attributes: nil)
            }
        }
        
        // Tracking maximum file
        tasks.asObservable().subscribeOn(SerialDispatchQueueScheduler(qos: .background)).filter { [weak self](_) -> Bool in
            guard let wSelf = self else {
                return false
            }
            return wSelf.tasks.value.count >= StaticConfig.maxItemsStorage && !wSelf.service.isUploading
            }.map({ $0[from: StaticConfig.maxItemsSend] })
            .bind(onNext: self.runUploadData).disposed(by: disposeBag)
        
        // Tracking at buffer time
        Observable<Int>.interval(StaticConfig.bufferSend, scheduler: SerialDispatchQueueScheduler(qos: .background)).filter { [weak self] (_) -> Bool in
            guard let wSelf = self else {
                return false
            }
            return !wSelf.service.isUploading
            }
            .map({ [unowned self] _ in self.tasks.value[from: StaticConfig.maxItemsSend]})
            .bind(onNext: self.runUploadData).disposed(by: disposeBag)
        
        // Tracking save when app prepare terminate
        let event1 = NotificationCenter.default.rx.notification(Notification.Name.UIApplicationWillTerminate, object: nil)
        let event2 = NotificationCenter.default.rx.notification(Notification.Name.UIApplicationDidEnterBackground, object: nil)
        
        Observable.merge([event1, event2]).map({ _ in }).subscribe(onNext: { [weak self](_) in
            self?.saveTasks()
        }).disposed(by: disposeBag)
    }
    
    fileprivate func runUploadData(from data: Parameters) {
        self.service.upload(from: data).filter({ $0.count > 0 })
            .bind(onNext: self.removeTasks).disposed(by: disposeBag)
    }
    
    fileprivate func saveTasks() {
        excuteInSafe {
            guard let f = self.fileURL else {
                return
            }
            let encoder = JSONEncoder()
            do{
                let data = try encoder.encode(self.tasks.value)
                try data.write(to: f)
            } catch {
                print(error.localizedDescription)
            }
        }
    }
    
    fileprivate func removeTasks(_ tasks:Parameters) {
        guard tasks.count > 0 else {
            return
        }
        self.excuteInSafe { [unowned self] in
            self.tasks.value -= tasks
        }
        self.saveTasks()
    }
    
    fileprivate func addTask(with parameter:ParameterContent) {
        let nTask = ReportTask(parameter)
        excuteInSafe {
            self.tasks.value.append(nTask)
        }
    }
    
    fileprivate func excuteInSafe(_ block: @escaping () ->()) {
        defer {
            lock.unlock()
        }
        lock.lock()
        block()
    }
}

@objcMembers
public class GoogleReporter: NSObject {
    
    public static let shared = GoogleReporter()
    public var quietMode = true
    
    private static let identifierKey = "GoogleReporter.uniqueUserIdentifier"
    private var trackerId: String?
    private lazy var manager = ManagerGoogleReporterTasks()
    private override init() {
        super.init()
    }
    
    public func configure(withTrackerId trackerId: String) {
        self.trackerId = trackerId
    }
    
    
    private lazy var uniqueUserIdentifier: String = {
        let defaults = UserDefaults.standard
        guard let identifier = defaults.string(forKey: GoogleReporter.identifierKey) else {
            let identifier = UUID().uuidString
            defaults.set(identifier, forKey: GoogleReporter.identifierKey)
            defaults.synchronize()
            
            if !self.quietMode {
                print("New GA user with identifier: ", identifier)
            }
            return identifier
        }
        return identifier
    }()
    
    private lazy var userAgent: String = {
        let currentDevice = UIDevice.current
        let osVersion = currentDevice.systemVersion.replacingOccurrences(of: ".", with: "_")
        return "Mozilla/5.0 (\(currentDevice.model); CPU iPhone OS \(osVersion) like Mac OS X) AppleWebKit/601.1.46 (KHTML, like Gecko) Mobile/13T534YI"
    }()
    
    private lazy var appName: String = {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
    }()
    
    private lazy var appIdentifier: String = {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleIdentifier") as! String
    }()
    
    private lazy var appVersion: String = {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    }()
    
    private lazy var appBuild: String = {
        return Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as! String
    }()
    
    private lazy var formattedVersion: String = {
        return "\(self.appVersion) (\(self.appBuild))"
    }()
    
    private lazy var userLanguage: String = {
        guard let locale = Locale.preferredLanguages.first, locale.count > 0 else {
            return "(not set)"
        }
        
        return locale
    }()
    
    private lazy var screenResolution: String = {
        let size = UIScreen.main.bounds.size
        return "\(size.width)x\(size.height)"
    }()
}

// MARK: Public send
extension GoogleReporter {
    enum Report {
        case screenView
        case event
        case timing
        case exception
        
        var category: String {
            switch self {
            case .screenView:
                return "screenView"
            case .event:
                return "event"
            case .timing:
                return "timing"
            case .exception:
                return "exception"
            }
        }
        
        func send(using reporter: GoogleReporter, with data: ParameterContent) {
            reporter.send(self.category, parameters: data)
        }
    }
    
    public func screenView(_ name: String, parameters: ParameterContent = [:]) {
        let data = parameters + ["cd": name]
        Report.screenView.send(using: self, with: data)
    }
    
    public func event(_ category: String, action: String, label: String = "",
                      parameters: ParameterContent = [:]) {
        let data = parameters + ["ec": category, "ea": action, "el": label]
        Report.event.send(using: self, with: data)
    }
    
    public func timing(_ category: String, action: String, label: String = "",
                       parameters: ParameterContent = [:]) {
        let data = parameters + ["utc": category, "utv": action, "utl": label]
        Report.timing.send(using: self, with: data)
    }
    
    public func exception(_ description: String, isFatal: Bool,
                          parameters: ParameterContent = [:]) {
        let data = parameters + ["exd": description, "exf": String(isFatal)]
        Report.exception.send(using: self, with: data)
    }
    
    private func send(_ type:  String, parameters: ParameterContent) {
        guard let trackerId = trackerId else {
            fatalError("You must set your tracker ID UA-XXXXX-XX with GoogleReporter.configure()")
        }
        let hasValue = parameters.keys.contains("v")
        var queryArguments: ParameterContent = [
            "tid": trackerId,
            "aid": appIdentifier,
            "cid": uniqueUserIdentifier,
            "an": appName,
            "av": formattedVersion,
            "ua": userAgent,
            "ul": userLanguage,
            "sr": screenResolution,
            "t": type
        ]
        if !hasValue {
            queryArguments["v"] = "1"
        }
        let arguments = queryArguments + parameters
        manager.addTask(with: arguments)
    }
}

// MARK: - Helper
extension URL: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        guard let url = URL(string: value) else {
            fatalError("Invalid value \(value)")
        }
        self = url
    }
}
