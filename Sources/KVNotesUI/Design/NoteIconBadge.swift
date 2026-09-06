import KVNotesCore
import SwiftUI

struct NoteIconBadge: View {
    let icon: String
    let theme: NoteTheme
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let parsed = NoteIcon.parse(icon) {
                switch parsed {
                case .emoji(let emoji):
                    Text(verbatim: emoji)
                        .font(.system(size: size * 0.54))
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: size * 0.46, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                }
            } else {
                Text(verbatim: icon)
                    .font(.system(size: size * 0.54))
            }
        }
        .frame(width: size, height: size)
        .background(theme.elevatedCard, in: Circle())
        .overlay {
            Circle().strokeBorder(theme.separator, lineWidth: 0.75)
        }
    }
}

#Preview {
    HStack {
        NoteIconBadge(icon: "🔑", theme: .preview)
        NoteIconBadge(icon: "sf:lock.fill", theme: .preview)
    }
    .padding()
    .background(NoteTheme.preview.background)
}
