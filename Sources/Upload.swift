//
//  Upload.swift
//  GoogleReporter
//
//  Created by Dung Vu on 1/10/18.
//

import Foundation
import RxSwift
import RxCocoa

// I 'll go to upload
class GoogleReporterUploadService {
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
