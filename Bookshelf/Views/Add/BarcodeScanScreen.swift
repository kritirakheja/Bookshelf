import SwiftUI

/// The full-screen barcode scanner: the camera, a viewfinder with a sweeping laser
/// line, and a short "got it" moment (green flash, tick, the ISBN) before handing
/// the code on.
struct BarcodeScanScreen: View {
    let onISBN: (String) -> Void
    let onCancel: () -> Void

    @State private var found: String?

    var body: some View {
        ZStack {
            camera
                .ignoresSafeArea()
            ScanViewfinder(found: found)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            Button("Cancel", action: onCancel)
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.25))
                .padding()
        }
        .statusBarHidden()
    }

    @ViewBuilder
    private var camera: some View {
        if ScannerView.isAvailable {
            ScannerView { isbn in caught(isbn) }
        } else {
            // The simulator has no camera: a stand-in so the viewfinder can be seen.
            LinearGradient(colors: [Color(white: 0.25), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
                #if DEBUG
                .task {
                    if UserDefaults.standard.bool(forKey: "previewScanFound") {
                        try? await Task.sleep(for: .seconds(1.5))
                        caught("9780141439518")
                    }
                }
                #endif
        }
    }

    private func caught(_ isbn: String) {
        guard found == nil else { return }
        withAnimation(.spring(duration: 0.35, bounce: 0.45)) { found = isbn }
        Task {
            // Long enough to see the tick and the number, short enough not to wait.
            try? await Task.sleep(for: .milliseconds(850))
            onISBN(isbn)
        }
    }
}

/// Dims everything but a barcode-shaped window, with corner brackets and a laser
/// line sweeping through it; turns green when a code is caught.
struct ScanViewfinder: View {
    let found: String?

    private let window = CGSize(width: 290, height: 160)
    @State private var sweepDown = false
    @State private var hintPulse = false

    private var accent: Color { found == nil ? .white : .green }

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(x: (proxy.size.width - window.width) / 2,
                              y: proxy.size.height * 0.42 - window.height / 2,
                              width: window.width, height: window.height)
            ZStack {
                // The dimmed surround, with the window cut out.
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: proxy.size))
                    path.addRoundedRect(in: rect, cornerSize: CGSize(width: 18, height: 18))
                }
                .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))

                // Green flash inside the window once caught.
                RoundedRectangle(cornerRadius: 18)
                    .fill(.green.opacity(found == nil ? 0 : 0.18))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                CornerBrackets()
                    .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .frame(width: rect.width, height: rect.height)
                    .scaleEffect(found == nil ? 1 : 1.07)
                    .shadow(color: accent.opacity(0.6), radius: found == nil ? 0 : 10)
                    .position(x: rect.midX, y: rect.midY)

                if found == nil {
                    laser
                        .frame(width: rect.width - 36)
                        .position(x: rect.midX, y: rect.midY + (sweepDown ? 1 : -1) * (rect.height / 2 - 18))
                        .transition(.opacity)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 54, weight: .bold))
                        .foregroundStyle(.white, .green)
                        .shadow(radius: 6)
                        .position(x: rect.midX, y: rect.midY)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }

                caption
                    .frame(width: proxy.size.width - 40)
                    .position(x: rect.midX, y: rect.maxY + 56)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { sweepDown = true }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { hintPulse = true }
        }
    }

    /// A glowing red line, brightest in the middle.
    private var laser: some View {
        Capsule()
            .fill(LinearGradient(colors: [.red.opacity(0), .red, .red, .red.opacity(0)], startPoint: .leading, endPoint: .trailing))
            .frame(height: 3)
            .shadow(color: .red, radius: 6)
            .shadow(color: .red.opacity(0.6), radius: 14)
    }

    @ViewBuilder
    private var caption: some View {
        if let found {
            VStack(spacing: 6) {
                Text("Got it")
                    .font(.inter(.headline))
                Text(found)
                    .font(.inter(.title3).monospacedDigit().weight(.semibold))
                    .tracking(2)
            }
            .foregroundStyle(.white)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "barcode.viewfinder")
                    .font(.inter(.title2))
                Text("Point at the barcode on the back cover")
                    .font(.inter(.subheadline, .medium))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .opacity(hintPulse ? 1 : 0.6)
        }
    }
}

/// Four L-shaped corners of a rounded rectangle.
struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let arm: CGFloat = 30
        let r: CGFloat = 18
        var path = Path()
        // Top left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
        // Top right
        path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
        // Bottom right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
        // Bottom left
        path.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
        return path
    }
}
