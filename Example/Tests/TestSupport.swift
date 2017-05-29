//
//  TestSupport.swift
//  Succulent
//
//  Created by Karl von Randow on 29/05/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import Foundation
import XCTest

protocol SucculentTest {
    var baseURL: URL! { get }
    var session: URLSession! { get }
    
    func GET(_ path: String, completion: @escaping (_ data: Data?, _ response: HTTPURLResponse?, _ error: Error?) -> ())
    func POST(_ path: String, body: Data, completion: @escaping (_ data: Data?, _ response: HTTPURLResponse?, _ error: Error?) -> ())
    
}

extension SucculentTest where Self: XCTestCase {
    
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
