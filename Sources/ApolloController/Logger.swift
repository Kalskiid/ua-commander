import Foundation

private let logPath = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/ApolloController.log")
private let logFile: FileHandle? = {
    FileManager.default.createFile(atPath: logPath, contents: nil)
    return FileHandle(forWritingAtPath: logPath)
}()

func writeLog(_ message: String) {
    let line = "\(Date()) \(message)\n"
    logFile?.seekToEndOfFile()
    logFile?.write(line.data(using: .utf8) ?? Data())
    // Also print to stdout in case running in terminal
    print(line, terminator: "")
}
