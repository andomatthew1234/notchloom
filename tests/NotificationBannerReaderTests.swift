import AppKit
import Foundation

@main struct NotificationBannerReaderTests {
    static func main() throws {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let cases: [(CGRect, Bool, String)] = [
            (CGRect(x: 1090, y: 35, width: 360, height: 120), true, "standard banner"),
            (CGRect(x: 1090, y: 360, width: 360, height: 120), true, "stacked banner below old cutoff"),
            (CGRect(x: 1090, y: 35, width: 360, height: 400), true, "expanded banner above old height limit"),
            (CGRect(x: 8, y: 41, width: 360, height: 180), false, "desktop widget"),
            (CGRect(x: 1090, y: 0, width: 380, height: 956), false, "notification drawer"),
            (CGRect(x: 1090, y: -200, width: 360, height: 120), false, "offscreen window")
        ]
        for (frame, expected, name) in cases {
            precondition(NotificationBannerReader.isBanner(frame, on: screen) == expected, name)
            print("PASS \(name)")
        }
        precondition(NotificationBannerReader.isBanner(CGRect(x: -400, y: -800, width: 360, height: 180),
            on: CGRect(x: -1920, y: -1080, width: 1920, height: 1080)))
        print("PASS secondary display with negative coordinates")
        precondition(NotificationBannerReader.isNotificationCard(role: "AXGroup", childIdentifiers: ["title", "body"]))
        precondition(!NotificationBannerReader.isNotificationCard(role: "AXGroup", childIdentifiers: ["widget-local:clock"]))
        precondition(!NotificationBannerReader.isNotificationCard(role: "AXStaticText", childIdentifiers: ["title", "body"]))
        print("PASS semantic notification cards inside display-sized hosts")
        let data = NotificationBannerReader.visibleBanners()
        let snapshot = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(snapshot["accessibilityAuthorized"] is Bool && snapshot["banners"] is [Any])
        print("PASS reader reports permission independently of banner presence")
    }
}
