import SwiftUI
import UIKit
import Observation

/// Finishing a book: marks it read and throws confetti over whatever screen is showing.
@MainActor
@Observable
final class Celebration {
    static let shared = Celebration()
    /// Goes up by one for every burst; the overlay watches it.
    private(set) var bursts = 0

    /// Marks the book as read and celebrates, unless it was read already.
    func finish(_ book: Book) {
        guard book.status != .read else { return }
        withAnimation { book.setStatus(.read) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // A beat, so a sheet that's closing is out of the way first.
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            bursts += 1
        }
    }
}

extension View {
    /// Confetti over this view each time a book is finished. Touches pass through.
    func celebratesFinishedBooks() -> some View {
        overlay { ConfettiOverlay() }
    }
}

/// Its own view, so it redraws when a burst is fired wherever it's placed.
private struct ConfettiOverlay: View {
    var body: some View {
        ConfettiView(bursts: Celebration.shared.bursts)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Paper confetti falling from the top of the screen for a couple of seconds.
/// Nothing is shown with Reduce Motion on.
private struct ConfettiView: UIViewRepresentable {
    let bursts: Int

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        context.coordinator.seen = bursts
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard bursts != context.coordinator.seen else { return }
        context.coordinator.seen = bursts
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        Self.burst(in: view)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var seen = 0
    }

    private static let colors: [UIColor] = [
        UIColor(red: 0.10, green: 0.35, blue: 0.26, alpha: 1), UIColor(red: 0.46, green: 0.78, blue: 0.62, alpha: 1),
        .systemYellow, .systemOrange, .systemPink, .systemTeal, .systemIndigo,
    ]

    private static func burst(in view: UIView) {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.emitterPosition = CGPoint(x: view.bounds.midX, y: -12)
        emitter.emitterSize = CGSize(width: view.bounds.width, height: 1)
        emitter.beginTime = CACurrentMediaTime()
        emitter.emitterCells = colors.flatMap { color in
            [piece(color, size: CGSize(width: 9, height: 5)), piece(color, size: CGSize(width: 6, height: 6), round: true)]
        }
        view.layer.addSublayer(emitter)
        // Pour for a moment, let the last pieces fall, then tidy up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { emitter.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) { emitter.removeFromSuperlayer() }
    }

    private static func piece(_ color: UIColor, size: CGSize, round: Bool = false) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            let rect = CGRect(origin: .zero, size: size)
            if round { context.cgContext.fillEllipse(in: rect) } else { context.fill(rect) }
        }.cgImage
        cell.birthRate = 9
        cell.lifetime = 5
        cell.velocity = 260
        cell.velocityRange = 120
        cell.emissionLongitude = .pi          // downwards
        cell.emissionRange = .pi / 5
        cell.yAcceleration = 180
        cell.spin = 3
        cell.spinRange = 5
        cell.scale = 1
        cell.scaleRange = 0.4
        cell.alphaSpeed = -0.18
        return cell
    }
}
