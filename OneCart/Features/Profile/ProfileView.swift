import SwiftUI

struct ProfileAvatarView: View {
    let name: String
    var remoteURL: String?
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let remoteURL, let url = URL(string: remoteURL), url.scheme == "https" {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(remote):
                        remote
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        initialsView
                            .overlay(ProgressView().scaleEffect(0.7))
                    case .failure:
                        initialsView
                    @unknown default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(name)
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OneCartPalette.primary)
    }

    private var initials: String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let value = words.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "?" : value.uppercased()
    }
}
