//
//  SSAudioQueuePlayer.swift
//  SSAudioQueuePlayer
//
//  Created by Michael on 2020/4/21.
//  Copyright © 2020 Michael. All rights reserved.
//

import UIKit
import AudioToolbox
import AVFoundation

fileprivate let kNumberBuffers: Int = 3

class SSAudioQueuePlayer: NSObject {
    var mDataFormat: AudioStreamBasicDescription = AudioStreamBasicDescription()
    var mAudioQueue: AudioQueueRef? = nil
    var mAudioFile: AudioFileID? = nil
    var mBuffSize: UInt32 = 0
    var mCurrentPacketIndex: Int64 = 0
    var mIsRunning = false
    var mNumPacketsToRead: UInt32 = 0
    var mPacketDescs: UnsafeMutablePointer<AudioStreamPacketDescription>?
    var mBuffers = Array<AudioQueueBufferRef?>(repeating: nil, count: kNumberBuffers)

    func play(url:NSURL) -> Void {
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            
        }
        
        mIsRunning = true
        
        prepareAudioQueue(url: url)
        
        AudioQueueStart(mAudioQueue!, nil)
        
        let inUserPointer = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)
        
        for index in 0..<kNumberBuffers {
            handleOutputBufferCallback(inUserPointer, mAudioQueue!, mBuffers[index]!)
        }

    }
    
    func prepareAudioQueue(url:NSURL) -> Void {
        var status: OSStatus = AudioFileOpenURL(url,AudioFilePermissions.readPermission, 0,&mAudioFile)
        SSCheckError(status, "AudioFileOpenURL")

        var dataFormatSize: UInt32 = UInt32(MemoryLayout<AudioStreamBasicDescription>.size(ofValue: mDataFormat))
        status = AudioFileGetProperty(mAudioFile!, kAudioFilePropertyDataFormat, &dataFormatSize, &mDataFormat)
        SSCheckError(status, "AudioFileGetProperty DataFormat")

        let voidPtr = Unmanaged.passRetained(self).toOpaque()
        status = AudioQueueNewOutput(&mDataFormat, handleOutputBufferCallback, voidPtr, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue, 0, &mAudioQueue)
        SSCheckError(status, "AudioQueueNewOutput")

        var maxPacketSize:UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        
        status = AudioFileGetProperty(mAudioFile!, kAudioFilePropertyPacketSizeUpperBound, &propertySize, &maxPacketSize)
        SSCheckError(status, "AudioFileGetProperty PacketSizeUpperBound")

        deriveBufferSize(asbDescription: mDataFormat, maxPacketSize: maxPacketSize, seconds: 0.5, outBufferSize: &mBuffSize, outNumPacketsToRead: &mNumPacketsToRead)
        
        //PacketDescription
        let isFormatVBR = mDataFormat.mBytesPerPacket == 0 || mDataFormat.mFramesPerPacket == 0
        if isFormatVBR {
            let descsSize = MemoryLayout<AudioStreamPacketDescription>.size
            mPacketDescs = malloc(Int(mNumPacketsToRead) * descsSize)?.assumingMemoryBound(to: AudioStreamPacketDescription.self)
            
//            mPacketDescs = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: (Int(mNumPacketsToRead) * MemoryLayout<AudioStreamPacketDescription>.size))

        }
        else{
            mPacketDescs = nil
        }
        
        //magicCookie
        var cookieSize: UInt32 = UInt32(MemoryLayout<UInt32>.size)
        status = AudioFileGetPropertyInfo(mAudioFile!, kAudioFilePropertyMagicCookieData, &cookieSize, nil)
        SSCheckError(status, "AudioFileGetPropertyInfo MagicCookieData")

        if (status != 0 && cookieSize > 0) {
            let magicCookie:UnsafeMutableRawPointer = malloc(Int(cookieSize))
            status = AudioFileGetProperty(mAudioFile!, kAudioFilePropertyMagicCookieData, &cookieSize, magicCookie)
            SSCheckError(status, "AudioFileGetProperty MagicCookieData")

            status = AudioQueueSetProperty(mAudioQueue!, kAudioQueueProperty_MagicCookie, magicCookie, cookieSize)
            SSCheckError(status, "AudioQueueSetProperty MagicCookieData")
            
            free(magicCookie)

        }
        
        mCurrentPacketIndex = 0
        for index in 0..<kNumberBuffers {
            status = AudioQueueAllocateBuffer(mAudioQueue!, mBuffSize, &mBuffers[index])
            SSCheckError(status, "AudioQueueAllocateBuffer")
            
//            let voidPtr = Unmanaged.passRetained(self).toOpaque()
//            handleOutputBufferCallback(voidPtr, mAudioQueue!, mBuffers[index]!)
        }
        
        let gain: Float = 1.0
        status = AudioQueueSetParameter(mAudioQueue!, kAudioQueueParam_Volume, gain)
        SSCheckError(status, "AudioQueueSetParameter Volume")
    }

    let handleOutputBufferCallback: AudioQueueOutputCallback = {
        (inUserData:UnsafeMutableRawPointer?, inAQ:AudioQueueRef, inBuffer:AudioQueueBufferRef) -> ()
        in
        
        let player = unsafeBitCast(inUserData!, to:SSAudioQueuePlayer.self)
        if !player.mIsRunning {
            print("not running")
            return
        }
        
        var numBytesReadFromFile: UInt32 = inBuffer.pointee.mAudioDataBytesCapacity
        var numPackets: UInt32 = player.mNumPacketsToRead
        
        var status = AudioFileReadPacketData(player.mAudioFile!, false, &numBytesReadFromFile, player.mPacketDescs, player.mCurrentPacketIndex, &numPackets, inBuffer.pointee.mAudioData)
        SSCheckError(status, "AudioFileReadPacketData")

        if (numPackets > 0){
            inBuffer.pointee.mAudioDataByteSize = numBytesReadFromFile
            inBuffer.pointee.mPacketDescriptionCount = numPackets
            status = AudioQueueEnqueueBuffer(inAQ, inBuffer, (player.mPacketDescs == nil ? 0 : numPackets), player.mPacketDescs)
            SSCheckError(status, "AudioQueueEnqueueBuffer")

            player.mCurrentPacketIndex = player.mCurrentPacketIndex + Int64(numPackets)
            
            print("play  \(numPackets)")

        }else{
            print("stop")
            AudioQueueStop(inAQ, false)
            player.mIsRunning = false
        }
    }
    
    func deriveBufferSize(asbDescription:AudioStreamBasicDescription,maxPacketSize:UInt32,seconds:Float64,outBufferSize: UnsafeMutablePointer<UInt32>,outNumPacketsToRead: UnsafeMutablePointer<UInt32>) -> Void {
        let maxBufferSize:UInt32 = 0x50000
        let minBufferSize:UInt32 = 0x4000
        
        if asbDescription.mFramesPerPacket != 0 {
            let numPacketsForTime = asbDescription.mSampleRate/Double(asbDescription.mFramesPerPacket)*seconds
            outBufferSize.pointee = UInt32(numPacketsForTime)*UInt32(maxPacketSize)
        }
        else
        {
            outBufferSize.pointee = max(maxBufferSize, maxPacketSize)
        }
        
        if (outBufferSize.pointee > maxBufferSize && outBufferSize.pointee > maxPacketSize )
        {
            outBufferSize.pointee = maxBufferSize
        }
        else {
            if (outBufferSize.pointee < minBufferSize)
            {
                outBufferSize.pointee = minBufferSize
            }
        }
        
        outNumPacketsToRead.pointee = outBufferSize.pointee / maxPacketSize
    }
}
