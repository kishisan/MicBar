import Foundation

enum TimeFormatter {
    static func format(seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes < 60 {
            return secs > 0 ? "\(minutes)m \(secs)s" : "\(minutes)m"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        if mins > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(hours)h"
    }
}
