import Cocoa

let application = NSApplication.shared
application.setActivationPolicy(ProcessInfo.processInfo.environment["SHORELINE_UI_TESTING"] == "1" ? .regular : .accessory)
let controller = AppController()
application.delegate = controller
application.run()
