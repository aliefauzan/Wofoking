//
//  CameraPreviewView.swift
//  Wofoking — Load Away
//
//  Renders the real front-camera feed from the live ARKit face-tracking
//  session as the gameplay background. No-op on devices without ARKit face
//  tracking (Simulator), where the scenery background shows instead.
//

import SwiftUI
import Combine
#if canImport(ARKit)
import ARKit
import SceneKit
#endif

struct CameraPreviewView: UIViewRepresentable {
    let tracker: GazeTracker
    /// Debug: overlay the live ARKit face mesh on the player's face.
    var showFaceMesh = false

    #if canImport(ARKit)
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = tracker.arSession      // share the tracker's running session
        view.automaticallyUpdatesLighting = true
        view.rendersContinuously = true
        view.isUserInteractionEnabled = false
        context.coordinator.showFaceMesh = showFaceMesh
        context.coordinator.attach(view, tracker: tracker)
        tracker.meshEnabled = showFaceMesh
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.showFaceMesh = showFaceMesh
        tracker.meshEnabled = showFaceMesh
        context.coordinator.refreshVisibility()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Renders the debug face mesh from `GazeTracker`'s Sendable frame stream
    /// (the tracker owns `session.delegate`, so ARSCNView never sees anchors).
    /// Colours the wireframe by live gaze state as the look-away indicator.
    final class Coordinator: NSObject {
        var showFaceMesh = false

        private weak var view: ARSCNView?
        private var faceNode: SCNNode?
        private var gaze: GazeState = .noFace
        private var bag = Set<AnyCancellable>()
        private let meshMaterial: SCNMaterial = {
            let m = SCNMaterial()
            m.fillMode = .lines
            m.isDoubleSided = true
            m.lightingModel = .constant
            return m
        }()

        func attach(_ view: ARSCNView, tracker: GazeTracker) {
            self.view = view
            guard bag.isEmpty else { return }   // subscribe once
            tracker.meshFrame
                .receive(on: DispatchQueue.main)
                .sink { [weak self] frame in self?.render(frame) }
                .store(in: &bag)
            tracker.$gaze
                .receive(on: DispatchQueue.main)
                .sink { [weak self] g in self?.gaze = g; self?.applyColor() }
                .store(in: &bag)
        }

        func refreshVisibility() { faceNode?.isHidden = !showFaceMesh }

        private func render(_ frame: FaceMeshFrame) {
            guard showFaceMesh, let view else { faceNode?.isHidden = true; return }
            let node = faceNode ?? makeNode(in: view)
            node.isHidden = false
            let geo = Self.geometry(from: frame)
            geo.materials = [meshMaterial]
            node.geometry = geo
            applyColor()
            node.simdTransform = frame.transform
        }

        private func makeNode(in view: ARSCNView) -> SCNNode {
            let n = SCNNode()
            view.scene.rootNode.addChildNode(n)
            faceNode = n
            return n
        }

        private func applyColor() {
            meshMaterial.diffuse.contents = Self.color(for: gaze)
        }

        private static func color(for g: GazeState) -> UIColor {
            switch g {
            case .lookingAway:     return .systemGreen   // loading (good)
            case .eyesClosed:      return .systemGreen   // loading (eyes shut)
            case .lookingAtScreen: return .systemRed     // paused
            case .faceLost:        return .systemOrange
            case .noFace:          return .systemGray
            }
        }

        private static func geometry(from frame: FaceMeshFrame) -> SCNGeometry {
            let verts = frame.vertices.map { SCNVector3($0.x, $0.y, $0.z) }
            let source = SCNGeometrySource(vertices: verts)
            let element = SCNGeometryElement(indices: frame.triangleIndices,
                                             primitiveType: .triangles)
            return SCNGeometry(sources: [source], elements: [element])
        }
    }
    #else
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ uiView: UIView, context: Context) {}
    #endif
}
