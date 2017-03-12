//
//  Tracer.swift
//  Pods
//
//  Created by Thomas Carey on 6/03/17.
//
//

import Foundation

protocol Traceable {
    var traceFormat: String { get }
}

internal struct TraceMeta: Traceable {
    
    var method: String?
    var protocolScheme: String?
    var host: String?
    var file: String?
    var version: String?
    
    var traceFormat: String {
        
        var trace = [String]()
        if let method = method {
            trace.append("Method: \(method)")
        }
        if let version = version {
            trace.append("Protocol-Version: \(version)")
        }
        if let protocolScheme = protocolScheme {
            trace.append("Protocol: \(protocolScheme)")
        }
        if let host = host {
            trace.append("Host: \(host)")
        }
        if let file = file {
            trace.append("File: \(file)")
        }
        
        return "\n\(trace.joined(separator: "\n"))"
    }
    
    init(method: String?, protocolScheme: String?, host: String?, file: String?, version: String?) {
        self.method = method
        self.protocolScheme = protocolScheme
        self.host = host
        self.file = file
        self.version = version
    }
    
    init(dictionary: [String: String]) {
        self = TraceMeta(method: dictionary["Method"], protocolScheme: dictionary["Protocol"], host: dictionary["Host"], file: dictionary["File"], version: dictionary["Protocol-Version"])
    }
}

extension Request: Traceable {
    
    var traceFormat: String {
        
        var trace = [String]()
        trace.append("\(method) \(path)")
        self.headers?.forEach({ (key, value) in
            trace.append("\(key): \(value)")
        })
        
        return trace.joined(separator: "\n")
    }
}

extension HTTPURLResponse: Traceable {
    
    var traceFormat: String {
        var trace = [String]()
        
        trace.append("HTTP/1.1 \(statusCode)")
        self.allHeaderFields.forEach { (key, value) in
            trace.append("\(key): \(value)")
        }
        
        return trace.joined(separator: "\n")
    }
}

class TraceWriter {
    enum Component {
        case meta
        case requestHeader
        case requestBody
        case responseHeader
        case responseBody
        
        var name: String? {
            switch self {
            case .meta: return nil
            case .requestBody: return "Request-Body"
            case .requestHeader: return "Request-Header"
            case .responseBody: return "Response-Body"
            case .responseHeader: return "Response-Header"
            }
        }
        
        func headerPart(token: String) -> String {
            if let name = self.name {
                return "\(name):<<--EOF-\(token)-\n"
            } else {
                return "\n"
            }
        }
        
        func footerPart(token: String) -> String {
            if let _ = self.name {
                return "\n--EOF-\(token)-\n"
            } else {
                return "\n"
            }
        }
    }
    
    let fileURL: URL
    
    init(fileURL: URL) {
        self.fileURL = fileURL
        
        writeHeader()
    }
    
    private func writeHeader() {
        let headerString = "HTTP-Trace-Version: 1.0\nGenerator: Succulent/1.0\n"
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            if fileHandle.offsetInFile == 0 {
                fileHandle.write(headerString.data(using: .utf8)!)
            }
        } else {
            try! headerString.appendToURL(fileURL: fileURL)
        }
    }
    
    func writeComponent(component: Component, content: Data, token: String) throws {
        try component.headerPart(token: token).appendToURL(fileURL: fileURL)
        try content.append(fileURL: fileURL)
        try component.footerPart(token: token).appendToURL(fileURL: fileURL)
    }
    
    func writeComponent(component: Component, content: Traceable, token: String) throws {
        let parts = [component.headerPart(token: token), content.traceFormat, component.footerPart(token: token)]
        try parts.joined(separator: "").appendToURL(fileURL: fileURL)
    }
}

extension String {
    func appendLineToURL(fileURL: URL) throws {
        try (self + "\n").appendToURL(fileURL: fileURL)
    }
    
    func appendToURL(fileURL: URL) throws {
        let data = self.data(using: String.Encoding.utf8)!
        try data.append(fileURL: fileURL)
    }
}

extension Data {
    func append(fileURL: URL) throws {
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        }
        else {
            let directoryURL = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            try write(to: fileURL, options: .atomic)
        }
    }
}

struct Trace {
    var meta : TraceMeta
    var responseHeader : Data?
    var responseBody: Data
}

class TraceReader {
    
    let fileURL: URL
    let delimiter = "\n"
    
    let tokenStartRegex = try! NSRegularExpression(pattern: "^(.+):<<--EOF-(.+)-$", options: [])
    let metaRegex = try! NSRegularExpression(pattern: "^(.+): (.+)$", options: [])
    
    init(fileURL: URL) {
        self.fileURL = fileURL
    }
    
    func readFile() -> [Trace]? {
        guard let fileHandle = FileHandle(forReadingAtPath: fileURL.path) else {
            return nil
        }
        defer {
            fileHandle.closeFile()
        }
        
        if consumeHeader(fileHandle: fileHandle) {
            var traces = [Trace]()
            while let trace = consumeTrace(fileHandle: fileHandle) {
                traces.append(trace)
            }
            
            return traces
        }
        
        return nil
    }
    
    private func consumeHeader(fileHandle: FileHandle) -> Bool {
        let offset = fileHandle.offsetInFile
        
        guard let data = fileHandle.readLine(withDelimiter: "\n") else {
            fileHandle.seek(toFileOffset: offset)
            return false
        }
        
        guard let contents = String(data: data, encoding: .ascii), contents == "HTTP-Trace-Version: 1.0\n" else {
            fileHandle.seek(toFileOffset: offset)
            return false
        }
        
        // lets just consume the next line
        let _ = fileHandle.readLine(withDelimiter: "\n")
        let _ = fileHandle.consumeEmptyLines()
        
        return true
    }
    
    
    enum ComponentType : String {
        case responseHeader = "Response-Header"
        case responseBody = "Response-Body"
    }
    
    struct Component {
        var type: ComponentType
        var data: Data
    }
    
    

    private func consumeTrace(fileHandle: FileHandle) -> Trace? {
    
        while(testForEmptyLine(fileHandle: fileHandle)) {
            if !consumeLines(count: 1, fileHandle: fileHandle) {
                return nil
            }
        }
        
        var meta = [String: String]()
    
        // Consume the Metas
        while(!testStartOfComponent(fileHandle: fileHandle)) {
            if let data = fileHandle.readLine(withDelimiter: delimiter) {
                if let line = String(data: data, encoding: .utf8) {
                    
                    let matches = metaRegex.matches(in: line, options: [], range: line.nsrange)
                    matches.forEach({ (match) in
                        let key = line.substring(with: match.rangeAt(1))!
                        let value = line.substring(with: match.rangeAt(2))!
                        
                        meta[key] = value
                    })
                }
            } else {
                // At the end of the file
                return nil
            }
            
        }
        
        var responseHeader : Data?
        var responseBody : Data?
        
        // Consume components until no longer at the start
        while(testStartOfComponent(fileHandle: fileHandle)) {
            if let component = consumeComponent(fileHandle: fileHandle) {
                switch component.type {
                case .responseBody:
                    responseBody = component.data
                case .responseHeader:
                    responseHeader = component.data
                }
            }
        }
        
        if let responseBody = responseBody {
            return Trace(meta: TraceMeta(dictionary: meta), responseHeader: responseHeader, responseBody: responseBody)
        }
        return nil
    }
    
    private func testStartOfComponent(fileHandle: FileHandle) -> Bool {
        let startingOffset = fileHandle.offsetInFile
        defer {
            fileHandle.seek(toFileOffset: startingOffset)
        }
        guard let data = fileHandle.readLine(withDelimiter: delimiter), let line = String(data: data, encoding: .utf8) else {
            return false
        }
        let matches = tokenStartRegex.matches(in: line, options: [], range: line.nsrange)
        return matches.count > 0
    }
    
    private func consumeComponent(fileHandle: FileHandle) -> Component? {
        let startingOffset = fileHandle.offsetInFile
        guard let data = fileHandle.readLine(withDelimiter: delimiter), let line = String(data: data, encoding: .utf8) else {
            fileHandle.seek(toFileOffset: startingOffset)
            return nil
        }
    
        let matches = tokenStartRegex.matches(in: line, options: [], range: line.nsrange)
        if matches.count > 0 {
            let contentType = line.substring(with: matches[0].rangeAt(1))!
            let token = line.substring(with: matches[0].rangeAt(2))!
            
            guard let data = consumeData(forToken: token, fileHandle: fileHandle) else {
                //Hit the end of the file
                return nil
            }
            
            guard let componentType = ComponentType(rawValue: contentType) else {
                //Unrecognised component
                //discard the component and move on
                return nil
            }
            
            return Component(type: componentType, data: data)
        } else {
            // not the start of content but could be the start of meta
            fileHandle.seek(toFileOffset: startingOffset)
            return nil
        }
    }
    
    
    
    private func testForEmptyLine(fileHandle: FileHandle) -> Bool {
        return testFor("", fileHandle: fileHandle)
    }
    
    private func testForToken(fileHandle: FileHandle, token:String) -> Bool {
        return testFor("--EOF-\(token)-", fileHandle: fileHandle)
    }
    
    private func testFor(_ str :String, fileHandle: FileHandle) -> Bool {
        let startingOffset = fileHandle.offsetInFile
        defer {
            fileHandle.seek(toFileOffset: startingOffset)
        }
        if let data = fileHandle.readLine(withDelimiter: delimiter) {
            if let line = String(data: data, encoding: .utf8) {
                if line == "\(str)\(delimiter)" {
                    return true
                }
            }
        }
        return false
    }
    
    private func consumeToken(fileHandle: FileHandle) -> Bool {
        return consumeLines(count: 1, fileHandle: fileHandle)
    }
    
    private func consumeLines(count: Int, fileHandle: FileHandle) -> Bool {
        for _ in (0..<count) {
            guard let _ = fileHandle.readLine(withDelimiter: delimiter) else {
                return false
            }
        }
        return true
    }
    
    
    private func consumeData(forToken token: String, fileHandle: FileHandle) -> Data? {
        let startingOffset = fileHandle.offsetInFile
        
        while (!testForToken(fileHandle: fileHandle, token: token)) {
            if(!consumeLines(count: 1, fileHandle: fileHandle)) {
                return nil
            }
        }
        
        let endingOffset = fileHandle.offsetInFile
        fileHandle.seek(toFileOffset: startingOffset)
        
        let data = fileHandle.readData(ofLength: Int(endingOffset - UInt64(fileHandle.delimiterLength(delimiter)) - startingOffset))
        
        fileHandle.seek(toFileOffset: endingOffset)
        let _ = consumeToken(fileHandle: fileHandle)
        
        return data
    }
    
    
}

extension FileHandle {
    
    func consumeEmptyLines() -> Int {
        var offset = offsetInFile
        var data = self.readLine(withDelimiter: "\n")
        var counter = 0
        
        while (data != nil) {
            if let contents = String(data: data!, encoding: .ascii), contents == "\n" {
                counter += 1
                offset = offsetInFile
                data = self.readLine(withDelimiter: "\n")
            } else {
                seek(toFileOffset: offset)
                return counter
            }
        }
        
        return counter
    }
}

extension String {
    /// An `NSRange` that represents the full range of the string.
    var nsrange: NSRange {
        return NSRange(location: 0, length: utf16.count)
    }
    
    /// Returns a substring with the given `NSRange`,
    /// or `nil` if the range can't be converted.
    func substring(with nsrange: NSRange) -> String? {
        guard let range = nsrange.toRange()
            else { return nil }
        let start = UTF16Index(range.lowerBound)
        let end = UTF16Index(range.upperBound)
        return String(utf16[start..<end])
    }
    
    /// Returns a range equivalent to the given `NSRange`,
    /// or `nil` if the range can't be converted.
    func range(from nsrange: NSRange) -> Range<Index>? {
        guard let range = nsrange.toRange() else { return nil }
        let utf16Start = UTF16Index(range.lowerBound)
        let utf16End = UTF16Index(range.upperBound)
        
        guard let start = Index(utf16Start, within: self),
            let end = Index(utf16End, within: self)
            else { return nil }
        
        return start..<end
    }
}



