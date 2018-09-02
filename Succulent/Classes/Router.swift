//
//  Router.swift
//  Succulent
//
//  Created by Karl von Randow on 15/01/17.
//  Copyright © 2017 Cactuslab. All rights reserved.
//

import Foundation

public typealias RoutingResultBLock = (RoutingResult) -> ()

/// The result of routing
public enum RoutingResult {
    
    case response(_: Response)
    case error(_: Error)
    case noRoute
    
}

public class Router {

    private var routes = [Route]()

    public init() {

    }
    
    public func add(_ path: String) -> Route {
        let route = Route(path)
        routes.append(route)
        return route
    }

    public func handle(request: Request, resultBlock: @escaping RoutingResultBLock) {
        var bestScore = -1
        var bestRoute: Route?

        for route in routes {
            if let score = route.match(request: request) {
                if score >= bestScore {
                    bestScore = score
                    bestRoute = route
                }
            }
        }

        if let route = bestRoute {
            route.handle(request: request, resultBlock: resultBlock)
        } else {
            resultBlock(.noRoute)
        }
    }
    
    public func handleSync(request: Request) -> RoutingResult {
        var result: RoutingResult?
        let semaphore = DispatchSemaphore(value: 0)
        
        handle(request: request) { theResult in
            result = theResult
            semaphore.signal()
        }
        
        semaphore.wait()
        return result!
    }

}

/// The status code of a response
public enum ResponseStatus: Equatable, CustomStringConvertible {
    
    public static func ==(lhs: ResponseStatus, rhs: ResponseStatus) -> Bool {
        return lhs.code == rhs.code
    }

    case notFound
    case ok
    case notModified
    case internalServerError
    case other(code: Int)
    
    public var code: Int {
        switch self {
        case .notFound: return 404
        case .ok: return 200
        case .notModified: return 304
        case .internalServerError: return 500
        case .other(let code): return code
        }
    }
    
    public var message: String {
        return HTTPURLResponse.localizedString(forStatusCode: code)
    }
    
    public var description: String {
        return "\(self.code) \(self.message)"
    }
    
}

/// The mime-type part of a content type
public enum ContentType {
    case TextJSON
    case TextPlain
    case TextHTML
    case Other(type: String)

    func type() -> String {
        switch self {
        case .TextJSON:
            return "text/json"
        case .TextPlain:
            return "text/plain"
        case .TextHTML:
            return "text/html"
        case .Other(let aType):
            return aType
        }
    }

    static func forExtension(ext: String) -> ContentType? {
        switch ext.lowercased() {
        case "json":
            return .TextJSON
        case "txt":
            return .TextPlain
        case "html", "htm":
            return .TextHTML
        default:
            return nil
        }
    }

    static func forContentType(contentType: String) -> ContentType? {
        let components = contentType.components(separatedBy: ";")
        guard components.count > 0 else {
            return nil
        }

        let mimeType = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
        switch mimeType.lowercased() {
        case "text/json":
            return .TextJSON
        case "text/plain":
            return .TextPlain
        case "text/html":
            return .TextHTML
        default:
            return .Other(type: mimeType)
        }
    }

}

public class Route {
    
    public typealias ThenBlock = () -> ()

    private let path: String
    private var params = [String: String]()
    private var allowOtherParams = false
    private var headers = [String: String]()
    private var responder: Responder?
    private var thenBlock: ThenBlock?

    public init(_ path: String) {
        self.path = path
    }

    @discardableResult public func param(_ name: String, _ value: String) -> Route {
        params[name] = value
        return self
    }

    @discardableResult public func anyParams() -> Route {
        allowOtherParams = true
        return self
    }

    @discardableResult public func header(_ name: String, _ value: String) -> Route {
        headers[name] = value
        return self
    }

    @discardableResult public func respond(_ responder: Responder) -> Route {
        return self
    }

    @discardableResult public func status(_ status: ResponseStatus) -> Route {
        responder = StatusResponder(status: status)
        return self
    }

    @discardableResult public func resource(_ url: URL) -> Route {
        return self
    }

    @discardableResult public func resource(_ resource: String) throws -> Route {
        return self
    }

    @discardableResult public func resource(bundle: Bundle, resource: String) throws -> Route {
        return self
    }

    @discardableResult public func content(_ string: String, _ type: ContentType) -> Route {
        responder = ContentResponder(string: string, contentType: type, encoding: .utf8)
        return self
    }
    
    @discardableResult public func content(_ data: Data, _ type: ContentType) -> Route {
        responder = ContentResponder(data: data, contentType: type)
        return self
    }

    @discardableResult public func block(_ block: @escaping BlockResponder.BlockResponderBlock) -> Route {
        responder = BlockResponder(block: block)
        return self
    }

    @discardableResult public func json(_ value: Any) throws -> Route {
        let data = try JSONSerialization.data(withJSONObject: value)
        return content(data, .TextJSON)
    }

    @discardableResult public func then(_ block: @escaping ThenBlock) -> Route {
        self.thenBlock = block
        return self
    }

    fileprivate func match(request: Request) -> Int? {
        guard match(path: request.path) else {
            return nil
        }

        guard let paramsScore = match(queryString: request.queryString) else {
            return nil
        }

        return paramsScore
    }

    private func match(path: String) -> Bool {
        guard let r = path.range(of: self.path, options: [.regularExpression, .anchored]) else {
            return false
        }

        /* Check anchoring at the end of the string, so our regex is a full match */
        if r.upperBound != path.endIndex {
            return false
        }

        return true
    }

    private func match(queryString: String?) -> Int? {
        var score = 0

        if let params = Route.parse(queryString: queryString) {
            var remainingToMatch = self.params

            for (key, value) in params {
                if let requiredMatch = self.params[key] {
                    if let r = value.range(of: requiredMatch, options: [.regularExpression, .anchored]) {
                        /* Check anchoring at the end of the string, so our regex is a full match */
                        if r.upperBound != value.endIndex {
                            return nil
                        }

                        score += 1
                        remainingToMatch.removeValue(forKey: key)
                    } else {
                        return nil
                    }
                } else if !allowOtherParams {
                    return nil
                }
            }

            guard remainingToMatch.count == 0 else {
                return nil
            }
        } else if self.params.count != 0 {
            return nil
        }

        return score
    }
    
    public static func parse(queryString: String?) -> [(String, String)]? {
        guard let queryString = queryString else {
            return nil
        }
        
        var result = [(String, String)]()

        for pair in queryString.components(separatedBy: "&") {
            let pairTuple = pair.components(separatedBy: "=")
            if pairTuple.count == 2 {
                result.append((pairTuple[0], pairTuple[1]))
            } else {
                result.append((pairTuple[0], ""))
            }
        }
        
        return result
    }

    fileprivate func handle(request: Request, resultBlock: @escaping RoutingResultBLock) {
        if let responder = responder {
            responder.respond(request: request) { (result) in
                resultBlock(result)
                
                if let thenBlock = self.thenBlock {
                    thenBlock()
                }
            }
        } else {
            resultBlock(.response(Response(status: .notFound)))
            
            if let thenBlock = thenBlock {
                thenBlock()
            }
        }
    }

}

/// Request methods
public enum RequestMethod: String {
    case GET
    case HEAD
    case POST
    case PUT
    case DELETE
}

public let DefaultHTTPVersion = "HTTP/1.1"

/// Model for an HTTP request
public struct Request {

    public var version: String
    public var method: String
    public var path: String
    public var queryString: String?
    public var headers: [(String, String)]?
    public var body: Data?
    public var contentType: ContentType? {
        if let contentType = header("Content-Type") {
            return ContentType.forContentType(contentType: contentType)
        } else {
            return nil
        }
    }
    public var file: String {
        if let queryString = queryString {
            return "\(path)?\(queryString)"
        } else {
            return path
        }
    }

    public init(method: String = RequestMethod.GET.rawValue, version: String = DefaultHTTPVersion, path: String) {
        self.method = method
        self.path = path
        self.version = version
    }

    public init(method: String = RequestMethod.GET.rawValue, version: String = DefaultHTTPVersion, path: String, queryString: String?) {
        self.method = method
        self.path = path
        self.version = version
        self.queryString = queryString
    }
    
    public init(method: String = RequestMethod.GET.rawValue, version: String = DefaultHTTPVersion, path: String, queryString: String?, headers: [(String, String)]?) {
        self.method = method
        self.path = path
        self.version = version
        self.queryString = queryString
        self.headers = headers
    }
    
    public func header(_ needle: String) -> String? {
        guard let headers = headers else {
            return nil
        }
        
        for (key, value) in headers {
            if key.lowercased().replacingOccurrences(of: "-", with: "_") == needle.lowercased().replacingOccurrences(of: "-", with: "_") {
                return value
            }
        }
        
        return nil
    }

}

/// Model for an HTTP response
public struct Response {

    public var status: ResponseStatus
    public var headers: [(String, String)]?
    public var data: Data?
    public var contentType: ContentType?
    
    public init(status: ResponseStatus) {
        self.status = status
    }
    
    public init(status: ResponseStatus, data: Data?, contentType: ContentType?) {
        self.status = status
        self.data = data
        self.contentType = contentType
    }
    
    public func containsHeader(_ needle: String) -> Bool {
        guard let headers = headers else {
            return false
        }
        
        for (key, _) in headers {
            if key.lowercased() == needle.lowercased() {
                return true
            }
        }
        
        return false
    }
    
}

public enum ResponderError: Error {
    case ResourceNotFound(bundle: Bundle, resource: String)
}

/// Protocol for objects that produce responses to requests
public protocol Responder {
    
    func respond(request: Request, resultBlock: @escaping RoutingResultBLock)

}

/// Responder that produces a response with a given bundle resource
public class ResourceResponder: Responder {

    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public init(bundle: Bundle, resource: String) throws {
        if let url = bundle.url(forResource: resource, withExtension: nil) {
            self.url = url
        } else {
            throw ResponderError.ResourceNotFound(bundle: bundle, resource: resource)
        }
    }
    
    public func respond(request: Request, resultBlock: @escaping RoutingResultBLock) {
        do {
            let data = try Data.init(contentsOf: url)
            resultBlock(.response(Response(status: .ok, data: data, contentType: .TextPlain))) //TODO contentType
        } catch {
            resultBlock(.error(error))
        }
    }
    
}

/// Responder that produces a response with the given content
public class ContentResponder: Responder {

    private let data: Data
    private let contentType: ContentType
    
    public init(string: String, contentType: ContentType, encoding: String.Encoding) {
        self.data = string.data(using: encoding)!
        self.contentType = contentType
    }

    public init(data: Data, contentType: ContentType) {
        self.data = data
        self.contentType = contentType
    }
    
    public func respond(request: Request, resultBlock: @escaping RoutingResultBLock) {
        resultBlock(.response(Response(status: .ok, data: data, contentType: contentType)))
    }
    
}

/// Responder that takes a block that itself produces a response given a request
public class BlockResponder: Responder {
    
    public typealias BlockResponderBlock = (Request, @escaping RoutingResultBLock) -> ()
    
    private let block: BlockResponderBlock
    
    public init(block: @escaping BlockResponderBlock) {
        self.block = block
    }
    
    public func respond(request: Request, resultBlock: @escaping RoutingResultBLock) {
        block(request, resultBlock)
    }
}

/// Responder that simply responds with the given response status
public class StatusResponder: Responder {
    
    private let status: ResponseStatus
    
    public init(status: ResponseStatus) {
        self.status = status
    }
    
    public func respond(request: Request, resultBlock: @escaping RoutingResultBLock) {
        resultBlock(.response(Response(status: status)))
    }
    
}
