import os

extension Logger {
    static let subsystem = "com.fugaif.ImasLiveDB"

    static let database = Logger(subsystem: subsystem, category: "database")
    static let cloudkit = Logger(subsystem: subsystem, category: "cloudkit")
    static let community = Logger(subsystem: subsystem, category: "community")
    static let musickit = Logger(subsystem: subsystem, category: "musickit")
    static let speech = Logger(subsystem: subsystem, category: "speech")
    static let image = Logger(subsystem: subsystem, category: "image")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let ocr = Logger(subsystem: subsystem, category: "ocr")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let notification = Logger(subsystem: subsystem, category: "notification")
}
