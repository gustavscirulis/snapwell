import Foundation
import CoreFoundation
import CoreGraphics
import Observation
#if os(iOS)
import UIKit
#endif

/// A device-local preference. Width changes resolve the layout without changing the saved choice.
@Observable
@MainActor
final class GridColumnPreferences {
    enum Device {
        case phone, pad, mac

        var minimumColumns: Int { self == .mac ? 2 : 1 }
        var maximumColumns: Int { self == .phone ? 4 : 8 }
        var defaultColumns: Int { self == .phone ? 2 : 4 }
        var minimumItemWidth: CGFloat { self == .phone ? 80 : 120 }

        @MainActor static var current: Self {
            #if os(iOS)
            UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
            #else
            .mac
            #endif
        }
    }

    static let storageKey = "gridColumnCount"
    let device: Device
    private let defaults: UserDefaults
    private var storedCount: Int

    var preferredColumnCount: Int {
        get { storedCount }
        set {
            storedCount = min(device.maximumColumns, max(device.minimumColumns, newValue))
            defaults.set(storedCount, forKey: Self.storageKey)
        }
    }

    init(device: Device, defaults: UserDefaults = .standard) {
        self.device = device
        self.defaults = defaults
        let initial: Int
        if defaults.object(forKey: Self.storageKey) != nil {
            let saved = defaults.object(forKey: Self.storageKey) as? NSNumber
            if let saved, CFGetTypeID(saved) != CFBooleanGetTypeID(),
               saved.doubleValue.isFinite, saved.doubleValue.rounded() == saved.doubleValue {
                initial = Int(min(Double(device.maximumColumns), max(Double(device.minimumColumns), saved.doubleValue)))
            } else {
                initial = device.defaultColumns
            }
        } else if device == .mac, let legacy = defaults.string(forKey: "thumbnailSize") {
            initial = ["small": 6, "medium": 4, "large": 3, "extraLarge": 2][legacy] ?? device.defaultColumns
        } else {
            initial = device.defaultColumns
        }
        storedCount = initial
        defaults.set(initial, forKey: Self.storageKey)
    }

    func columns(availableWidth: CGFloat, spacing: CGFloat) -> Int {
        Self.effectiveColumns(preferred: preferredColumnCount, availableWidth: availableWidth,
                              minimumItemWidth: device.minimumItemWidth, spacing: spacing)
    }

    nonisolated static func effectiveColumns(
        preferred: Int, availableWidth: CGFloat, minimumItemWidth: CGFloat, spacing: CGFloat
    ) -> Int {
        guard availableWidth.isFinite, availableWidth > 0,
              minimumItemWidth.isFinite, minimumItemWidth > 0,
              spacing.isFinite, spacing >= 0 else { return 1 }
        let fitting = floor((availableWidth + spacing) / (minimumItemWidth + spacing))
        return Int(max(1, min(CGFloat(max(1, preferred)), fitting)))
    }

    func zoomIn() { preferredColumnCount -= 1 }
    func zoomOut() { preferredColumnCount += 1 }
}
