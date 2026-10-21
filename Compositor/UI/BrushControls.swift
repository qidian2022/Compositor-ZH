import SwiftUI

struct BrushControls: View {
    @Bindable var session: EditorSession
    var body: some View {
        HStack(spacing: 12) {
            Text(zh(session.tool == .spotHealing ? "Spot Healing" : session.tool == .cloneStamp ? "Clone Stamp" : session.tool == .blur ? "Smear" : session.brushMode == .erase ? "Eraser" : "Brush")).font(ToolHeaderStyle.titleFont)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    if session.tool == .brush {
                        Picker(zh("Mode"), selection: $session.brushMode) {
                            ForEach(BrushToolMode.allCases, id: \.self) { Text(zh($0.rawValue)).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                        .help(zh("Paint with the foreground color (B), or erase pixels away (E)"))
                    }
                    if session.tool == .blur {
                        Picker(zh("Mode"), selection: $session.blurMode) {
                            ForEach(BlurToolMode.allCases, id: \.self) { Text(zh($0.rawValue)).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                        .help(zh("Liquify pushes pixels · Blur softens · Smudge drags color along"))
                    }
                    if session.tool == .spotHealing {
                        Picker(zh("Type"), selection: $session.spotHealingMode) {
                            ForEach(SpotHealingMode.allCases, id: \.self) { Text(zh($0.rawValue)).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                        .accessibilityIdentifier("spotHealingType")
                    }
                    if session.tool == .cloneStamp {
                        Toggle(zh("Aligned"), isOn: $session.cloneSettings.aligned)
                            .help(zh("Keep the source moving with the brush between strokes; off starts every stroke at the source point"))
                        Picker(zh("Sample"), selection: $session.cloneSettings.sampleAllLayers) {
                            Text(zh("This Layer")).tag(false)
                            Text(zh("All Layers")).tag(true)
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                        .help(zh("Copy from the active layer only, or from every visible layer as shown"))
                    }
                    Text(zh("Size")).scrubbable(sensitivity: 1.0, value: $session.brushSettings.diameter, range: 1...2000)
                    TextField(zh("Size"), value: Binding<Double>(get: { Double(session.brushSettings.diameter) },
                                                             set: { session.brushSettings.diameter = $0.isFinite ? CGFloat(min(2000, max(1, $0))) : 40 }),
                              format: .number.precision(.fractionLength(0)))
                    .frame(width: 48).textFieldStyle(.roundedBorder)
                    .arrowSteps(value: { Double(session.brushSettings.diameter) },
                                change: { session.brushSettings.diameter = CGFloat(min(2000, max(1, $0))) })
                    .onChange(of: session.brushSettings.diameter) { _, value in
                        session.brushSettings.diameter = value.isFinite ? min(2000, max(1, value)) : 40
                    }
                    .unitSuffix("px")
                    Text(zh("Hardness")).scrubbable(sensitivity: 0.01, value: $session.brushSettings.hardness, range: 0...1)
                    Slider(value: $session.brushSettings.hardness, in: 0...1).frame(width: 100)
                    TextField(zh("Hardness"), value: Binding<Double>(get: { Double(session.brushSettings.hardness * 100) },
                                                                 set: { session.brushSettings.hardness = $0.isFinite ? CGFloat(min(1, max(0, $0 / 100))) : 1 }),
                              format: .number.precision(.fractionLength(0)))
                    .frame(width: 42).textFieldStyle(.roundedBorder)
                    .arrowSteps(value: { Double(session.brushSettings.hardness * 100) },
                                change: { session.brushSettings.hardness = CGFloat(min(1, max(0, $0 / 100))) })
                    .unitSuffix("%")
                    Text(zh(session.tool == .blur ? "Strength" : "Opacity"))
                        .scrubbable(sensitivity: 0.01, value: $session.brushSettings.opacity, range: 0.01...1)
                    Slider(value: $session.brushSettings.opacity, in: 0.01...1).frame(width: 100)
                    TextField(zh("Opacity"), value: Binding<Double>(get: { Double(session.brushSettings.opacity * 100) },
                                                                set: { session.brushSettings.opacity = $0.isFinite ? CGFloat(min(100, max(1, $0)) / 100) : 1 }),
                              format: .number.precision(.fractionLength(0)))
                    .frame(width: 42).textFieldStyle(.roundedBorder)
                    .arrowSteps(value: { Double(session.brushSettings.opacity * 100) },
                                change: { session.brushSettings.opacity = CGFloat(min(100, max(1, $0)) / 100) })
                    .help(zh("Press 1–9 for 10–90%, 0 for 100%"))
                    .unitSuffix("%")
                    // Blur softens by a radius of its own, apart from how strongly it lays the softening down.
                    if session.tool == .blur, session.blurMode == .blur {
                        Text(zh("Radius")).scrubbable(sensitivity: 0.1, value: $session.brushSettings.blurRadius, range: 0.5...50)
                        // The slider covers everyday radii; typing or scrubbing reaches up to 50.
                        Slider(value: Binding(get: { min(20, session.brushSettings.blurRadius) },
                                              set: { session.brushSettings.blurRadius = $0 }), in: 0.5...20).frame(width: 100)
                        TextField(zh("Radius"), value: Binding<Double>(get: { Double(session.brushSettings.blurRadius) },
                                                                   set: { session.brushSettings.blurRadius = $0.isFinite ? CGFloat(min(50, max(0.5, $0))) : 5 }),
                                  format: .number.precision(.fractionLength(0...1)))
                        .frame(width: 42).textFieldStyle(.roundedBorder)
                        .arrowSteps(value: { Double(session.brushSettings.blurRadius) },
                                    change: { session.brushSettings.blurRadius = CGFloat(min(50, max(0.5, $0))) })
                        .help(zh("How far the blur softens, in pixels"))
                        .unitSuffix("px")
                    }
                    // Paint and Erase only: healing, cloning and smearing have their own feel.
                    if session.tool == .brush {
                        Text(zh("Smoothing"))
                            .scrubbable(sensitivity: 1, value: $session.brushSettings.smoothing, range: 0...100)
                        Slider(value: $session.brushSettings.smoothing, in: 0...100).frame(width: 100)
                        TextField(zh("Smoothing"), value: Binding<Double>(get: { Double(session.brushSettings.smoothing) },
                                                                      set: { session.brushSettings.smoothing = $0.isFinite ? CGFloat(min(100, max(0, $0))) : 0 }),
                                  format: .number.precision(.fractionLength(0)))
                        .frame(width: 42).textFieldStyle(.roundedBorder)
                        .arrowSteps(value: { Double(session.brushSettings.smoothing) },
                                    change: { session.brushSettings.smoothing = CGFloat(min(100, max(0, $0))) })
                        .help(zh("The brush trails the pointer on a string this long, so a shaky hand still draws a smooth line"))
                    }
                    if session.isMaskSelected {
                        Picker(zh("Paint"), selection: $session.maskPaintWhite) {
                            Text(zh("Black · Hide")).tag(false)
                            Text(zh("White · Reveal")).tag(true)
                        }.frame(width: 180)
                    } else if session.tool != .cloneStamp, session.tool != .blur {
                        // Same foreground color and Color Picker as the tool-rail swatch.
                        HStack(spacing: 6) {
                            Text(zh("Color"))
                            Button { session.openColorPicker(background: false) } label: {
                                let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
                                shape.fill(session.foregroundColor.swiftUI)
                                    .overlay { shape.inset(by: 1).strokeBorder(.white, lineWidth: 1) }
                                    .overlay { shape.strokeBorder(.black, lineWidth: 1) }
                                    .frame(width: 34, height: 18)
                                    .contentShape(shape)
                            }
                            .buttonStyle(.plain)
                            .disabled(!session.canEditPalette)
                            .help(zh("Foreground color"))
                            .accessibilityLabel(zh("Foreground color"))
                        }
                    }
                    Spacer(minLength: 0)
                    if session.tool == .cloneStamp, session.cloneSource == nil {
                        Text(zh("Option-click to set the source")).foregroundStyle(.secondary)
                    }
                    if session.isMaskSelected { Text(zh("Mask")).foregroundStyle(.secondary) }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 18).toolHeaderBar().releasesFocusOnCommit(session)
        .disabled(session.showsBusy)
    }
}

/// A rubber stamp for the tool rail (SF Symbols has none): round handle, neck, body, and pad.
struct CloneStampToolIcon: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            var stamp = Path()
            stamp.addEllipse(in: CGRect(x: w * 0.33, y: h * 0.02, width: w * 0.34, height: h * 0.30))
            stamp.addRect(CGRect(x: w * 0.43, y: h * 0.28, width: w * 0.14, height: h * 0.28))
            stamp.addRoundedRect(in: CGRect(x: w * 0.12, y: h * 0.54, width: w * 0.76, height: h * 0.22),
                                 cornerSize: CGSize(width: w * 0.08, height: w * 0.08))
            stamp.addRect(CGRect(x: w * 0.06, y: h * 0.82, width: w * 0.88, height: h * 0.12))
            context.fill(stamp, with: .foreground)
        }
        .accessibilityHidden(true)
    }
}
