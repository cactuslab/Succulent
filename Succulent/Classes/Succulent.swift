//
//  Succulent.swift
//  Succulent
//
//  Created by Karl von Randow on 15/01/17.
//  Copyright © 2017 Cactuslab. All rights reserved.
//

import Embassy
import Foundation

public class Succulent : NSObject, URLSessionTaskDelegate {
    
    public var port: Int?
    public var version = 0
    public var passThroughBaseURL: URL?
    public var recordURL: URL?
    public var ignoreParameters: Set<String>?
    
    public let router = Router()
    
    private var loop: EventLoop!
    private var server: DefaultHTTPServer!
    
    private var loopThreadCondition: NSCondition!
    private var loopThread: Thread!
    
    private var lastWasMutation = false
    
    private lazy var session : URLSession = {
        return URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()
    
    public var actualPort: Int {
        return server.listenAddress.port
    }
    
    private let queryPathSplitterRegex = try! NSRegularExpression(pattern: "^([^\\?]+)\\??(.*)?$", options: [])
    
    private var traces: [String : Trace]
    private var currentTrace = NSMutableOrderedSet()
    private var recordedKeys = Set<String>()

    public override init() {
        traces = [String : Trace]()
        
        super.init()

        router.add(".*").anyParams().block { (req, resultBlock) in
            /* Increment version when we get the first GET after a mutating http method */
            if req.method != "GET" && req.method != "HEAD" {
                self.lastWasMutation = true
            } else if self.lastWasMutation {
                self.version += 1
                self.lastWasMutation = false
            }

            if let trace = self.trace(for: req.path, queryString: req.queryString, method: req.method) {

                var status = ResponseStatus.ok
                var headers: [(String, String)]?

                if let headerData = trace.responseHeader {
                    let (aStatus, aHeaders) = self.parseHeaderData(data: headerData)
                    status = aStatus
                    headers = aHeaders
                }

                if headers == nil {
                    let contentType = self.contentType(for: req.path)
                    headers = [("Content-Type", contentType)]
                }

                var res = Response(status: status)
                res.headers = headers

                res.data = trace.responseBody
                resultBlock(.response(res))
            } else if let passThroughBaseURL = self.passThroughBaseURL {
                let url = URL(string: ".\(req.file)", relativeTo: passThroughBaseURL)!

                print("Pass-through URL: \(url.absoluteURL)")
                var urlRequest = URLRequest(url: url)
                req.headers?.forEach({ (key, value) in
                    let fixedKey = key.replacingOccurrences(of: "_", with: "-").capitalized

                    if !Succulent.dontPassThroughHeaders.contains(fixedKey.lowercased()) {
                        urlRequest.addValue(value, forHTTPHeaderField: fixedKey)
                    }
                })
                urlRequest.httpMethod = req.method
                urlRequest.httpShouldHandleCookies = false
                urlRequest.cachePolicy = .reloadIgnoringLocalCacheData

                let completionHandler = { (data: Data?, response: URLResponse?, error: Error?) in
                    // TODO handle nil response, occurs when the request fails, so we need to generate a synthetic error response
                    let response = response as! HTTPURLResponse
                    let statusCode = response.statusCode

                    var res = Response(status: .other(code: statusCode))

                    var headers = [(String, String)]()
                    for header in response.allHeaderFields {
                        let key = (header.key as! String)
                        if Succulent.dontPassBackHeaders.contains(key.lowercased()) {
                            continue
                        }
                        let value = header.value as! String

                        if key.lowercased() == "set-cookie" {
                            let values = Succulent.splitSetCookie(value: value)
                            for value in values {
                                let mungedValue = Succulent.munge(key: key, value: value)
                                headers.append((key, mungedValue))
                            }
                        } else {
                            headers.append((key, value))
                        }
                    }
                    res.headers = headers

                    try! self.recordTrace(request: req, data: data, response: response)

                    res.data = data

                    resultBlock(.response(res))
                }

                if let body = req.body {
                    let uploadTask = self.session.uploadTask(with: urlRequest, from: body, completionHandler: completionHandler)
                    uploadTask.resume()
                } else {
                    let dataTask = self.session.dataTask(with: urlRequest, completionHandler: completionHandler)
                    dataTask.resume()
                }
            } else {
                resultBlock(.response(Response(status: .notFound)))
            }
        }
    }

    public convenience init(traceURL: URL) {
        self.init()

        let traceReader = TraceReader(fileURL: traceURL)
        if let orderedTraces = traceReader.readFile() {
            var version = 0
            var lastWasMutation = false
            for trace in orderedTraces {
                if let file = trace.meta.file, let method = trace.meta.method {

                    let matches = queryPathSplitterRegex.matches(in: file, options: [], range: file.nsrange)
                    let path = file.substring(with: matches[0].rangeAt(1))!
                    let query = file.substring(with: matches[0].rangeAt(2))

                    if method != "GET" && method != "HEAD" {
                        lastWasMutation = true
                    } else if lastWasMutation {
                        version += 1
                        lastWasMutation = false
                    }

                    let key = mockPath(for: path, queryString: query, method: method, version: version)

                    traces[key] = trace
                }
            }
        }
    }

    public convenience init(recordingURL: URL) {
        self.init()

        self.recordURL = recordingURL

        //Throw away the previous trace
        try? FileManager.default.removeItem(at: recordingURL)
    }
    
    /** HttpURLRequest combines multiple set-cookies into one string separated by commas.
        We can't just split on comma as the expires also contains a comma, so we work around it.
     */
    public static func splitSetCookie(value: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "(expires\\s*=\\s*[a-z]+),", options: .caseInsensitive)
        let apologies = regex.stringByReplacingMatches(in: value, options: [], range: NSMakeRange(0, value.characters.count), withTemplate: "$1!!!OMG!!!")
        
        let split = apologies.components(separatedBy: ",")
        
        return split.map { (value) -> String in
            return value.replacingOccurrences(of: "!!!OMG!!!", with: ",").trimmingCharacters(in: .whitespaces)
        }
    }
    
    public static func munge(key: String, value: String) -> String {
        if key.lowercased() == "set-cookie" {
            let regex = try! NSRegularExpression(pattern: "(domain\\s*=\\s*)[^;]*(;?\\s*)", options: .caseInsensitive)
            return regex.stringByReplacingMatches(in: value, options: [], range: NSMakeRange(0, value.characters.count), withTemplate: "$1localhost$2")
        }
        
        return value
    }
    
    private func parseHeaderData(data: Data) -> (ResponseStatus, [(String, String)]) {
        let lines = String(data: data, encoding: .utf8)!.components(separatedBy: CharacterSet.newlines)
        
        let statusLineComponents = lines[0].components(separatedBy: CharacterSet.whitespaces)
        let statusCode = ResponseStatus.other(code: Int(statusLineComponents[1])!)
        var headers = [(String, String)]()
        
        for line in lines.dropFirst() {
            if let r = line.range(of: ": ") {
                let key = line.substring(to: r.lowerBound)
                let value = line.substring(from: r.upperBound)
                
                if Succulent.dontPassBackHeaders.contains(key.lowercased()) {
                    continue
                }
                headers.append((key, value))
            }
        }
        
        return (statusCode, headers)
    }
    
    private static let dontPassBackHeaders: Set<String> = ["content-encoding", "content-length", "connection", "keep-alive"]
    private static let dontPassThroughHeaders: Set<String> = ["accept-encoding", "content-length", "connection", "accept-language", "host"]
    
    private func createRequest(environ: [String: Any], completion: @escaping (Request)->()) {
        let method = environ["REQUEST_METHOD"] as! String
        let path = environ["PATH_INFO"] as! String
        let version = environ["SERVER_PROTOCOL"] as! String
        
        var req = Request(method: method, version: version, path: path)
        req.queryString = environ["QUERY_STRING"] as? String
        
        var headers = [(String, String)]()
        for pair in environ {
            if pair.key.hasPrefix("HTTP_"), let value = pair.value as? String {
                let key = pair.key.substring(from: pair.key.index(pair.key.startIndex, offsetBy: 5))
                headers.append((key, value))
            }
        }
        req.headers = headers
        
        var body: Data?
        
        /* We workaround what I think is a fault in Embassy. If the request has no body, then the input
           block is never called with the empty data to signify EOF. So we need to detect whether or not
           there should be a body.
         */
        if method == "GET" || method == "HEAD" {
            completion(req)
        } else {
            if let contentLengthString = req.header("Content-Length"), Int(contentLengthString) == 0 {
                completion(req)
            } else {
                let input = environ["swsgi.input"] as! SWSGIInput
                input { data in
                    if data.count > 0 {
                        if body == nil {
                            body = Data()
                        }
                        body!.append(data)
                    } else {
                        req.body = body
                        completion(req)
                    }
                }
            }
        }
    }
    
    public func start() {
        loop = try! SelectorEventLoop(selector: try! KqueueSelector())
        
        let app: SWSGI = {
            (
            environ: [String: Any],
            startResponse: @escaping ((String, [(String, String)]) -> Void),
            sendBody: @escaping ((Data) -> Void)
            ) in
            
            self.createRequest(environ: environ) { req in
                self.router.handle(request: req) { result in
                    self.loop.call {
                        switch result {
                        case .response(let res):
                            if res.containsHeader("Set-Cookie") {
                                print("Here we are with cooookies")
                            }
                            startResponse("\(res.status)", res.headers ?? [])
                            
                            if let data = res.data {
                                sendBody(data)
                            }
                            sendBody(Data())
                            
                        case .error(let error):
                            startResponse(ResponseStatus.internalServerError.description, [ ("Content-Type", "text/plain") ])
                            sendBody("An error occurred: \(error)".data(using: .utf8)!)
                            sendBody(Data())
                            
                        case .noRoute:
                            startResponse(ResponseStatus.notFound.description, [])
                            sendBody(Data())
                            
                        }
                    }
                }
            }
            
        }
        
        server = DefaultHTTPServer(eventLoop: loop, interface: "127.0.0.1", port: port ?? 0, app: app)
        
        try! server.start()
        
        loopThreadCondition = NSCondition()
        loopThread = Thread(target: self, selector: #selector(runEventLoop), object: nil)
        loopThread.start()
    }
    
    private func recordTrace(request: Request, data: Data?, response: HTTPURLResponse) throws {
        guard let recordURL = self.recordURL else {
            return
        }
        
        let traceURL = recordURL
        
        let key = mockPath(for: request.path, queryString: request.queryString, method: request.method, version: version)
        guard !recordedKeys.contains(key) else {
            return
        }
        
        //Record Metadata
        var path = request.path
        if let query = request.queryString {
            path.append("?\(sanitize(queryString: query))")
        }
        let traceMeta = TraceMeta(method: request.method, protocolScheme: self.passThroughBaseURL?.scheme, host: self.passThroughBaseURL?.host, file: path, version: "HTTP/1.1")

        let tracer = TraceWriter(fileURL: traceURL)
        let token = NSUUID().uuidString
        
        try tracer.writeComponent(component: .meta, content: traceMeta, token: token)
        
        try tracer.writeComponent(component: .responseHeader, content: response, token: token)
        if let data = data {
            try tracer.writeComponent(component: .responseBody, content: data, token: token)
        }
        
        recordedKeys.insert(key)
    }
    
    private func sanitize(pathForURL path: String) -> String {
        return path.replacingOccurrences(of: "?", with: "%3F")
//            .replacingOccurrences(of: "&", with: "%26")
    }
    
    private func headerData(response: HTTPURLResponse) -> Data? {
        var string = "\(response.statusCode)\r\n"
        
        for header in response.allHeaderFields {
            let key = header.key as! String
            
            if Succulent.dontPassBackHeaders.contains(key.lowercased()) {
                continue
            }
            
            string += "\(key): \(header.value)\r\n"
        }
        return string.data(using: .utf8)
    }
    
    private func trace(for path: String, queryString: String?, method: String, replaceExtension: String? = nil) -> Trace? {
        
        var searchVersion = version
        while searchVersion >= 0 {
            let resource = mockPath(for: path, queryString: queryString, method: method, version: searchVersion, replaceExtension: replaceExtension)
            
            if let trace = traces[resource] {
                return trace
            }
            
            searchVersion -= 1
        }
        
        return nil
        
    }
    
    
    private func mockPath(for path: String, queryString: String?, method: String, version: Int, replaceExtension: String? = nil) -> String {
        let withoutExtension = (path as NSString).deletingPathExtension
        
        let ext = replaceExtension != nil ? replaceExtension! : (path as NSString).pathExtension
        let methodSuffix = (method == "GET") ? "" : "-\(method)"
        var querySuffix: String
        if let queryString = queryString, queryString.characters.count > 0 {
            let sanitizedQueryString = sanitize(queryString: queryString)
            querySuffix = "?\(sanitizedQueryString)"
        } else {
            querySuffix = ""
        }
        
        return ("/\(withoutExtension)-\(version)\(methodSuffix)" as NSString).appendingPathExtension(ext)!.appending(querySuffix)
    }
    
    private func sanitize(queryString: String) -> String {
        guard let ignoreParameters = self.ignoreParameters else {
            return queryString
        }
        
        let params = Route.parse(queryString: queryString)
        var result = ""
        params?.forEach({ (key, value) in
            if !ignoreParameters.contains(key) {
                if result.endIndex > result.startIndex {
                    result += "&"
                }
                result += "\(key)=\(value)"
            }
        })
        return result
    }
    
    private func contentType(for path: String) -> String {
        var path = path
        if let r = path.range(of: "?", options: .backwards) {
            path = path.substring(to: r.lowerBound)
        }
        
        let ext = (path as NSString).pathExtension.lowercased()
        
        switch ext {
        case "json":
            return "text/json"
        case "txt":
            return "text/plain"
        default:
            return "application/x-octet-stream"
        }
    }
    
    public func stop() {
        server.stopAndWait()
        loopThreadCondition.lock()
        loop.stop()
        while loop.running {
            if !loopThreadCondition.wait(until: Date().addingTimeInterval(10)) {
                fatalError("Join eventLoopThread timeout")
            }
        }
    }
    
    @objc private func runEventLoop() {
        loop.runForever()
        loopThreadCondition.lock()
        loopThreadCondition.signal()
        loopThreadCondition.unlock()
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

