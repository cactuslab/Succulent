import UIKit
import XCTest
import Succulent

class Tests: XCTestCase {
    
    private var suc: Succulent!
    private var session: URLSession!
    private var baseURL: URL!
    
    override func setUp() {
        super.setUp()
        
        let bundle = Bundle(for: type(of: self))
        suc = Succulent(bundle: bundle)
        suc.start()
        
        baseURL = URL(string: "http://localhost:\(suc.actualPort)")
        
        session = URLSession(configuration: .default)
    }
    
    override func tearDown() {
        suc.stop()
        
        super.tearDown()
    }
    
    func testSimple() {
        GET("testing") { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8)!, "Hello world")
            XCTAssertEqual(response?.allHeaderFields["Content-Type"] as! String, "application/x-octet-stream")
        }
        
        GET("testing2") { (data, response, error) in
            XCTAssert(response?.statusCode == 404)
        }
        
        GET("testing.txt") { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8)!, "Hello!\n")
            XCTAssertEqual(response?.allHeaderFields["Content-Type"] as! String, "text/plain")
        }
    }
    
    func testQuery() {
        GET("query.txt?username=test") { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8)!, "Success for query")
            XCTAssertEqual(response?.allHeaderFields["Content-Type"] as? String, "text/plain")
        }
        
        GET("query.txt?username=fail") { (data, response, error) in
            XCTAssert(response?.statusCode == 404)
        }
    }
    
    func testNested() {
        GET("folder/testing.txt") { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8)!, "Great")
        }
    }
    
    func testVersioned() {
        GET("folder/testing.txt") { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8)!, "Great")
        }
        
        suc.version += 1
        
        GET("folder/testing.txt") { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8)!, "Wrong")
        }
    }
    
    func testPOST() {
        XCTAssertEqual(0, suc.version)
        
        POST("testing.txt", body: "Body".data(using: .utf8)!) { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8), "posted")
        }
        
        XCTAssertEqual(0, suc.version)
        
        GET("testing.txt") { (data, response, error) in
            let string = String(data: data!, encoding: .utf8)!
            XCTAssert(string == "Hello!\n")
        }
        
        XCTAssertEqual(1, suc.version)
    }
    
    func testPassThrough() {
        suc.passThroughURL = URL(string: "http://www.cactuslab.com/")
        
        GET("index.html") { (data, response, error) in
            let string = String(data: data!, encoding: .utf8)!
            XCTAssertTrue(string.endIndex > string.startIndex)
        }
    }
    
    func testRecord() {
        suc.passThroughURL = URL(string: "http://www.cactuslab.com/")
        suc.recordBaseURL = URL(fileURLWithPath: "/Users/karlvr/Desktop/Mock/")
        
        GET("index.html") { (data, response, error) in
            let string = String(data: data!, encoding: .utf8)!
            XCTAssertTrue(string.endIndex > string.startIndex)
        }
    }
    
    func GET(_ path: String, completion: @escaping (_ data: Data?, _ response: HTTPURLResponse?, _ error: Error?) -> ()) {
        let url = URL(string: path, relativeTo: baseURL)!
        let expectation = self.expectation(description: "Loaded URL")
        
        let dataTask = session.dataTask(with: url) { (data, response, error) in
            completion(data, response as? HTTPURLResponse, error)
            expectation.fulfill()
        }
        dataTask.resume()
        
        self.waitForExpectations(timeout: 10) { (error) in
            if let error = error {
                completion(nil, nil, error)
            }
        }
    }
    
    func POST(_ path: String, body: Data, completion: @escaping (_ data: Data?, _ response: HTTPURLResponse?, _ error: Error?) -> ()) {
        let url = URL(string: path, relativeTo: baseURL)!
        let expectation = self.expectation(description: "Loaded URL")
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        
        let dataTask = session.uploadTask(with: req, from: body) { (data, response, error) in
            completion(data, response as? HTTPURLResponse, error)
            expectation.fulfill()
        }
        dataTask.resume()
        
        self.waitForExpectations(timeout: 10) { (error) in
            if let error = error {
                completion(nil, nil, error)
            }
        }
    }
    
}
