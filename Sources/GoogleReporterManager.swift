//
//  GoogleRepoterManager.swift
//  GoogleReporter
//
//  Created by Dung Vu on 1/10/18.
//

import Foundation
import RxSwift
import RxCocoa

final class ManagerGoogleReporterTasks {
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
    
    private func runUploadData(from data: Parameters) {
        self.service.upload(from: data).filter({ $0.count > 0 })
            .bind(onNext: self.removeTasks).disposed(by: disposeBag)
    }
    
    private func saveTasks() {
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
    
    private func removeTasks(_ tasks:Parameters) {
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
    
    private func excuteInSafe(_ block: @escaping () ->()) {
        defer {
            lock.unlock()
        }
        lock.lock()
        block()
    }
}

infix operator <-
func <-(lhs: ManagerGoogleReporterTasks, rhs:ParameterContent) {
    lhs.addTask(with: rhs)
}

