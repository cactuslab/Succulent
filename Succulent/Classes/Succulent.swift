import Embassy

public class Succulent {
    
    public var port: Int?
    public var version = 0
    public var passThroughBaseURL: URL?
    public var recordBaseURL: URL?
    public var ignoreParameters: Set<String>?
    
    public let router = Matching()
    
    private let bundle: Bundle
    
    private var loop: EventLoop!
    private var server: DefaultHTTPServer!
    
    private var loopThreadCondition: NSCondition!
    private var loopThread: Thread!
    
    private var lastWasMutation = false
    
    private lazy var session = URLSession(configuration: .default)
    
    public var actualPort: Int {
        return server.listenAddress.port
    }
    
    public init(bundle: Bundle) {
        self.bundle = bundle
        
        router.add(".*").anyParams().block { (req, resultBlock) in
            /* Increment version when we get the first GET after a mutating http method */
            if req.method != "GET" && req.method != "HEAD" {
                self.lastWasMutation = true
            } else if self.lastWasMutation {
                self.version += 1
                self.lastWasMutation = false
            }
            
            if let url = self.url(for: req.path, queryString: req.queryString, method: req.method) {
                let data = try! Data(contentsOf: url)
                
                var status = ResponseStatus.ok
                var headers: [(String, String)]?
                
                if let headersUrl = self.url(for: req.path, queryString: req.queryString, method: req.method, replaceExtension: "head") {
                    if let headerData = try? Data(contentsOf: headersUrl) {
                        let (aStatus, aHeaders) = self.parseHeaderData(data: headerData)
                        status = aStatus
                        headers = aHeaders
                    }
                }
                
                if headers == nil {
                    let contentType = self.contentType(for: url)
                    headers = [("Content-Type", contentType)]
                }
                
                var res = Response(status: status)
                res.headers = headers
                
                res.data = data
                resultBlock(.response(res))
            } else if let passThroughBaseURL = self.passThroughBaseURL {
                var url = URL(string: ".\(req.file)", relativeTo: passThroughBaseURL)!
                
                print("Pass-through URL: \(url.absoluteURL)")
                var urlRequest = URLRequest(url: url)
                req.headers?.forEach({ (key, value) in
                    let fixedKey = key.replacingOccurrences(of: "_", with: "-").capitalized
                    
                    if !Succulent.dontPassThroughHeaders.contains(fixedKey.lowercased()) {
                        urlRequest.addValue(value, forHTTPHeaderField: fixedKey)
                    }
                })
                urlRequest.httpMethod = req.method
                
                let completionHandler = { (data: Data?, response: URLResponse?, error: Error?) in
                    let response = response as! HTTPURLResponse
                    let statusCode = response.statusCode
                    
                    var res = Response(status: .other(code: statusCode))
                    
                    var headers = [(String, String)]()
                    for header in response.allHeaderFields {
                        let key = (header.key as! String)
                        if Succulent.dontPassBackHeaders.contains(key.lowercased()) {
                            continue
                        }
                        headers.append((key, header.value as! String))
                    }
                    res.headers = headers
                    
                    try! self.record(for: req.path, queryString: req.queryString, method: req.method, data: data, response: response)
                    
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
    
    private func parseHeaderData(data: Data) -> (ResponseStatus, [(String, String)]) {
        let lines = String(data: data, encoding: .utf8)!.components(separatedBy: "\r\n")
        let statusCode = ResponseStatus.other(code: Int(lines[0])!)
        var headers = [(String, String)]()
        
        for line in lines.dropFirst() {
            if let r = line.range(of: ": ") {
                let key = line.substring(to: r.lowerBound)
                let value = line.substring(from: r.upperBound)
                
                if Succulent.dontPassBackHeaders.contains(key.lowercased()) ?? false {
                    continue
                }
                headers.append((key, value))
            }
        }
        
        return (statusCode, headers)
    }
    
    private static let dontPassBackHeaders: Set<String> = ["content-encoding", "content-length", "connection", "keep-alive"]
    private static let dontPassThroughHeaders: Set<String> = ["accept-encoding", "content-length", "connection", "accept-language", "host"]
    
    private func createRequest(environ: [String: Any]) -> Request {
        let method = environ["REQUEST_METHOD"] as! String
        let path = environ["PATH_INFO"] as! String
        
        var req = Request(method: method, path: path)
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
        
        let input = environ["swsgi.input"] as! SWSGIInput
        input { data in
            if data.count > 0 {
                if body == nil {
                    body = Data()
                }
                body!.append(data)
            }
        }
        
        req.body = body
        
        return req
    }
    
    public func start() {
        loop = try! SelectorEventLoop(selector: try! KqueueSelector())
        
        let app: SWSGI = {
            (
            environ: [String: Any],
            startResponse: @escaping ((String, [(String, String)]) -> Void),
            sendBody: @escaping ((Data) -> Void)
            ) in
            
            let method = environ["REQUEST_METHOD"] as! String
            let path = environ["PATH_INFO"] as! String
            let queryString = environ["QUERY_STRING"] as? String
            
            let req = self.createRequest(environ: environ)
            self.router.handle(request: req) { result in
                self.loop.call {
                    switch result {
                    case .response(let res):
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
        
        server = DefaultHTTPServer(eventLoop: loop, interface: "127.0.0.1", port: port ?? 0, app: app)
        
        try! server.start()
        
        loopThreadCondition = NSCondition()
        loopThread = Thread(target: self, selector: #selector(runEventLoop), object: nil)
        loopThread.start()
    }
    
    private func record(for path: String, queryString: String?, method: String, data: Data?, response: HTTPURLResponse) throws {
        guard let recordBaseURL = self.recordBaseURL else {
            return
        }
        
        let resource = sanitize(pathForURL: mockPath(for: path, queryString: queryString, method: method, version: version))
        let recordURL = URL(string: ".\(resource)", relativeTo: recordBaseURL)!
        
        try FileManager.default.createDirectory(at: recordURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        
        if let data = data {
            try data.write(to: recordURL)
        }
        
        if let headersData = headerData(response: response) {
            let headersResource = sanitize(pathForURL: mockPath(for: path, queryString: queryString, method: method, version: version, replaceExtension: "head"))
            let headersURL = URL(string: ".\(headersResource)", relativeTo: recordBaseURL)!
            
            try headersData.write(to: headersURL)
        }
        
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
    
    private func url(for path: String, queryString: String?, method: String, replaceExtension: String? = nil) -> URL? {
        var searchVersion = version
        while searchVersion >= 0 {
            let resource = mockPath(for: path, queryString: queryString, method: method, version: searchVersion, replaceExtension: replaceExtension)
            if let url = self.bundle.url(forResource: "Mock\(resource)", withExtension: nil) {
                return url
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
        if let queryString = queryString {
            let sanitizedQueryString = sanitize(queryString: queryString)
            querySuffix = "?\(sanitizedQueryString)"
        } else {
            querySuffix = ""
        }
        
        return ("\(withoutExtension)-\(version)\(methodSuffix)" as NSString).appendingPathExtension(ext)!.appending(querySuffix)
    }
    
    private func sanitize(queryString: String) -> String {
        guard let ignoreParameters = self.ignoreParameters else {
            return queryString
        }
        
        let params = Matcher.parse(queryString: queryString)
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
    
    private func contentType(for url: URL) -> String {
        var path = url.path
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
    
}
