import SwiftUI
import AppKit

/// QR code + channel name for phone notifications (Settings › Push, simple mode).
/// Thin view: everything it shows comes from `PhonePush`.
struct PhonePushQRBlock: View {
    let topic: String
    let onNewCode: () -> Void

    @State private var confirmNewCode = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if let image = QRCodeImage.image(for: PhonePush.setupURL(topic), side: 320) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .padding(8)
                    .background(Color.white)
                    .cornerRadius(8)
                    .accessibilityLabel("QR code to set up phone notifications")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Scan this code with your phone's camera.")
                Text("2. Follow the two steps on the page that opens.")
                Text("Your channel")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                Text(topic)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button(copied ? "Copied" : "Copy name") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(topic, forType: .string)
                        copied = true
                    }
                    Button("New code…") { confirmNewCode = true }
                }
                Text("No scanner? Install the ntfy app and subscribe to this channel name by hand.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(FCType.body)
        }
        .onChange(of: topic) { _ in copied = false }
        .alert("Make a new code?", isPresented: $confirmNewCode) {
            Button("New code", role: .destructive) { onNewCode() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Phones that scanned the current code stop receiving notifications until they scan the new one.")
        }
    }
}
