//
//  GameContainerView.swift
//  Wofoking — Load Away
//
//  Drives a level through permission → face calibration → gameplay, with
//  win / retry / face-lost overlays. Pauses safely on backgrounding (NFR-8).
//  Renders the real front camera during play and the live BPM from the watch.
//  Landscape-only layout. Manual look-away control when face tracking is
//  unsupported (Simulator).
//

import SwiftUI

struct GameContainerView: View {
    let level: Level
    @Binding var path: [Route]

    @EnvironmentObject private var store: PersistenceStore
    @StateObject private var vm: GameVM
    @ObservedObject private var hr = HeartRateService.shared
    @Environment(\.scenePhase) private var scenePhase

    init(level: Level, path: Binding<[Route]>) {
        self.level = level
        self._path = path
        self._vm = StateObject(wrappedValue: GameVM(level: level))
    }

    private var loc: Localization { Localization(language: store.settings.language) }

    var body: some View {
        ZStack {
            LoadAwayBackground()
            // Real camera feed behind the gameplay HUD (PRD: real camera). Also
            // shown during the Face Scan screen so the detection reticle has the
            // live face to sit on.
            if (vm.phase == .playing || vm.phase == .calibrating) && !vm.isManual {
                CameraPreviewView(tracker: vm.gaze, showFaceMesh: store.settings.debugFaceMesh)
                    .ignoresSafeArea()
                Color.black.opacity(store.settings.debugFaceMesh ? 0.15 : 0.45)
                    .ignoresSafeArea()
            }
            content
        }
        .navigationBarBackButtonHidden(vm.phase == .playing)
        .onAppear { vm.begin() }
        .onDisappear { vm.teardown() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { vm.engine.resumeFromBackground() }
            else { vm.engine.pauseForBackground() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .permission:   permissionPrompt
        case .denied:       deniedView
        case .unsupported, .playing: gameplay
        case .calibrating:  FaceScanView(vm: vm, loc: loc) { vm.finishFaceScan() }
        case .storyline:    StorylineView(loc: loc) { vm.finishStoryline() }
        }
    }

    // MARK: Permission / errors

    private var permissionPrompt: some View {
        infoCard(title: loc.t(.cameraDeniedTitle), body: loc.t(.cameraDeniedBody)) {
            Button(loc.t(.grantCamera)) { vm.begin() }.buttonStyle(.borderedProminent)
        }
    }

    private var deniedView: some View {
        infoCard(title: loc.t(.cameraDeniedTitle), body: loc.t(.cameraDeniedBody)) {
            Button(loc.t(.openSettings)) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }.buttonStyle(.borderedProminent)
        }
    }

    // MARK: Gameplay (landscape)

    private var gameplay: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                livesView
                if vm.peekCount > 0 { peekShameView }
                Spacer()
                if vm.canGiveUp { giveUpButton }
                if store.settings.heartRateEnabled { bpmView }
            }

            if store.settings.debugFaceMesh { debugGazeBadge }

            Spacer()

            LoadingBar(progress: vm.progress, atWindow: vm.engineState == .reached100)
                .frame(maxWidth: 520)

            Text(vm.mockLine.isEmpty ? loc.t(.faceLookAway) : vm.mockLine)
                .font(.system(.title3, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .frame(minHeight: 44)
                .animation(.default, value: vm.mockLine)

            if vm.engineState == .faceLost {
                Text(loc.t(.faceLost)).foregroundStyle(.yellow).font(.headline)
            }

            Spacer()
            if vm.isManual { manualControl.frame(maxWidth: 420) }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
        .animation(.default, value: vm.canGiveUp)
        .overlay { overlays }
    }

    private var livesView: some View {
        Group {
            if let max = ConfigService.shared.rules(for: level).lives {
                HStack(spacing: 6) {
                    ForEach(0..<max, id: \.self) { i in
                        Image(systemName: i < vm.lives ? "heart.fill" : "heart")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    /// Shame counter: how many times the player was caught peeking.
    private var peekShameView: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                .foregroundStyle(.yellow)
            Text("\(vm.peekCount)")
                .font(.system(.headline, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            Text("peeks").font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .transition(.scale.combined(with: .opacity))
        .animation(.default, value: vm.peekCount)
    }

    /// Live heart-rate readout streamed from the Apple Watch.
    private var bpmView: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .foregroundStyle(hr.isElevated ? .red : .pink)
                .symbolEffect(.pulse, options: .repeating, isActive: hr.isStreaming)
            Text(hr.bpm.map { "\($0)" } ?? "—")
                .font(.system(.headline, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            Text("BPM").font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// Debug readout: live gaze state, colour-matched to the face mesh.
    private var debugGazeBadge: some View {
        let (label, color): (String, Color) = {
            switch vm.gazeState {
            case .lookingAway:     return ("LOOKING AWAY · loading", .green)
            case .eyesClosed:      return ("EYES CLOSED · loading", .green)
            case .lookingAtScreen: return ("LOOKING AT SCREEN · paused", .red)
            case .faceLost:        return ("FACE LOST", .orange)
            case .noFace:          return ("NO FACE", .gray)
            }
        }()
        return HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.white)
            // Live guard numbers: eye-ray-to-camera angle (peek when ≤ the
            // eyeOnScreenConeDeg gate while turned away) and last identity
            // shape err (imposter when > faceShapeToleranceRatio).
            Text(String(format: "yaw %+.0f° · eye %.0f° · id %.3f", vm.debugYawDeg, vm.debugConeDeg, vm.debugShapeErr))
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(.default, value: vm.gazeState)
    }

    /// Hidden until the player stares at the screen for `giveUpRevealSeconds`.
    private var giveUpButton: some View {
        Button { vm.giveUp() } label: {
            Label(loc.t(.giveUp), systemImage: "flag.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .transition(.opacity.combined(with: .scale))
    }

    /// Press-and-hold to look away (Simulator / unsupported devices).
    private var manualControl: some View {
        Text("Hold to Look Away")
            .font(.headline).foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(.ultraThinMaterial, in: Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in vm.manualLookAway(true) }
                    .onEnded { _ in vm.manualLookAway(false) })
    }

    // MARK: Win / Retry overlays

    @ViewBuilder
    private var overlays: some View {
        switch vm.engineState {
        case .levelCompleted, .win:
            resultOverlay(title: loc.t(.win)) {
                if let next = Level(rawValue: level.rawValue + 1), next.isPlayable,
                   store.isUnlocked(next) {
                    Button(next.title) { path = [.game(next)] }
                        .buttonStyle(.borderedProminent)
                }
                Button(loc.t(.continueGame)) { path.removeAll() }
                    .buttonStyle(.bordered)
            }
        case .retry:
            resultOverlay(title: vm.mockLine.isEmpty ? loc.t(.retry) : vm.mockLine) {
                Button(loc.t(.retry)) { vm.retry() }.buttonStyle(.borderedProminent)
                Button(loc.t(.back)) { path.removeAll() }.buttonStyle(.bordered)
            }
        case .gaveUp:
            resultOverlay(title: vm.mockLine.isEmpty ? loc.t(.giveUp) : vm.mockLine) {
                Button(loc.t(.mainMenu)) { path.removeAll() }.buttonStyle(.borderedProminent)
            }
            .task {
                // Let the mock land, then bounce to the main menu.
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                path.removeAll()
            }
        default:
            EmptyView()
        }
    }

    private func resultOverlay<Buttons: View>(title: String,
                                              @ViewBuilder buttons: () -> Buttons) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            HStack(spacing: 24) {
                Text(title)
                    .font(.title.bold()).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                VStack(spacing: 14) { buttons() }
            }.padding(32)
        }
    }

    private func infoCard<Action: View>(title: String, body: String,
                                        @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 16) {
            Text(title).font(.title2.bold()).foregroundStyle(.white)
            Text(body).font(.callout).multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
            action()
        }
        .padding(28)
        .frame(maxWidth: 600)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
