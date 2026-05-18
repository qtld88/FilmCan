import SwiftUI

struct FanOutProgressBar: View {
    let copyFraction: Double   // 0...1
    let verifyFraction: Double // 0...1
    let status: DestStatus

    private var safeCopy: Double { min(max(copyFraction, 0), 1) }
    private var safeVerify: Double { min(max(verifyFraction, 0), safeCopy) }

    private var copyColor: Color {
        switch status {
        case .active:    return FilmCanTheme.brandYellow
        case .complete:  return FilmCanTheme.brandGreen
        case .failed:    return FilmCanTheme.brandRed
        case .pending:   return Color.gray.opacity(0.4)
        }
    }

    private var verifyColor: Color {
        switch status {
        case .active:   return FilmCanTheme.brandGreen.opacity(0.85)
        case .complete: return FilmCanTheme.brandGreen
        case .failed:   return FilmCanTheme.brandRed
        case .pending:  return .clear
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.controlBackgroundColor).opacity(0.4))
                    .frame(height: 8)
                // Copy fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(copyColor)
                    .frame(width: geo.size.width * safeCopy, height: 8)
                    .animation(.easeOut(duration: 0.25), value: safeCopy)
                // Verify fill (drawn on top)
                RoundedRectangle(cornerRadius: 4)
                    .fill(verifyColor)
                    .frame(width: geo.size.width * safeVerify, height: 8)
                    .animation(.easeOut(duration: 0.25), value: safeVerify)
            }
        }
        .frame(height: 8)
    }
}

#Preview {
    VStack(spacing: 16) {
        FanOutProgressBar(copyFraction: 0.7, verifyFraction: 0.4, status: .active)
        FanOutProgressBar(copyFraction: 1.0, verifyFraction: 1.0, status: .complete)
        FanOutProgressBar(copyFraction: 0.4, verifyFraction: 0, status: .failed(.verify))
        FanOutProgressBar(copyFraction: 0, verifyFraction: 0, status: .pending)
    }
    .padding()
    .frame(width: 300)
    .background(Color.black)
}
