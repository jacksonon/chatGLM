import Foundation

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import UIKit
typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
typealias PlatformImage = NSImage
#endif

