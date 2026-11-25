import MacterminalCore
import MacterminalTerminal
import SwiftUI

/// Capa de bloques sobre la rejilla de la terminal: cabeceras con chip y acciones, separadores,
/// selección, foco, estado vacío y aviso de integración. Recibe todo inyectado (no conoce el
/// panel) y se aloja en `BlocksOverlayHostingView`, que deja pasar a la terminal todo clic fuera
/// de sus controles. Los rellenos van aparte, bajo el texto, en `BlocksBackdropView`.
struct BlocksOverlayView: View {
  nonisolated static let coordinateSpace = "BlocksOverlay"
  /// Sin una marca A autenticada en este plazo se asume que la integración no llegó.
  static let integrationTimeout: Duration = .seconds(3)

  let tracker: BlockTracker
  let state: BlockOverlayState
  /// Filas absolutas del buffer (scrollback incluido) y tamaño de celda en pt.
  let viewport: ViewportSnapshot
  let resolve: (RowAnchor) -> Int?
  let textProvider: (Range<Int>) -> String
  let insertIntoPrompt: (String, InsertionToken) -> InsertResult
  /// `false` si la shell no es zsh o no se pudo instalar la integración.
  let integrationAvailable: Bool
  let openPalette: () -> Void
  /// Compartido por todos los paneles: al activarse, el estado vacío se va de todos a la vez.
  let firstCommand: FirstCommandFlag

  @State private var integrationTimedOut = false
  @State private var bannerDismissed = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let geometry = BlockGeometry(viewport: viewport)
    let actions = BlockActions(
      tracker: tracker, resolve: resolve, textProvider: textProvider,
      insertIntoPrompt: insertIntoPrompt, toasts: .shared)
    ZStack(alignment: .topLeading) {
      ForEach(geometry.frames(of: tracker, resolve: resolve)) { frame in
        if let block = tracker.blocks.last(where: { $0.id == frame.id }) {
          BlockChromeView(
            block: block, frame: frame, geometry: geometry, state: state, actions: actions,
            accessibilityLabel: tracker.accessibilityLabel(for: block)
          )
          .frame(maxWidth: .infinity)
          .frame(height: geometry.height(of: frame.rows))
          .padding(.top, geometry.top(of: frame.rows.lowerBound))
        }
      }
      if showsEmptyState {
        BlocksEmptyStateView(
          directory: tracker.cwd, openPalette: openPalette, dismiss: firstCommand.markSet
        )
        .reportsRegion(.control("empty"), to: state)
        .padding(.top, viewport.cursor.map { geometry.top(of: $0.row + 1) } ?? 0)
        .transition(.opacity)
      }
      if let bannerCause {
        IntegrationBannerView(cause: bannerCause) { bannerDismissed = true }
          .reportsRegion(.control("banner"), to: state)
          .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .clipped()
    .coordinateSpace(.named(Self.coordinateSpace))
    .animation(BlockTokens.enter, value: bannerCause)
    .animation(reduceMotion ? nil : BlockTokens.exit, value: showsEmptyState)
    .task {
      do { try await Task.sleep(for: Self.integrationTimeout) } catch { return }
      integrationTimedOut = true
    }
  }

  /// `promptGeneration > 0` significa que llegó al menos una marca A autenticada.
  private var bannerCause: IntegrationBannerView.Cause? {
    guard !bannerDismissed else { return nil }
    if !integrationAvailable { return .unsupportedShell }
    return integrationTimedOut && tracker.promptGeneration == 0 ? .noPromptMark : nil
  }

  private var showsEmptyState: Bool {
    EmptyStateVisibility.shouldShow(
      hasRunFirstCommand: firstCommand.isSet, promptGeneration: tracker.promptGeneration,
      bannerVisible: bannerCause != nil)
  }
}
