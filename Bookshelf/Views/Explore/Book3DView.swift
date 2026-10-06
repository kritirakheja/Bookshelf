import SwiftUI
import SceneKit

/// A real 3D book: front cover, back cover, spine and page edges on a solid block.
/// Tap to turn it over.
struct Book3DView: UIViewRepresentable {
    struct Faces: Equatable {
        var front: UIImage?
        var back: UIImage?
        var spine: UIImage?
    }

    let faces: Faces
    /// The book's thickness as a fraction of its width.
    let thickness: CGFloat
    let label: String
    let blurb: String?
    /// Extra height above and below the book's slot that the view also draws into.
    /// Mid-turn, the edge nearest you looms taller than the book at rest; without
    /// this room its top and bottom would be cut off.
    var overflow: CGFloat = 0

    /// How wide the book appears on screen, face-on, in a view of this size
    /// (so the covers can be drawn at the size they'll be seen).
    static func bookWidth(in size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 0 }
        return size.height / BookSceneView.visibleHeight(aspect: size.width / size.height)
    }

    func makeUIView(context: Context) -> BookSceneView {
        BookSceneView(thickness: thickness)
    }

    func updateUIView(_ view: BookSceneView, context: Context) {
        view.show(faces)
        view.overflow = overflow
        view.accessibilityLabel = label
        view.accessibilityValue = blurb
    }
}

final class BookSceneView: SCNView {
    /// A long lens: with a wide one, the edge that swings towards you mid-turn looms
    /// much taller than the book at rest. At this angle it stays within about 3%.
    private static let fieldOfView: CGFloat = 6
    /// Rest poses, in radians about the vertical axis: turned a little so the spine shows.
    private static let frontPose: Float = 0.30
    private static let backPose: Float = .pi - 0.10

    private let bookNode = SCNNode()
    private let cameraNode = SCNNode()
    private let shadowNode = SCNNode()
    private let box: SCNBox
    private var faces = Book3DView.Faces()
    private var yaw: Float = BookSceneView.frontPose
    private var hasTurnedOver = false
    /// Height at the top and bottom that is spare room for the turn, not part of
    /// the space the resting book is fitted to.
    var overflow: CGFloat = 0 {
        didSet { if overflow != oldValue { setNeedsLayout() } }
    }

    /// The height of the scene the camera must take in, in book-widths (the book is
    /// 1 wide and 1.5 tall), leaving a margin so a turning book stays in frame.
    static func visibleHeight(aspect: CGFloat) -> CGFloat {
        max(1.5 / heightFill, 1 / (widthFill * aspect))
    }

    /// How much of its slot's height and width the resting book may fill.
    private static let heightFill: CGFloat = 0.95
    private static let widthFill: CGFloat = 0.90

    init(thickness: CGFloat) {
        box = SCNBox(width: 1, height: 1.5, length: thickness, chamferRadius: 0.006)
        super.init(frame: .zero, options: nil)
        backgroundColor = .clear
        isOpaque = false
        antialiasingMode = .multisampling4X
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Double tap to turn the book over."

        let scene = SCNScene()
        self.scene = scene

        let camera = SCNCamera()
        camera.fieldOfView = Self.fieldOfView
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        // Mostly even light so covers keep their true colours, plus a little from
        // the upper left so the spine and page edges read as separate faces.
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 800
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 280
        key.eulerAngles = SCNVector3(-0.35, -0.45, 0)
        scene.rootNode.addChildNode(key)

        // A soft shadow on the "wall" behind the book.
        let shadow = SCNPlane(width: 1.7, height: 2.2)
        shadow.firstMaterial = Self.material(Self.shadowImage, lit: false)
        shadow.firstMaterial?.writesToDepthBuffer = false
        shadowNode.geometry = shadow
        shadowNode.position = SCNVector3(0, -0.05, Float(-thickness) - 0.2)
        shadowNode.renderingOrder = -1
        scene.rootNode.addChildNode(shadowNode)

        bookNode.geometry = box
        scene.rootNode.addChildNode(bookNode)
        applyMaterials()

        #if DEBUG
        if let held = PreviewArgs.flipAngle {
            yaw = held * .pi / 180
            hasTurnedOver = true
            shadowNode.isHidden = abs(sin(yaw)) > 0.35
        }
        #endif
        applyPose()

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let slotHeight = bounds.height - 2 * overflow
        guard bounds.width > 0, slotHeight > 0 else { return }
        // Fit the book to its slot, then widen the view to take in the spare room too.
        let visible = Self.visibleHeight(aspect: bounds.width / slotHeight) * bounds.height / slotHeight
        let distance = visible / (2 * tan(Self.fieldOfView * .pi / 360))
        cameraNode.position = SCNVector3(0, 0, Float(distance + box.length / 2))
    }

    func show(_ newFaces: Book3DView.Faces) {
        guard newFaces != faces else { return }
        let firstCovers = faces.back == nil && newFaces.back != nil
        faces = newFaces
        applyMaterials()
        // The first time the book is ready: a beat on the front, then turn it over.
        if firstCovers, !hasTurnedOver {
            hasTurnedOver = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.turn(to: Self.backPose)
            }
        }
    }

    override func accessibilityActivate() -> Bool {
        turnOver()
        return true
    }

    // MARK: Turning

    @objc private func tapped() { turnOver() }

    private func turnOver() {
        turn(to: cos(yaw) > 0 ? Self.backPose : Self.frontPose)
    }

    /// Turns to a pose by the shortest way round.
    private func turn(to pose: Float) {
        let turns = ((yaw - pose) / (2 * .pi)).rounded()
        yaw = pose + turns * 2 * .pi
        // The shadow is drawn for a book at rest, so it steps aside during the turn.
        if !UIAccessibility.isReduceMotionEnabled {
            shadowNode.runAction(.sequence([.fadeOut(duration: 0.12), .wait(duration: 0.5), .fadeIn(duration: 0.3)]))
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.75
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        applyPose()
        SCNTransaction.commit()
    }

    private func applyPose() {
        bookNode.eulerAngles = SCNVector3(0, yaw, 0)
    }

    // MARK: Faces

    private func applyMaterials() {
        let pagesSide = Self.material(Self.pagesImage(linesAlongHeight: true))
        let pagesTop = Self.material(Self.pagesImage(linesAlongHeight: false))
        // SCNBox order: front, right, back, left, top, bottom. Seen from the front,
        // the spine is on the left and the page edges on the right.
        box.materials = [
            Self.material(faces.front ?? UIColor.systemGray4),
            pagesSide,
            Self.material(faces.back ?? UIColor.systemGray4),
            Self.material(faces.spine ?? UIColor.systemGray3),
            pagesTop,
            pagesTop,
        ]
    }

    private static func material(_ contents: Any, lit: Bool = true) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = contents
        material.diffuse.mipFilter = .linear
        material.lightingModel = lit ? .lambert : .constant
        return material
    }

    /// The edge of a block of pages: off-white with fine lines.
    private static func pagesImage(linesAlongHeight: Bool) -> UIImage {
        let size = CGSize(width: 96, height: 96)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.96, green: 0.94, blue: 0.89, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.55, alpha: 0.35).setFill()
            for offset in stride(from: CGFloat(2), to: 96, by: 5) {
                context.fill(linesAlongHeight
                    ? CGRect(x: offset, y: 0, width: 1, height: size.height)
                    : CGRect(x: 0, y: offset, width: size.width, height: 1))
            }
        }
    }

    /// A blurred dark rectangle on a clear background.
    private static let shadowImage: UIImage = {
        let size = CGSize(width: 340, height: 440)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            // Draw the rectangle off-canvas and let only its shadow land in view.
            let rect = CGRect(x: 70 - 1000, y: 75, width: 200, height: 300)
            context.cgContext.setShadow(offset: CGSize(width: 1000, height: 0), blur: 34,
                                        color: UIColor.black.withAlphaComponent(0.16).cgColor)
            UIColor.black.setFill()
            context.fill(rect)
        }
    }()
}
