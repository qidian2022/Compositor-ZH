import SwiftUI

struct TrimSheet: View {
    let finish: (TrimOptions?) -> Void
    @State private var basedOn: TrimBasedOn = .transparentPixels
    @State private var trimTop: Bool = true
    @State private var trimBottom: Bool = true
    @State private var trimLeft: Bool = true
    @State private var trimRight: Bool = true

    var body: some View { sheet.roundedControls() }

    @ViewBuilder private var sheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(zh("Trim")).font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text(zh("Based On")).font(.headline)
                Picker(zh(""), selection: $basedOn) {
                    ForEach(TrimBasedOn.allCases) { option in
                        Text(zh(option.rawValue)).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(zh("Trim Away")).font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Toggle(zh("Top"), isOn: $trimTop)
                        Toggle(zh("Bottom"), isOn: $trimBottom)
                    }
                    GridRow {
                        Toggle(zh("Left"), isOn: $trimLeft)
                        Toggle(zh("Right"), isOn: $trimRight)
                    }
                }
            }

            Divider()

            HStack {
                Button(zh("Cancel")) { finish(nil) }
                    .configuredNativeShortcut(.escape)
                Spacer()
                Button(zh("OK")) {
                    let options = TrimOptions(
                        basedOn: basedOn,
                        top: trimTop,
                        bottom: trimBottom,
                        left: trimLeft,
                        right: trimRight
                    )
                    finish(options)
                }
                .configuredNativeShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!trimTop && !trimBottom && !trimLeft && !trimRight)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}
