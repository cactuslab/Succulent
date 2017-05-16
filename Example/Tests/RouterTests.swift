//
//  UITestMockingTests.swift
//  UITestMockingTests
//
//  Created by Karl von Randow on 15/01/17.
//  Copyright © 2017 XK72. All rights reserved.
//

import XCTest
import Succulent

class RouterTests: XCTestCase {
    
    var mock: Router!
    
    override func setUp() {
        super.setUp()
    
        mock = Router()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    private func handle(request: Request) -> Response {
        let result = mock.handleSync(request: request)
        switch result {
        case .response(let res):
            return res
        case .error:
            return Response(status: .internalServerError)
        case .noRoute:
            return Response(status: .notFound)
        }
    }
    
    func testAnchoredMatching() {
        mock.add("/login").status(.ok)
        
        XCTAssert(handle(request: Request(path: "/login")).status == .ok)
        XCTAssert(handle(request: Request(path: "x/login")).status == .notFound)
        XCTAssert(handle(request: Request(path: "/loginx")).status == .notFound)
    }

    func testParamMatching() {
        mock.add("/login").status(.ok)
        mock.add("/login").param("username", "karl").status(.ok)

        XCTAssert(handle(request: Request(path: "/login", queryString: "username=karl")).status == .ok)
        XCTAssert(handle(request: Request(path: "/login", queryString: "username=karlx")).status == .notFound)
        XCTAssert(handle(request: Request(path: "/login", queryString: "username=karl&another=other")).status == .notFound)
    }

    func testParamMatchingWithAny() {
        mock.add("/login").status(.ok)
        mock.add("/login").param("username", "karl").anyParams().status(.ok)

        XCTAssert(handle(request: Request(path: "/login", queryString: "username=karl")).status == .ok)
        XCTAssert(handle(request: Request(path: "/login", queryString: "username=karl&another=other")).status == .ok)
    }

    func testMultiParamMatching() {
        mock.add("/login").status(.ok)
        mock.add("/login").param("username", "karl").param("password", "toast").status(.ok)

        XCTAssert(handle(request: Request(path: "/login", queryString: "username=karl")).status == .notFound)
        XCTAssert(handle(request: Request(path: "/login", queryString: "username=karl&password=toast")).status == .ok)
        XCTAssert(handle(request: Request(path: "/login", queryString: "username=karl&password=toastx")).status == .notFound)
        XCTAssert(handle(request: Request(path: "/login", queryString: "username=karl&password=toast&another=other")).status == .notFound)
    }

    func testMultiParamMatchingWithAny() {
        mock.add("/login").status(.ok)
        mock.add("/login").param("username", "karl").param("password", "toast").anyParams().status(.ok)

        XCTAssert(handle(request: Request(path: "/login", queryString: "username=karl")).status == .notFound)
        XCTAssert(handle(request: Request(path: "/login", queryString: "username=karl&password=toast")).status == .ok)
        XCTAssert(handle(request: Request(path: "/login", queryString: "username=karl&password=toastx")).status == .notFound)
        XCTAssert(handle(request: Request(path: "/login", queryString: "username=karl&password=toast&another=other")).status == .ok)
    }
    
    func testBlock() {
        mock.add("/echo").anyParams().block { (req, resultBlock) in
            resultBlock(.response(Response(status: .ok, data: req.body, contentType: req.contentType)))
        }

        let res = handle(request: Request(path: "/echo", queryString: "username=karl"))
        XCTAssertEqual(res.status, .ok)
        XCTAssertEqual(res.data, nil)
        
        var req = Request(path: "/echo")
        req.body = "Success".data(using: .utf8)
        
        let res2 = handle(request: req)
        XCTAssertEqual(res2.status, .ok)
        XCTAssertEqual(res2.data, req.body)
    }

    func testExample() {
        mock.add("/login").status(.ok)
        mock.add("/login").param("username", "karl").status(.ok)
        mock.add("/login").param("username", "donald").content("OK", .TextPlain).then {
            print("Did then")
        }
        mock.add("/register.*").status(.ok)
        mock.add("/invalid)").status(.ok)

        mock.add("/echo").anyParams().block { (req, resultBlock) in
            resultBlock(.response(Response(status: .ok, data: req.body, contentType: req.contentType)))
        }

        XCTAssert(handle(request: Request(path: "/login")).status == .ok)
        XCTAssert(handle(request: Request(path: "x/login")).status == .notFound)
        XCTAssert(handle(request: Request(path: "/loginx")).status == .notFound)

        XCTAssert(handle(request: Request(path: "/login", queryString: "username=karl")).status == .ok)
        XCTAssert(handle(request: Request(path: "/login", queryString: "username=karlx")).status == .notFound)
        XCTAssert(handle(request: Request(path: "/login", queryString: "username=karl&another=other")).status == .notFound)

        XCTAssert(handle(request: Request(path: "/register")).status == .ok)
        XCTAssert(handle(request: Request(path: "/register123")).status == .ok)

        XCTAssert(handle(request: Request(path: "/invalid)")).status == .notFound)
    }
    
}
