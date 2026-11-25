import CoreGraphics

/// Geometry of the drop-down terminal. The window frame stays inside the target screen's visible
/// area for the whole animation; only the content moves, clipped by the window, so a display
/// stacked above never shows the panel mid-slide.
public struct QuakeSlide: Sendable, Equatable {
  /// Window frame in screen coordinates (origin bottom-left, y up).
  public let frame: CGRect
  /// Vertical translation in points (y up) that places the content just above the frame's top
  /// edge, i.e. fully clipped.
  public let hiddenContentOffset: CGFloat

  /// - Parameter heightFraction: fraction 0-1 of the visible height.
  public init(visible: CGRect, heightFraction: Double) {
    let height = (visible.height * heightFraction).rounded()
    frame = CGRect(x: visible.minX, y: visible.maxY - height, width: visible.width, height: height)
    hiddenContentOffset = height
  }
}
