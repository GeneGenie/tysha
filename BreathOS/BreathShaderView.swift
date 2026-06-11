import SwiftUI

/// Full-screen Metal-shader background. `TimelineView(.animation)` drives a redraw
/// every frame; the uniforms come from the engine's published state.
struct BreathShaderView: View {
    let engine: BreathEngine

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.animation) { _ in
                Rectangle()
                    .fill(.black)
                    .colorEffect(
                        ShaderLibrary.breathBackground(
                            .float(Float(engine.shaderTime)),
                            .float(Float(engine.shaderPhase)),
                            .float(Float(engine.shaderPrevPhase)),
                            .float(Float(engine.phaseProgress)),
                            .float(Float(engine.transition)),
                            .float2(Float(size.width), Float(size.height))
                        )
                    )
            }
        }
        .ignoresSafeArea()
    }
}
