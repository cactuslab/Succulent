//
//  TraceTests.swift
//  Succulent
//
//  Created by Thomas Carey on 9/03/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

@testable import Succulent
import XCTest

class TraceTests: XCTestCase {
    
    private var suc: Succulent!
    private var session: URLSession!
    private var baseURL: URL!
    private var recordingURL: URL!
    
    override func setUp() {
        super.setUp()
        
        let testName = self.description.trimmingCharacters(in: CharacterSet(charactersIn: "-[] ")).replacingOccurrences(of: " ", with: "_")
        
        recordingURL = URL(fileURLWithPath: getDocumentsDirectory()).appendingPathComponent("\(testName).trace")
        
        suc = Succulent(recordUrl: recordingURL, passThroughBaseUrl: recordingURL)
        
        suc.start()
        
        baseURL = URL(string: "http://localhost:\(suc.actualPort)")
        
        session = URLSession(configuration: .default)
    }
    
    fileprivate func getDocumentsDirectory() -> String {
        let filePath = Bundle(for: type(of:self)).infoDictionary!["TraceOutputDirectory"] as! String
        let _ = try? FileManager.default.createDirectory(atPath: filePath, withIntermediateDirectories: true, attributes: nil)
        return filePath
    }
    
    override func tearDown() {
        suc.stop()
        
        super.tearDown()
    }
    
    func testRecordingSimple() {
        suc.passThroughBaseUrl = URL(string: "http://www.cactuslab.com/")
        
        // we've bundled in a trace file for this just to try to trip it up
        GET("index.html") { (data, response, error) in
            XCTAssertEqual(response?.statusCode, 404)
            let string = String(data: data!, encoding: .utf8)!
            XCTAssertTrue(string.endIndex > string.startIndex)
        }
        
    }
    
    func testRecordingResult() {
        suc.passThroughBaseUrl = URL(string: "http://cactuslab.com/")
        GET("/") { (data, response, error) in
            XCTAssertEqual(response?.statusCode, 200)
            
            let traceReader = TraceReader(fileURL: self.recordingURL)
            let results = traceReader.readFile()!
            
            XCTAssertEqual(results.count, 1)
            
            XCTAssert(results[0].responseBody == data)
        }
    }
    
//    func testExample() {
//        // This is an example of a functional test case.
//        // Use XCTAssert and related functions to verify your tests produce the correct results.
//        
//        let fileURL = Bundle(for: TraceTests.self).url(forResource: "trace", withExtension: "trace")!
//        
//        let traceReader = TraceReader(fileURL: fileURL)
//        if let results = traceReader.readFile() {
//            print("results")
//        }
//        
//        print("file: \(fileURL)")
//        
//    }
    
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
