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

// MARK: Send
extension GoogleReporter {
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
        manager <- arguments
    }
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
}


