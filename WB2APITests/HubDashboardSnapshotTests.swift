import XCTest
import SwiftUI
import UIKit
@testable import WB2API

/// These attachments use synthetic fixtures, not the user's server/account data.
final class HubDashboardSnapshotTests: XCTestCase {
    @MainActor
    func testDashboardLayoutsInLightAndDark() async throws {
        let overview = try DashboardFixture.overview()
        let usage = try DashboardFixture.usage(range: .all)
        for style in [UIUserInterfaceStyle.light, .dark] {
            let theme = style == .dark ? "dark" : "light"
            try await capture(HubOverviewContent(data: overview, updated: DashboardFixture.now), name: "hub-overview-\(theme)-fixture", style: style)
            try await capture(HubUsageContent(presentation: usage, range: .constant(.all), dimension: .constant(.account), updated: DashboardFixture.now), name: "hub-data-\(theme)-fixture", style: style)
        }
    }

    @MainActor
    private func capture<V: View>(_ root: V, name: String, style: UIUserInterfaceStyle) async throws {
        let view = root.environment(\.colorScheme, style == .dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: "zh_CN"))
        let controller = UIHostingController(rootView: view)
        let size = CGSize(width: 390, height: 1450)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = style
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.backgroundColor = .systemBackground
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        XCTAssertEqual(image.size.width, 390)
        XCTAssertNotNil(image.cgImage)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
    }
}
