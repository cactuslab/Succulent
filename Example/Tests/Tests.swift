import UIKit
import XCTest
import Succulent

class Tests: XCTestCase, SucculentTest {
    
    private var suc: Succulent!
    var session: URLSession!
    var baseURL: URL!
    
    override func setUp() {
        super.setUp()
        
        if let traceURL = self.traceUrl {
            suc = Succulent(traceUrl: traceURL, baseUrl: nil, ignoreVersioningRequests: ["^/ignore_post.txt"])
        } else {
            suc = Succulent()
        }
        
        suc.start()
        
        baseURL = URL(string: "http://localhost:\(suc.actualPort)")
        
        session = URLSession(configuration: .default)
    }
    
    /// The name of the trace file for the current test
    private var traceName: String {
        return self.description.trimmingCharacters(in: CharacterSet(charactersIn: "-[] ")).replacingOccurrences(of: " ", with: "_")
    }
    
    /// The URL to the trace file for the current test when running tests
    private var traceUrl: URL? {
        let bundle = Bundle(for: type(of: self))
        return bundle.url(forResource: self.traceName, withExtension: "trace", subdirectory: "Succulent")
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
        
        GET("testing.txt?") { (data, response, error) in
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
    
    func testIgnoredParameters() {
        suc.ignoreParameters = ["ignoreMe"]
        
        GET("query.txt?username=test&ignoreMe=1209") { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8)!, "Success for query")
            XCTAssertEqual(response?.allHeaderFields["Content-Type"] as? String, "text/plain")
        }
        
        GET("query.txt?username=test&dontIgnoreMe=1209") { (data, response, error) in
            XCTAssert(response?.statusCode == 404)
        }
    }
    
    func testIgnoreAllParameters() {
        suc.ignoreParameters = ["ignore_me"]
        
        GET("query.txt?ignore_me=12345") { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8)!, "Success for query")
            XCTAssertEqual(response?.allHeaderFields["Content-Type"] as? String, "text/plain")
        }
        
        GET("query2.txt?ignore_me=12345") { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8)!, "Success for query")
            XCTAssertEqual(response?.allHeaderFields["Content-Type"] as? String, "text/plain")
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
        
        GET("query.txt") { (data, response, error) in
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
            XCTAssertEqual(String(data: data!, encoding: .utf8)!, "Tilde")
        }
    }
    
    func testVersioned() {
        GET("folder/testing.txt") { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8)!, "Great")
        }
        
        POST("testing.txt", body: Data()) { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8), "Random post to up the version number")
        }
        
        GET("folder/testing.txt") { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8)!, "Wrong")
        }
    }
    
    func testPOSTVersions() {
        
        POST("ignore_post.txt", body: Data()) { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8), "Post1")
        }
        
        GET("folder/testing.txt") { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8)!, "Great")
        }
        
        POST("testing.txt", body: Data()) { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8), "Post2")
        }
        
        GET("folder/testing.txt") { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8)!, "Wrong")
        }
    }
    
    func testPOSTEmptyBody() {
        XCTAssertEqual(0, suc.version)
        
        POST("testing.txt", body: Data()) { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8), "posted")
        }
        
        XCTAssertEqual(0, suc.version)
        
        GET("testing.txt") { (data, response, error) in
            let string = String(data: data!, encoding: .utf8)!
            XCTAssert(string == "Hello!")
        }
        
        XCTAssertEqual(1, suc.version)
    }
    
    func testPOST() {
        XCTAssertEqual(0, suc.version)
        
        POST("testing.txt", body: "Body".data(using: .utf8)!) { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8), "posted")
        }
        
        XCTAssertEqual(0, suc.version)
        
        GET("testing.txt") { (data, response, error) in
            let string = String(data: data!, encoding: .utf8)!
            XCTAssert(string == "Hello!")
        }
        
        XCTAssertEqual(1, suc.version)
    }
    
    func testPassThrough() {
        suc.baseUrl = URL(string: "http://www.cactuslab.com/")
        
        GET("index.html") { (data, response, error) in
            let string = String(data: data!, encoding: .utf8)!
            XCTAssertTrue(string.endIndex > string.startIndex)
        }
    }
    
    func testPassThroughURLPreservation() {
        suc.baseUrl = URL(string: "http://www.cactuslab.com/api/")
        
        GET("index.html") { (data, response, error) in
            XCTAssertTrue(response?.url?.absoluteString == "http://cactuslab.com/api/index.html", "The responseURL was \(response?.url?.absoluteString ?? "nil")")
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
    
    func testIgnorePostVersioning() {
        XCTAssertEqual(0, suc.version)
        
        GET("get2.txt") { (data, response, error) in
            let string = String(data: data!, encoding: .utf8)!
            XCTAssert(string == "get2")
        }
        
        POST("ignore_post.txt", body: "Body".data(using: .utf8)!) { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8), "posted1")
        }
        
        GET("get1.txt") { (data, response, error) in
            let string = String(data: data!, encoding: .utf8)!
            XCTAssert(string == "get1")
        }
        
        XCTAssertEqual(0, suc.version)
        
        POST("post2.txt", body: "Body".data(using: .utf8)!) { (data, response, error) in
            XCTAssertEqual(String(data: data!, encoding: .utf8), "posted2")
        }
        
        GET("get1.txt") { (data, response, error) in
            let string = String(data: data!, encoding: .utf8)!
            XCTAssert(string == "get1+1")
        }
        
        XCTAssertEqual(1, suc.version)
    }
    
}
