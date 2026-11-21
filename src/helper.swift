// MEEMO Print helper.
//   helper pages <pdf>               print the page count
//   helper devices                   list paired Bluetooth devices as "address<TAB>name"
//   helper job <ppd> <raster> <out>  run the vendor driver offline and save the printer command data
//   helper send <address>            stdin -> printer (RFCOMM channel 1); HOLD=<seconds> to keep the link open after EOF
import Foundation
import IOBluetooth
import PDFKit

func die(_ msg: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(code)
}

/// CUPS raster -> printer commands. Runs the vendor filter (rastertoM08F) and answers the status queries it sends
/// to the printer. macOS never relays those answers over Bluetooth, which is why normal printing hangs forever.
func makeJob(ppd: String, raster: String, out dst: String) -> Never {
    // query -> reply, measured from a real HTP-431: firmware version, paper OK (0x89; 0x88 = no paper), status, battery
    let replies: [([UInt8], [UInt8])] = [
        ([0x1f, 0x11, 0x07], [0x1a, 0x07, 0x02, 0x01, 0x08]),
        ([0x1f, 0x11, 0x11], [0x1a, 0x06, 0x89]),
        ([0x1f, 0x11, 0x12], [0x1a, 0x05, 0x98]),
        ([0x1f, 0x11, 0x43], [0x1a, 0x0f, 0x0c]),
        ([0x1f, 0x11, 0x08], [0x1a, 0x04, 0x64]),
    ]
    signal(SIGPIPE, SIG_IGN)
    var outP: [Int32] = [0, 0], bcP: [Int32] = [0, 0], sv: [Int32] = [0, 0]
    guard pipe(&outP) == 0, pipe(&bcP) == 0, socketpair(AF_UNIX, SOCK_STREAM, 0, &sv) == 0 else { die("pipe failed") }
    // Move everything above fd 4 so the dup2 calls below cannot overwrite each other.
    let fds = (outP + bcP + sv).map { fd -> Int32 in let n = fcntl(fd, F_DUPFD_CLOEXEC, 10); close(fd); return n }
    let (outR, outW, bcR, bcW, sa, sb) = (fds[0], fds[1], fds[2], fds[3], fds[4], fds[5])

    // CUPS filter convention: fd1 = output, fd3 = back-channel (printer replies), fd4 = side-channel
    var fa: posix_spawn_file_actions_t? = nil
    posix_spawn_file_actions_init(&fa)
    posix_spawn_file_actions_adddup2(&fa, outW, 1)
    posix_spawn_file_actions_adddup2(&fa, bcR, 3)
    posix_spawn_file_actions_adddup2(&fa, sb, 4)
    posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0)
    let filter = "/usr/libexec/cups/filter/rastertoM08F"
    let argv = [filter, "1", "user", "job", "1", "PageSize=A4", raster].map { strdup($0) } + [nil]
    var env = ProcessInfo.processInfo.environment
    env["PPD"] = ppd
    let envp = env.map { strdup("\($0)=\($1)") } + [nil]
    var pid: pid_t = 0
    guard posix_spawn(&pid, filter, &fa, nil, argv, envp) == 0 else { die("cannot start the printer driver") }
    close(outW); close(bcR); close(sb)
    _ = fcntl(bcW, F_SETFL, O_NONBLOCK)

    var out = Data()
    let done = DispatchSemaphore(value: 0)
    Thread {
        var tail = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(outR, &buf, buf.count)
            if n <= 0 { break }
            out.append(buf, count: n)
            tail.append(buf, count: n)
            for (query, reply) in replies {
                while let r = tail.range(of: Data(query)) {
                    tail = Data(tail[r.upperBound...])
                    _ = write(bcW, reply, reply.count)
                }
            }
            tail = Data(tail.suffix(2))  // a query may be split across two reads
        }
        done.signal()
    }.start()
    Thread {
        var q = [UInt8](repeating: 0, count: 1024)
        while recv(sa, &q, q.count, 0) > 0 {
            let data: [UInt8] = [3: [1], 4: Array("MDL:HTP-431;".utf8), 5: [0]][q[0]] ?? []
            let msg = [q[0], 0, UInt8(data.count >> 8), UInt8(data.count & 0xff)] + data
            _ = Darwin.send(sa, msg, msg.count, 0)
        }
    }.start()

    DispatchQueue.global().asyncAfter(deadline: .now() + 120) { kill(pid, SIGKILL) }
    var status: Int32 = 0
    waitpid(pid, &status, 0)
    _ = done.wait(timeout: .now() + 5)
    // 1d 76 30 00 = the raster-image command; without it the driver produced nothing printable
    guard status == 0, out.range(of: Data([0x1d, 0x76, 0x30, 0x00])) != nil else { die("printer driver failed (status \(status))") }
    do { try out.write(to: URL(fileURLWithPath: dst)) } catch { die("cannot write \(dst)") }
    exit(0)
}

final class Echo: NSObject, IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!, data p: UnsafeMutableRawPointer!, length n: Int) {
        let d = Data(bytes: p, count: n)
        FileHandle.standardOutput.write(d)
        FileHandle.standardError.write("<< \(d.map { String(format: "%02x", $0) }.joined())\n".data(using: .utf8)!)
    }
}

/// stdin -> printer, printer replies -> stdout (+ hex on stderr). Keeps the link open HOLD seconds after EOF so the
/// printer can finish receiving before we disconnect.
func relay(to address: String) -> Never {
    let hold = Double(ProcessInfo.processInfo.environment["HOLD"] ?? "12") ?? 12
    guard let dev = IOBluetoothDevice(addressString: address), dev.openConnection() == kIOReturnSuccess else { exit(2) }
    let delegate = Echo()
    var chOpt: IOBluetoothRFCOMMChannel? = nil
    guard dev.openRFCOMMChannelSync(&chOpt, withChannelID: 1, delegate: delegate) == kIOReturnSuccess, let ch = chOpt else { exit(3) }
    let mtu = Int(ch.getMTU())
    FileHandle.standardError.write("relay open mtu \(mtu)\n".data(using: .utf8)!)
    var total = 0
    var eofAt: Date? = nil
    Thread {
        while true {
            let data = FileHandle.standardInput.availableData
            DispatchQueue.main.async {
                if data.isEmpty { eofAt = eofAt ?? Date(); return }
                var i = 0
                while i < data.count {
                    var chunk = [UInt8](data[i..<min(i + mtu, data.count)])
                    if ch.writeSync(&chunk, length: UInt16(chunk.count)) != kIOReturnSuccess { exit(4) }
                    i += chunk.count
                }
                total += data.count
            }
            if data.isEmpty { break }
        }
    }.start()
    while true {
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        if let e = eofAt, Date().timeIntervalSince(e) > hold { break }
    }
    FileHandle.standardError.write("relay sent \(total)\n".data(using: .utf8)!)
    ch.close()
    dev.closeConnection()
    exit(0)
}

let args = CommandLine.arguments
switch (args.count > 1 ? args[1] : "", args.count) {
case ("pages", 3):
    guard let doc = PDFDocument(url: URL(fileURLWithPath: args[2])) else { die("cannot read PDF: \(args[2])") }
    print(doc.pageCount)
case ("devices", 2):
    for d in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [] {
        print("\(d.addressString ?? "")\t\(d.name ?? "")")
    }
case ("job", 5): makeJob(ppd: args[2], raster: args[3], out: args[4])
case ("send", 3): relay(to: args[2])
default: die("usage: helper pages <pdf> | devices | job <ppd> <raster> <out> | send <address>", 64)
}
