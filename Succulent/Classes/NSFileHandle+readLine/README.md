NSFileHandle-readLine
=====================

A simple Cocoa / Objective-C NSFileHandle category that adds the ability to read a file line by line.

License
-------

Dual-licensed under the FreeBSD license and MIT license (either license may be chosen based on your preference).

Usage
-----

To use, just grab "NSFileHandle+readLine.h" and "NSFileHandle+readLine.m" from the repository and add it to your 
project in Xcode like normal.

Then, with any instance of NSFileHandle, use "- readLineWithDelimiter:" to read the next line in the file, where
new lines are determined by the delimiter sent.

An NSData* object is returned with the line if found, or nil if no more lines were found.

Example Code Snippet
--------------------

NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:@"path/to/my/file"]; 

NSData *line = [fileHandle readLineWithDelimiter:@"\n"];

// For a slightly more complete example, checkout the ReadLineDemo project in this repository.

Changing Buffer Size
--------------------

"- readLineWithDelimiter:" uses a buffer of 1024 bytes when reading the line into the returned NSData* object, but
you're welcome to change this to suit your needs. Just change bufferSize's value at the top of the method in
"NSFileHandle+readLine.m" to make it smaller or bigger.
