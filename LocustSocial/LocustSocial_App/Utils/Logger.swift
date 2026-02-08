
import Foundation

enum Log {
    static func info(_ msg: String) { print("ℹ️", msg) }
    static func warn(_ msg: String) { print("⚠️", msg) }
    static func error(_ msg: String) { print("❌", msg) }
}
