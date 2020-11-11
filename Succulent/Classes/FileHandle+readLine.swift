//
//  FileHandle+readLine.swift
//  Succulent
//
//  Created by Daniel Muhra on 18/11/19.
//  Copyright © 2019 CaperWhite GmbH. All rights reserved.
//
//

import Foundation

/// Used to read a line within a file in chunks 
struct LineReader: IteratorProtocol {
    static private let bufferSize = 1024

    typealias Element = Data

    let fileHandle: FileHandle
    let delimiter: UInt8
    var found = false

    mutating func next() -> Data? {
        // We found the delimiter, so we are done
        guard !found else { return nil }

        let offset = self.fileHandle.offsetInFile
        let lineData = self.fileHandle.readData(ofLength: LineReader.bufferSize)

        // If the data is empty, we reached the end of the file. So we are done too
        if lineData.isEmpty { return nil }

        // If we don't find the delimiter, we simply return this data batch
        guard let index = lineData.firstIndex(of: delimiter) else { return lineData }

        // On the next iteration, we will terminate
        found = true

        // Small optimisation: If the delimiter is the last item, we simply return the whole data batch.
        if index == lineData.count - 1 { return lineData }

        // Set the handle right after the delimiter
        self.fileHandle.seek(toFileOffset: offset + UInt64(index) + 1)

        // Return the data up to the delimiter (and include the it).
        return lineData[0...index]
    }
    
}

extension FileHandle {
    // Standard delimiter
    static let delimiter = "\n".data(using: .ascii)!.first!

    func delimiterLength(_ delimiter: String) -> Int {
        return delimiter.data(using: .ascii)?.count ?? 0
    }

    func readLine(withDelimiter theDelimiter: String) -> Data? {
        // TODO: Remove this hack
        // We always use \n as delimiter in Succulent, so we can hardcode it.
        // Converting it to UInt8 was actually quite expensive (~30% of the overall computing time, if done each time).
        return self.readLine(withDelimiter: FileHandle.delimiter)
    }

    private func readLine(withDelimiter delimiter: UInt8) -> Data? {
        let reader = LineReader(fileHandle: self, delimiter: delimiter)

        // Simply read all batches and concatenate them until the delimiter is reached.
        let lineData = IteratorSequence(reader).reduce(Data(), +)

        return lineData.isEmpty ? nil : lineData
    }
}
