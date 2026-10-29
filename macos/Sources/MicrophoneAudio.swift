import AppKit
import AVFoundation
import AudioToolbox
import CoreAudio

struct AudioInput {
    let device: AudioDeviceID
    let id: String
    let name: String
    let usb: Bool
}
enum AudioInputs {
    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    private static func text(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String {
        var property = address(selector); var value: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr, let value else { return "" }
        return value.takeRetainedValue() as String
    }
    static func list() -> [AudioInput] {
        var property = address(kAudioHardwarePropertyDevices); var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard !devices.isEmpty else { return [] }
        let result = devices.withUnsafeMutableBytes { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, $0.baseAddress!) }
        guard result == noErr else { return [] }
        return devices.compactMap { device in
            var streams = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeInput); var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            var transport = address(kAudioDevicePropertyTransportType); var type: UInt32 = 0; var typeSize: UInt32 = 4
            _ = AudioObjectGetPropertyData(device, &transport, 0, nil, &typeSize, &type)
            let uid = text(device, kAudioDevicePropertyDeviceUID)
            guard !uid.isEmpty else { return nil }
            return AudioInput(device: device, id: uid, name: text(device, kAudioObjectPropertyName), usb: type == kAudioDeviceTransportTypeUSB)
        }
    }
    static func defaultID() -> String {
        var property = address(kAudioHardwarePropertyDefaultInputDevice); var device: AudioDeviceID = 0; var size: UInt32 = 4
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &device) == noErr else { return "" }
        return text(device, kAudioDevicePropertyDeviceUID)
    }
    static func makeDefault(_ input: AudioInput) throws {
        guard list().contains(where: { $0.id == input.id && $0.device == input.device }) else { throw JustVibeRemoteError.message("This microphone was disconnected. Refresh the list.") }
        var property = address(kAudioHardwarePropertyDefaultInputDevice); var device = input.device
        guard AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, 4, &device) == noErr, defaultID() == input.id else {
            throw JustVibeRemoteError.message("macOS could not select that input. Choose it in System Settings → Sound → Input.")
        }
    }
    static func check(_ preference: MicrophonePreference?) throws {
        guard preference?.guardDictation == true else { return }
        if let issue = MicrophonePolicy.issue(preference, available: list().map(\.id), defaults: [defaultID()]) { throw JustVibeRemoteError.message(issue) }
    }
}

final class MicrophoneCapture {
    private var queue: AudioQueueRef?
    private var player: AVAudioPlayer?
    private let lock = NSLock()
    private var preview: PCMPreview?
    private var accepting = false
    private var callbacks = 0
    private var received = 0
    private var lastAudioAt = Date.distantPast
    private var sourceError: String?
    private(set) var inputID = ""
    var recording: Bool { queue != nil }
    var error: String? { lock.lock(); defer { lock.unlock() }; return sourceError }
    var hasClip: Bool { lock.lock(); defer { lock.unlock() }; return !(preview?.samples.isEmpty ?? true) }
    var hasSignal: Bool { lock.lock(); defer { lock.unlock() }; return preview?.hasSignal ?? false }
    var full: Bool { lock.lock(); defer { lock.unlock() }; return preview?.full ?? false }
    var sampleCount: Int { lock.lock(); defer { lock.unlock() }; return received }
    var bufferCount: Int { lock.lock(); defer { lock.unlock() }; return callbacks }
    var meterPercent: Double { lock.lock(); defer { lock.unlock() }; return recording && Date().timeIntervalSince(lastAudioAt) < 0.4 ? preview?.meterPercent ?? 0 : 0 }
    var decibels: Double? { lock.lock(); defer { lock.unlock() }; return preview?.decibels }
    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw JustVibeRemoteError.message("\(operation) failed (audio status \(status)). No other microphone was used.") }
    }
    private func currentID(_ queue: AudioQueueRef) -> String? {
        var uid: Unmanaged<CFString>?;var size=UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioQueueGetProperty(queue,kAudioQueueProperty_CurrentDevice,&uid,&size) == noErr,let uid else { return nil }
        return uid.takeRetainedValue() as String
    }
    func start(_ input: AudioInput) throws {
        clear()
        guard AVCaptureDevice.authorizationStatus(for:.audio) == .authorized else { throw JustVibeRemoteError.message("Allow Microphone access for JustVibe Remote to run a test.") }
        guard AudioInputs.list().filter({ $0.id == input.id && $0.device == input.device }).count == 1 else { throw JustVibeRemoteError.message("Selected microphone is unavailable. No other input was opened.") }
        var rate: Float64 = 0;var size: UInt32=8
        var property=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyNominalSampleRate,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(input.device,&property,0,nil,&size,&rate),"Read microphone format")
        guard rate.isFinite,(8000...192000).contains(rate),rate.rounded() == rate else { throw JustVibeRemoteError.message("Unsupported microphone sample rate.") }
        var format=AudioStreamBasicDescription(mSampleRate:rate,mFormatID:kAudioFormatLinearPCM,mFormatFlags:kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,mBytesPerPacket:2,mFramesPerPacket:1,mBytesPerFrame:2,mChannelsPerFrame:1,mBitsPerChannel:16,mReserved:0)
        var created: AudioQueueRef?
        try check(AudioQueueNewInput(&format,{ context, queue, buffer, _, _, _ in
            guard let context else { return }
            Unmanaged<MicrophoneCapture>.fromOpaque(context).takeUnretainedValue().receive(queue,buffer)
        },Unmanaged.passUnretained(self).toOpaque(),nil,nil,0,&created),"Create microphone recorder")
        guard let created else { throw JustVibeRemoteError.message("macOS did not create an input recorder.") }
        do {
            var uid=input.id as CFString
            try check(withUnsafePointer(to:&uid) { AudioQueueSetProperty(created,kAudioQueueProperty_CurrentDevice,$0,UInt32(MemoryLayout<CFString>.size)) },"Select microphone")
            guard currentID(created) == input.id else { throw JustVibeRemoteError.message("Recorder source does not match your selection. Test cancelled.") }
            preview=PCMPreview(sampleRate:Int(rate));inputID=input.id
            for _ in 0..<3 {
                var buffer: AudioQueueBufferRef?
                try check(AudioQueueAllocateBuffer(created,UInt32(rate / 10) * 2,&buffer),"Allocate audio buffer")
                guard let buffer else { throw JustVibeRemoteError.message("macOS did not provide an audio buffer.") }
                try check(AudioQueueEnqueueBuffer(created,buffer,0,nil),"Prepare audio buffer")
            }
            lock.lock();accepting=true;lock.unlock()
            try check(AudioQueueStart(created,nil),"Start microphone recorder")
            queue=created
        } catch {
            lock.lock();accepting=false;lock.unlock();AudioQueueDispose(created,true);throw error
        }
    }
    private func receive(_ source: AudioQueueRef, _ buffer: AudioQueueBufferRef) {
        lock.lock();let active=accepting;lock.unlock();guard active else{return}
        guard currentID(source) == inputID else { lock.lock();sourceError="Audio source changed. No audio from another mic was accepted.";accepting=false;lock.unlock();return }
        let count=Int(buffer.pointee.mAudioDataByteSize) / MemoryLayout<Int16>.size
        let data=buffer.pointee.mAudioData.assumingMemoryBound(to:Int16.self)
        let samples=Array(UnsafeBufferPointer(start:data,count:count))
        lock.lock()
        guard accepting else { lock.unlock();return }
        callbacks += 1;received += count;preview?.append(samples);lastAudioAt=Date()
        let requeue=preview?.full != true
        lock.unlock()
        if requeue {
            let status=AudioQueueEnqueueBuffer(source,buffer,0,nil)
            if status != noErr { lock.lock();sourceError="Audio input stopped (status \(status)).";accepting=false;lock.unlock() }
        }
    }
    func stop() {
        lock.lock();accepting=false;lock.unlock()
        if let queue { AudioQueueStop(queue,true);AudioQueueDispose(queue,true) }
        queue=nil
    }
    func play() throws {
        stop();player?.stop()
        lock.lock();let bytes=preview?.wave();lock.unlock()
        guard let bytes,hasClip else{return}
        player=try AVAudioPlayer(data:bytes);player?.play()
    }
    func clear() {
        stop();player?.stop();player=nil
        lock.lock();preview=nil;sourceError=nil;lastAudioAt = .distantPast;callbacks=0;received=0;lock.unlock();inputID=""
    }
    deinit { clear() }
}
