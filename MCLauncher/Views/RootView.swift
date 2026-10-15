import SwiftUI

/// Top-level tab container.
struct RootView: View {
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        TabView {
            LaunchView()
                .tabItem { Label("Play", systemImage: "play.fill") }

            InstancesView()
                .tabItem { Label("Instances", systemImage: "square.stack.3d.up.fill") }

            FilesView()
                .tabItem { Label("Files", systemImage: "folder") }

            AccountsView()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.green)
        .overlay(alignment: .bottom) {
            if let banner = model.banner {
                BannerView(text: banner) { model.banner = nil }
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.banner)
    }
}

/// Small transient message bar.
struct BannerView: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
            Text(text).font(.footnote).lineLimit(3)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.1)))
        .padding(.horizontal, 16)
        .shadow(radius: 8)
    }
}

/// A reusable section card used across screens.
struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
