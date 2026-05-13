import SwiftUI

/// Shown on app launch when no project history exists.
/// Offers the user a choice between templates or a blank document.
struct WelcomeView: View {
    var onBlankDocument: () -> Void
    var onSelectTemplate: () -> Void
    var onOpenFile: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            // App icon and title
            VStack(spacing: 12) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("myleaf")
                    .font(.largeTitle.bold())

                Text("LaTeX Editor")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(width: 200)

            // Action buttons
            VStack(spacing: 16) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 24) {
                    welcomeCard(
                        icon: "doc.text",
                        title: "Blank Document",
                        subtitle: "Start with a basic template",
                        action: onBlankDocument
                    )

                    welcomeCard(
                        icon: "rectangle.grid.2x2",
                        title: "Choose Template",
                        subtitle: "Conference, journal, or thesis",
                        action: onSelectTemplate
                    )

                    welcomeCard(
                        icon: "folder",
                        title: "Open File",
                        subtitle: "Open an existing .tex file",
                        action: onOpenFile
                    )
                }
            }
        }
        .padding(48)
        .frame(minWidth: 700, minHeight: 400)
    }

    private func welcomeCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
                    .frame(height: 44)

                Text(title)
                    .font(.body.bold())
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 160, height: 140)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
