//
//  SSAudioUtil.swift
//  SSAudioQueueRecording
//
//  Created by Michael on 2020/4/3.
//  Copyright © 2020 Michael. All rights reserved.
//

import UIKit

class SSAudioUtil: NSObject {

}

// MARK: Utility functions
func SSCheckError(_ error: OSStatus, _ message: String) {
    guard error != noErr else { return }
    guard error > 0 else {
        print("OSStatus error code must be greater than 0: \(message)  \(error)")
        return
    }
    
    let count = 5
    let stride = MemoryLayout<OSStatus>.stride
    let byteCount = stride * count
    
    var err = CFSwapInt32BigToHost(UInt32(error))
    var charArray = [CChar](repeating: 0, count: byteCount)
    print("Audio Error: \(error)")
    withUnsafeBytes(of: &err, { buffer in
        for (index, byte) in buffer.enumerated() {
            charArray[index + 1] = CChar(byte)
        }
    })
    
    let v1 = charArray[1], v2 = charArray[2], v3 = charArray[3], v4 = charArray[4]
    if isprint(Int32(v1)) > 0 && isprint(Int32(v2)) > 0 && isprint(Int32(v3)) > 0 && isprint(Int32(v4)) > 0 {
        charArray[0] = "\'".utf8CString[0]
        charArray[5] = "\'".utf8CString[0]
        if let errStr = String(bytesNoCopy: &charArray, length: charArray.count, encoding: .ascii, freeWhenDone: false) {
            print("Audio Error: \(message) \(errStr)")
            return
        }
    }
    print("Audio Error: \(message)")
}
