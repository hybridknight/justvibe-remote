import Foundation
import Darwin

/// One settings/mapping owner per user. Read-only diagnostics never own a session.
final class SingleInstanceLock {
    private var descriptor: Int32 = -1
    let url: URL
    init(directory: URL) { url = directory.appendingPathComponent("session.lock") }
    static func isReadOnly(_ arguments: [String]) -> Bool {
        let flags: Set<String> = ["--dictation-button-diagnostics", "--render-cursor-preview", "--connection-diagnostics", "--list-audio-inputs", "--render-preview", "--render-add-remote-preview", "--render-setup-preview", "--render-microphone-preview", "--render-connection-preview"]
        return arguments.contains { flags.contains($0) }
    }
    var ownerPID: Int32? {
        guard let text = try? String(contentsOf:url,encoding:.utf8) else { return nil }
        return Int32(text.trimmingCharacters(in:.whitespacesAndNewlines))
    }
    func acquire() throws -> Bool {
        if descriptor >= 0 { return true }
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let fd = Darwin.open(url.path,O_CREAT | O_RDWR | O_CLOEXEC | O_EXLOCK | O_NONBLOCK,S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            let failure=errno
            if failure == EWOULDBLOCK || failure == EAGAIN { return false }
            throw NSError(domain:NSPOSIXErrorDomain,code:Int(failure))
        }
        let bytes=Data("\(getpid())\n".utf8)
        guard ftruncate(fd,0) == 0, bytes.withUnsafeBytes({ Darwin.write(fd,$0.baseAddress,$0.count) }) == bytes.count else {
            let failure=errno;Darwin.close(fd);throw NSError(domain:NSPOSIXErrorDomain,code:Int(failure))
        }
        descriptor=fd;return true
    }
    func release() { if descriptor >= 0 { Darwin.close(descriptor);descriptor = -1 } }
    deinit { release() }
}
