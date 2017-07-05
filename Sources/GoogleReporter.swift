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
func +<T:Hashable,V>(lhs: [T: V], rhs: [T: V]) -> [T: V] {
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
    func subArray(with maxItem: Int) -> [Element] {
        let nItems = Swift.min(self.count, maxItem)
        return Array(self[0..<nItems])
    }
}

func -=<E: Equatable>(lhs: inout [E], rhs:[E]) {
    guard lhs.count > 0, rhs.count > 0 else {
        return
    }
    
    rhs.forEach({
        guard let idx = lhs.index(of: $0) else {
            return
        }
        lhs.remove(at: idx)
    })
}

enum Send {
    case one([String: String])
    case multiple([[String: String]])
    
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
        let baseURL = URL(string: "https://www.google-analytics.com/")!
        let characterSet = CharacterSet.urlPathAllowed
        switch self {
        case .one(let parameters):
            // Embed url
            var componets = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
            componets?.queryItems = parameters.map({ URLQueryItem(name: $0.0, value: $0.1.addingPercentEncoding(withAllowedCharacters: characterSet)) })
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
            let query = allValues.map({ $0.map({ URLQueryItem(name: $0.0, value: $0.1.addingPercentEncoding(withAllowedCharacters: characterSet)).query }).joined(separator: "&") }).joined(separator: "\n")
            request.httpBody = query.data(using: .utf8)
            return request
        }
    }
}

fileprivate class ReportTask: NSObject, NSCoding {
    // Using for find
    let identify: Int
    
    // Keep save content
    let content: [String: String]
    
    init(_ content: [String: String]) {
        self.content = content
        self.identify = Int(Date().timeIntervalSince1970)
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        guard let c = aDecoder.decodeObject(forKey: "content") as? [String: String] else {
            return nil
        }
        let i = aDecoder.decodeInteger(forKey: "identify")
        self.content = c
        self.identify = i
        super.init()
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(self.content, forKey: "content")
        aCoder.encode(self.identify, forKey: "identify")
    }
    
    override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? ReportTask else {
            return false
        }
        return self.identify == o.identify
    }
}

// I 'll go to upload
fileprivate class GoogleReporterUploadService {
     // Please check me
     var isUploading: Bool = false
    
    // Give me the tasks
    func upload(from tasks: [ReportTask]?) -> Observable<[ReportTask]> {
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
        return Observable.create({ (s) -> Disposable in
            let session = URLSession.shared
            let t = session.dataTask(with: type.request, completionHandler: { (_, _, e) in
                guard let e = e else {
                    s.onNext(tasks)
                    s.onCompleted()
                    return
                }
                s.onError(e)
            })
            t.resume()
            return Disposables.create {
                t.cancel()
            }
        }).do(onNext: { [weak self](_) in
            // Free me to prepare other task
            self?.isUploading = false
        }, onError: { [weak self](_) in
            // Free me to prepare other task
            self?.isUploading = false
        }).catchError({ (e) -> Observable<[ReportTask]> in
            // Using Catch avoid error terminate signal
            print("GA error: \(e.localizedDescription)")
            return Observable.just([])
        })
    }
    
}

// Maximum items 'll send
fileprivate let maxItemsSend = 20

// Buffer time send
fileprivate let bufferSend: TimeInterval = 20

// Max File prepare send
fileprivate let maxItemsStorage = 40


fileprivate class ManagerGoogleReporterTasks {
    // I have multiply task
    var tasks: Variable<[ReportTask]> = Variable([])
    
    let fileURL: URL?
    
    let disposeBag = DisposeBag()
    let lock = NSLock()
    let service = GoogleReporterUploadService()
    
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
            if size > 0 {
                tasks.value = NSKeyedUnarchiver.unarchiveObject(withFile: f.path) as? [ReportTask] ?? []
            }
        }
        
        // Tracking maximum file
        tasks.asObservable().subscribeOn(SerialDispatchQueueScheduler(qos: .background)).filter { [weak self](_) -> Bool in
            guard let wSelf = self else {
                return false
            }
            return wSelf.tasks.value.count >= maxItemsStorage && !wSelf.service.isUploading
            }.flatMap({ [unowned self] in
                self.service.upload(from: $0.subArray(with: maxItemsSend))
            }).subscribe(onNext: { [weak self] in
                guard $0.count > 0 else { return }
                self?.removeTasks($0)
                self?.saveTasks()
            }).addDisposableTo(disposeBag)
        
        // Tracking at buffer time
        Observable<Int>.interval(bufferSend, scheduler: SerialDispatchQueueScheduler(qos: .background)).filter { [weak self] (_) -> Bool in
            guard let wSelf = self else {
                return false
            }
            return !wSelf.service.isUploading
            }.flatMap({ [unowned self] _ in
                self.service.upload(from: self.tasks.value.subArray(with: maxItemsSend))
            }).subscribe(onNext: { [weak self] in
                guard $0.count > 0 else { return }
                self?.removeTasks($0)
                self?.saveTasks()
            }).addDisposableTo(disposeBag)
        
        // Tracking save when app prepare terminate
        let event1 = NotificationCenter.default.rx.notification(Notification.Name.UIApplicationWillTerminate, object: nil)
        let event2 = NotificationCenter.default.rx.notification(Notification.Name.UIApplicationWillEnterForeground, object: nil)
        
        Observable.merge([event1, event2]).subscribe(onNext: { [weak self](_) in
           self?.saveTasks()
        }).addDisposableTo(disposeBag)
    }
    
    func saveTasks() {
        excuteInSafe {
            guard let f = self.fileURL else {
                return
            }
            let r = NSKeyedArchiver.archiveRootObject(self.tasks.value, toFile: f.path)
            if !r {
                print("Can't save!!!!")
            }
        }
    }
    
    
    func removeTasks(_ tasks:[ReportTask]) {
        guard tasks.count > 0 else {
            return
        }
        self.excuteInSafe { [unowned self] in
            self.tasks.value -= tasks
        }
    }
    
    func addTask(with parameter:[String: String]) {
        let nTask = ReportTask(parameter)
        excuteInSafe {
            self.tasks.value.append(nTask)
        }
    }
    
    func excuteInSafe(_ block: @escaping () ->()) {
        defer {
            lock.unlock()
        }
        lock.lock()
        block()
    }
}



public class GoogleReporter: NSObject {
    public static let shared = GoogleReporter()
    
    public var quietMode = true
    
    private static let identifierKey = "GoogleReporter.uniqueUserIdentifier"
    
    private var trackerId: String?
    private lazy var manager = ManagerGoogleReporterTasks()
    
    
    public func configure(withTrackerId trackerId: String) {
        self.trackerId = trackerId
    }
   
    private override init() {
        super.init()
    }
    
    public func screenView(_ name: String, parameters: [String: String] = [:]) {
        let data = parameters + ["cd": name]
        send("screenView", parameters: data)
    }
    
    public func event(_ category: String, action: String, label: String = "",
                      parameters: [String: String] = [:]) {
        let data = parameters + ["ec": category, "ea": action, "el": label]
        
        send("event", parameters: data)
    }
    
    public func exception(_ description: String, isFatal: Bool,
                          parameters: [String: String] = [:]) {
        let data = parameters + ["exd": description, "exf": String(isFatal)]
        send("exception", parameters: data)
    }
    
    private func send(_ type:  String, parameters: [String: String]) {
        guard let trackerId = trackerId else {
            fatalError("You must set your tracker ID UA-XXXXX-XX with GoogleReporter.configure()")
        }
        let hasValue = parameters.keys.contains("v")
        var queryArguments: [String: String] = [
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
        guard let locale = Locale.preferredLanguages.first, locale.characters.count > 0 else {
            return "(not set)"
        }
        
        return locale
    }()
    
    private lazy var screenResolution: String = {
        let size = UIScreen.main.bounds.size
        return "\(size.width)x\(size.height)"
    }()
}
