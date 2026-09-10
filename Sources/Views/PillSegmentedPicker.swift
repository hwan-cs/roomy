import SwiftUI

struct PillSegmentedPicker<Value: Hashable, Content: View>: View {
    @Binding var selection: Value
    let options: [Value]
    var tint: Color = .accentColor
    @ViewBuilder var label: (Value) -> Content

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    label(option)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            selection == option ? tint : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .foregroundStyle(selection == option ? Color.white : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
    }
}
