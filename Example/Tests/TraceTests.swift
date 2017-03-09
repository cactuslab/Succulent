//
//  TraceTests.swift
//  Succulent
//
//  Created by Thomas Carey on 9/03/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest
import Succulent

class TraceTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        
        let fileURL = Bundle(for: TraceTests.self).url(forResource: "trace", withExtension: "trace")!
        
        let traceReader = TraceReader(fileURL: fileURL)
        if let results = traceReader.readFile() {
            print("results")
        }
        
        print("file: \(fileURL)")
        
    }
    
    
}
