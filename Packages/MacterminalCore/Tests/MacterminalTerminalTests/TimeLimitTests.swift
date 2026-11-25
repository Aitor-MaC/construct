import Testing

@testable import MacterminalTerminal

/// Una operación que ignora la cancelación: solo termina cuando el test la suelta, como un
/// `flush()` síncrono atascado en un disco lento.
private struct StuckOperation: Sendable {
  let stream: AsyncStream<Void>
  let continuation: AsyncStream<Void>.Continuation
  init() { (stream, continuation) = AsyncStream<Void>.makeStream() }
  /// La espera va en una `Task` desacoplada: cancelar a quien la espera no la cancela, así que
  /// `run()` solo vuelve con `release()`, igual que una escritura síncrona.
  func run() async {
    let stream = stream
    await Task { for await _ in stream { return } }.value
  }
  func release() { continuation.finish() }
}

@Suite(.timeLimit(.minutes(1))) struct TimeLimitTests {
  @Test func theLimitWinsOverAnOperationThatIgnoresCancellation() async {
    let stuck = StuckOperation()
    // Si `TimeLimit` esperase a la operación, volvería al soltarla, a los 2 s.
    let release = Task {
      try await Task.sleep(for: .seconds(2))
      stuck.release()
    }
    let clock = ContinuousClock()
    let start = clock.now
    let result = await TimeLimit.run(
      limit: .seconds(1), sleep: { _ in },
      operation: {
        await stuck.run()
        return "guardado"
      },
      onTimeout: { "tiempo agotado" })
    let elapsed = clock.now - start
    #expect(result == "tiempo agotado")
    #expect(elapsed < .seconds(1))
    release.cancel()
    stuck.release()
  }

  @Test func aFastOperationWinsAndTheTimerIsCancelled() async {
    let result = await TimeLimit.run(
      limit: .seconds(1),
      sleep: { _ in
        // Reloj que no avanza: solo sale si lo cancelan.
        try await Task.sleep(for: .seconds(3600))
      },
      operation: { "guardado" }, onTimeout: { "tiempo agotado" })
    #expect(result == "guardado")
  }

  @Test func cancellingTheCallerCancelsTheOperation() async {
    let task = Task {
      await TimeLimit.run(
        limit: .seconds(1), sleep: { _ in try await Task.sleep(for: .seconds(3600)) },
        operation: {
          do {
            try await Task.sleep(for: .seconds(3600))
            return "guardado"
          } catch {
            return "cancelado"
          }
        }, onTimeout: { "tiempo agotado" })
    }
    task.cancel()
    #expect(await task.value == "cancelado")
  }
}
