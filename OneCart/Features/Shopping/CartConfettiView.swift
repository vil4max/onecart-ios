import SwiftUI

struct ConfettiParticle: Identifiable {
    let id: Int
    let color: Color
    let width: CGFloat
    let height: CGFloat
    let isCircle: Bool
    let startX: CGFloat
    let startY: CGFloat
    let speed: CGFloat
    let swayFrequency: Double
    let swayAmplitude: CGFloat
    let swayPhase: Double
    let rotationSpeed: Double
    let flipSpeed: Double
    let delay: Double
}

struct CartConfettiView: View {
    let trigger: Int

    @State private var particles: [ConfettiParticle] = []
    @State private var isAnimating: Bool = false
    @State private var startDate: Date = .now
    @State private var stopTask: Task<Void, Never>?
    @State private var containerWidth: CGFloat = 390

    private static let palette: [Color] = [
        OneCartPalette.primary,
        OneCartPalette.primaryAccent,
        Color(red: 0.98, green: 0.75, blue: 0.18), // gold
        Color(red: 0.32, green: 0.82, blue: 0.58), // mint
        Color(red: 0.98, green: 0.42, blue: 0.46), // soft coral
        Color(red: 0.38, green: 0.68, blue: 0.98), // sky blue
        Color(red: 0.76, green: 0.48, blue: 0.95), // lavender
    ]

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height

            Group {
                if isAnimating, !particles.isEmpty {
                    TimelineView(.animation(paused: !isAnimating)) { timeline in
                        let elapsed = timeline.date.timeIntervalSince(startDate)

                        ZStack {
                            ForEach(particles) { particle in
                                let dt = elapsed - particle.delay

                                if dt > 0 {
                                    let currentY = particle.startY + particle.speed * CGFloat(dt)
                                    let currentX = particle
                                        .startX + CGFloat(sin(dt * particle.swayFrequency + particle.swayPhase)) *
                                        particle.swayAmplitude
                                    let fadeThreshold = max(100, screenHeight - 140)
                                    let opacity: Double = currentY < fadeThreshold
                                        ? 1.0
                                        : max(0.0, Double(1.0 - (currentY - fadeThreshold) / 140.0))

                                    Group {
                                        if particle.isCircle {
                                            Circle()
                                                .fill(particle.color)
                                        } else {
                                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                                .fill(particle.color)
                                        }
                                    }
                                    .frame(width: particle.width, height: particle.height)
                                    .rotationEffect(.degrees(dt * particle.rotationSpeed))
                                    .rotation3DEffect(.degrees(dt * particle.flipSpeed), axis: (x: 1, y: 0.3, z: 0))
                                    .opacity(opacity)
                                    .position(x: currentX, y: currentY)
                                }
                            }
                        }
                        .frame(width: screenWidth, height: screenHeight)
                    }
                }
            }
            .onAppear {
                containerWidth = screenWidth
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                containerWidth = newWidth
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onChange(of: trigger) { _, newTrigger in
            guard newTrigger > 0 else { return }
            fireConfetti(width: containerWidth)
        }
    }

    private func fireConfetti(width: CGFloat) {
        stopTask?.cancel()

        var newParticles: [ConfettiParticle] = []
        let count = 56
        let boundsWidth: CGFloat = max(320, width)

        for index in 0 ..< count {
            let color = Self.palette[index % Self.palette.count]
            let isCircle = index.isMultiple(of: 4)
            let width = CGFloat.random(in: 7 ... 11)
            let height = isCircle ? width : CGFloat.random(in: 12 ... 20)

            let startX = CGFloat.random(in: 16 ... max(32, boundsWidth - 16))
            let startY = CGFloat.random(in: -70 ... -15)
            let speed = CGFloat.random(in: 270 ... 430)
            let swayFrequency = Double.random(in: 2.2 ... 4.5)
            let swayAmplitude = CGFloat.random(in: 16 ... 36)
            let swayPhase = Double.random(in: 0 ... (.pi * 2))
            let rotationSpeed = Double.random(in: -280 ... 280)
            let flipSpeed = Double.random(in: 360 ... 900)
            let delay = Double.random(in: 0.0 ... 0.45)

            newParticles.append(
                ConfettiParticle(
                    id: index,
                    color: color,
                    width: width,
                    height: height,
                    isCircle: isCircle,
                    startX: startX,
                    startY: startY,
                    speed: speed,
                    swayFrequency: swayFrequency,
                    swayAmplitude: swayAmplitude,
                    swayPhase: swayPhase,
                    rotationSpeed: rotationSpeed,
                    flipSpeed: flipSpeed,
                    delay: delay
                )
            )
        }

        particles = newParticles
        startDate = .now
        isAnimating = true

        stopTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_800_000_000)
            if !Task.isCancelled {
                isAnimating = false
                particles.removeAll()
            }
        }
    }
}
