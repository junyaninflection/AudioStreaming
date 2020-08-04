//
//  Created by Dimitrios Chatzieleftheriou on 26/05/2020.
//  Copyright © 2020 Decimal. All rights reserved.
//

import Foundation

enum DataStreamError: Error {
    case unknown
    case sessionDeinit
}

protocol StreamTaskProvider: class {
    func dataStream(for request: URLSessionTask) -> NetworkDataStream?
}

extension URLSessionConfiguration {
    static var networkingConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.networkServiceType = .avStreaming
        configuration.urlCache = nil
        return configuration
    }
}

internal final class NetworkingClient {
    
    let session: URLSession
    let delegate: NetworkSessionDelegate
    let networkQueue: DispatchQueue
    
    var tasks = NetworkTasksMap()
    var activeTasks = Set<NetworkDataStream>()
    
    internal init(configuration: URLSessionConfiguration = .networkingConfiguration,
         delegate: NetworkSessionDelegate = NetworkSessionDelegate(),
         networkQueue: DispatchQueue = DispatchQueue(label: "com.decimal.session.network.queue")) {
        
        let delegateQueue = operationQueue(underlyingQueue: networkQueue)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: delegateQueue)
        self.session = session
        self.delegate = delegate
        self.networkQueue = networkQueue
        delegate.taskProvider = self
    }
    
    deinit {
        session.finishTasksAndInvalidate()
    }
    
    /// Creates a data stream for the given `URLRequest`
    /// - parameter request: A `URLRequest` to be used for the data stream
    internal func stream(request: URLRequest) -> NetworkDataStream {
        let stream = NetworkDataStream(id: UUID(), underlyingQueue: networkQueue)
        setupRequest(stream, request: request)
        return stream
    }
    
    /// Cancels on active requests
    internal func cancelAllRequest() {
        networkQueue.async { [weak self] in
            self?.activeTasks.forEach { $0.cancel() }
        }
        self.activeTasks.removeAll()
        self.tasks = NetworkTasksMap()
    }
    
    internal func remove(task: NetworkDataStream) {
        self.activeTasks.remove(task)
        self.tasks[task] = nil
    }
    
    // MARK: Private
    
    /// Schedules the given `NetworkDataStream` to be performed immediatelly
    /// - parameter stream: The `NetworkDataStream` object to be performed
    /// - parameter request: The `URLRequest` for the `stream`
    private func setupRequest(_ stream: NetworkDataStream, request: URLRequest) {
        networkQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.activeTasks.insert(stream)
            let task = stream.task(for: request, using: self.session)
            self.tasks[stream] = task
            
        }
    }

}

// MARK: StreamTaskProvider conformance
extension NetworkingClient: StreamTaskProvider {
    internal func dataStream(for request: URLSessionTask) -> NetworkDataStream? {
        tasks[request] ?? nil
    }
    
    internal func sessionTask(for stream: NetworkDataStream) -> URLSessionTask? {
        tasks[stream] ?? nil
    }
}

// MARK: Helper

private func operationQueue(underlyingQueue: DispatchQueue) -> OperationQueue {
    let delegateQueue = OperationQueue()
    delegateQueue.qualityOfService = .default
    delegateQueue.maxConcurrentOperationCount = 1
    delegateQueue.underlyingQueue = underlyingQueue
    delegateQueue.name = "com.decimal.session.delegate.queue"
    return delegateQueue
}
