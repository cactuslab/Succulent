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
    
    func testEncoding() {
        GET("encodingTest%28%20%2742%27%20%29") { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8)!, "Hello encoding!\n")
            XCTAssertEqual(response?.allHeaderFields["Content-Type"] as! String, "application/x-octet-stream")
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
    
    func testTilde() {
        GET("~/testing.txt") { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8)!, "Tilde\n")
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
        suc.passThroughBaseURL = URL(string: "http://www.cactuslab.com/")
        
        GET("index.html") { (data, response, error) in
            let string = String(data: data!, encoding: .utf8)!
            XCTAssertTrue(string.endIndex > string.startIndex)
        }
    }
    
    func testRecord() {
        suc.passThroughBaseURL = URL(string: "http://www.cactuslab.com/")
        suc.recordBaseURL = URL(fileURLWithPath: "/Users/thomascarey/Desktop/Mock/")
        
        GET("index.html") { (data, response, error) in
            XCTAssertEqual(response?.statusCode, 404)
            let string = String(data: data!, encoding: .utf8)!
            XCTAssertTrue(string.endIndex > string.startIndex)
        }
    }
    
    func testHeaders() {
        GET("headers/index.html") { (data, response, error) in
            XCTAssertEqual(response?.statusCode, 404)
            XCTAssertEqual(response?.allHeaderFields["Content-Type"] as! String, "text/html;charset=utf-8")
        }
    }
    
    func testHeaderMunge() {
        let value = Succulent.munge(key: "Set-Cookie", value: ".ASPXAUTH=E2A2F27E643A5060E240F3CD3BBFFF3420264C34A9B441DCB0D7C2DDB8A1CD4B0552EC1C2ACCF88D0D491C05CA780E08388CF34ACF175242CC5F7BEA273644F241C780367BE9DA96E2A4A72A88245F1AB74B70A37A876AA69F727B402E81004EF23C3752BEFC5C29D2BE734F07EFECEDB689CDB4; domain=.barfoot.co.nz; expires=Wed, 25-Jan-2017 02:32:25 GMT; path=/; HttpOnly")
        XCTAssertEqual(value, ".ASPXAUTH=E2A2F27E643A5060E240F3CD3BBFFF3420264C34A9B441DCB0D7C2DDB8A1CD4B0552EC1C2ACCF88D0D491C05CA780E08388CF34ACF175242CC5F7BEA273644F241C780367BE9DA96E2A4A72A88245F1AB74B70A37A876AA69F727B402E81004EF23C3752BEFC5C29D2BE734F07EFECEDB689CDB4; domain=localhost; expires=Wed, 25-Jan-2017 02:32:25 GMT; path=/; HttpOnly")
        
        XCTAssertEqual(Succulent.munge(key: "set-COOKIE", value: "name=value"), "name=value")
    }
    
    func testSetCookieMadness() {
        let value = "SC_ANALYTICS_GLOBAL_COOKIE=73051b1ef8cb4754a229d527e05b35e6; expires=Mon, 25-Jan-2027 02:39:32 GMT; path=/; HttpOnly, SC_ANALYTICS_SESSION_COOKIE=20DEC82E7861452F884C0E562C7663A9|1|00zaww0gms2fk3gkv03cyfht; path=/; HttpOnly, .ASPXAUTH=BA9DF32B7E5964D3B99F90FFB6DC39DA4A245F5FF439964D744E4412CB07D623021192D160B3C922C256A5545B17F4D19F698561E01AA870CD01028539A8CF3ADBB56A15D80239BD66D7BC4413E4C085C5AF64B425823404BAB81DC76166CBC8216D3F437CFAFC907D96CD42D99D77E846DA9FDE; expires=Wed, 25-Jan-2017 03:09:32 GMT; path=/; HttpOnly"
        let values = Succulent.splitSetCookie(value: value)
        
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values[0], "SC_ANALYTICS_GLOBAL_COOKIE=73051b1ef8cb4754a229d527e05b35e6; expires=Mon, 25-Jan-2027 02:39:32 GMT; path=/; HttpOnly")
        XCTAssertEqual(values[1], "SC_ANALYTICS_SESSION_COOKIE=20DEC82E7861452F884C0E562C7663A9|1|00zaww0gms2fk3gkv03cyfht; path=/; HttpOnly")
        XCTAssertEqual(values[2], ".ASPXAUTH=BA9DF32B7E5964D3B99F90FFB6DC39DA4A245F5FF439964D744E4412CB07D623021192D160B3C922C256A5545B17F4D19F698561E01AA870CD01028539A8CF3ADBB56A15D80239BD66D7BC4413E4C085C5AF64B425823404BAB81DC76166CBC8216D3F437CFAFC907D96CD42D99D77E846DA9FDE; expires=Wed, 25-Jan-2017 03:09:32 GMT; path=/; HttpOnly")
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
