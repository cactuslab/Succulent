import Embassy

public class Succulent {
    
    public var port: Int?
    public var version = 0
    public var passThroughURL: URL?
    public var recordBaseURL: URL?
    
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
            
            /* Increment version when we get the first GET after a mutating http method */
            if method != "GET" && method != "HEAD" {
                self.lastWasMutation = true
            } else if self.lastWasMutation {
                self.version += 1
                self.lastWasMutation = false
            }
            
            if let url = self.url(for: path, queryString: queryString, method: method) {
                let data = try! Data(contentsOf: url)
                let contentType = self.contentType(for: url)
                startResponse("200 OK", [ ("Content-Type", contentType) ])
                
                sendBody(data)
                sendBody(Data())
            } else if let passThroughURL = self.passThroughURL {
                let data = try! Data(contentsOf: passThroughURL)
                //TODO headers like content-type
                //TODO write those to files
                //TODO non-GET requests
                
                try! self.record(for: path, queryString: queryString, method: method, data: data)
                
                
                startResponse("200 OK", [])
                sendBody(data)
                sendBody(Data())
            } else {
                startResponse("404 Not Found", [])
                sendBody(Data())
            }
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
        
        return ("\(withoutExtension)-\(version)\(methodSuffix)" as NSString).appendingPathExtension(ext)!
    }
    
    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
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
