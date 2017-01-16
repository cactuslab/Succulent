import Embassy

public class Succulent {
    
    public var port: Int?
    public var version = 0
    public var passThroughURL: URL?
    public var recordBaseURL: URL?
    
    public let router = Matching()
    
    private let bundle: Bundle
    
    private var loop: EventLoop!
    private var server: DefaultHTTPServer!
    
    private var loopThreadCondition: NSCondition!
    private var loopThread: Thread!
    
    private var lastWasMutation = false
    
    public var actualPort: Int {
        return server.listenAddress.port
    }
    
    public init(bundle: Bundle) {
        self.bundle = bundle
        
        router.add(".*").block { (req) -> Response? in
            /* Increment version when we get the first GET after a mutating http method */
            if req.method != "GET" && req.method != "HEAD" {
                self.lastWasMutation = true
            } else if self.lastWasMutation {
                self.version += 1
                self.lastWasMutation = false
            }
            
            if let url = self.url(for: req.path, queryString: req.queryString, method: req.method) {
                let data = try! Data(contentsOf: url)
                let contentType = self.contentType(for: url)
                
                var res = Response(status: .ok)
                res.headers = [("Content-Type", contentType)]
                
                res.data = data
                return res
            } else if let passThroughURL = self.passThroughURL {
                let data = try! Data(contentsOf: passThroughURL)
                //TODO headers like content-type
                //TODO write those to files
                //TODO non-GET requests
                //TODO handle non-200 statuses
                
                try! self.record(for: req.path, queryString: req.queryString, method: req.method, data: data)
                
                var res = Response(status: .ok)
                res.data = data
                return res
            } else {
                return Response(status: .notFound)
            }
        }
    }
    
    private func createRequest(environ: [String: Any]) -> Request {
        let method = environ["REQUEST_METHOD"] as! String
        let path = environ["PATH_INFO"] as! String
        
        var req = Request(method: method, path: path)
        if let queryString = environ["QUERY_STRING"] as? String {
//            var params = [String: String]()
//            
//            for pair in queryString.components(separatedBy: "&") {
//                let pairTuple = pair.components(separatedBy: "=")
//                if pairTuple.count == 2 {
//                    params[pairTuple[0]] = pairTuple[1]
//                } else {
//                    params[pairTuple[0]] = ""
//                }
//            }
//            
//            req.params = params
            req.queryString = queryString
        }
        
        var headers = [(String, String)]()
        for pair in environ {
            if pair.key.hasPrefix("HTTP_"), let value = pair.value as? String {
                let key = pair.key.substring(from: pair.key.index(pair.key.startIndex, offsetBy: 5))
                headers.append((key, value))
            }
        }
        req.headers = headers
        
        return req
    }
    
    public func start() {
        loop = try! SelectorEventLoop(selector: try! KqueueSelector())
        
        let app: SWSGI = {
            (
            environ: [String: Any],
            startResponse: ((String, [(String, String)]) -> Void),
            sendBody: ((Data) -> Void)
            ) in
            
            let method = environ["REQUEST_METHOD"] as! String
            let path = environ["PATH_INFO"] as! String
            let queryString = environ["QUERY_STRING"] as? String
            
            let req = self.createRequest(environ: environ)
            let res = self.router.handle(request: req)
            
            startResponse("\(res.status)", res.headers ?? [])
            
            if let data = res.data {
                sendBody(data)
            }
            sendBody(Data())
        }
        
        server = DefaultHTTPServer(eventLoop: loop, port: port ?? 0, app: app)
        
        try! server.start()
        
        loopThreadCondition = NSCondition()
        loopThread = Thread(target: self, selector: #selector(runEventLoop), object: nil)
        loopThread.start()
    }
    
    private func record(for path: String, queryString: String?, method: String, data: Data) throws {
        guard let recordBaseURL = self.recordBaseURL else {
            return
        }
        
        let resource = mockPath(for: path, queryString: queryString, method: method, version: version)
        let recordURL = URL(string: ".\(resource)", relativeTo: recordBaseURL)!
        
        try FileManager.default.createDirectory(at: recordURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        
        try data.write(to: recordURL)
    }
    
    private func url(for path: String, queryString: String?, method: String) -> URL? {
        var searchVersion = version
        while searchVersion >= 0 {
            let resource = mockPath(for: path, queryString: queryString, method: method, version: searchVersion)
            if let url = self.bundle.url(forResource: "Mock\(resource)", withExtension: nil) {
                return url
            }
            
            searchVersion -= 1
        }
        
        return nil
    }
    
    private func mockPath(for path: String, queryString: String?, method: String, version: Int) -> String {
        //TODO queryString
        let withoutExtension = (path as NSString).deletingPathExtension
        let ext = (path as NSString).pathExtension
        let methodSuffix = (method == "GET") ? "" : "-\(method)"
        let querySuffix = (queryString == nil) ? "": "?\(queryString!)"
        
        return ("\(withoutExtension)-\(version)\(methodSuffix)" as NSString).appendingPathExtension(ext)!.appending(querySuffix)
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
