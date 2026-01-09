import SwiftUI
import AppKit

/// A sidebar gallery showing recent captures with thumbnails.
/// Allows users to quickly switch between recent screenshots or open them.
struct RecentCapturesGallery: View {
    @ObservedObject var store: RecentCapturesStore
    let onSelect: (RecentCapture) -> Void
    let onReveal: (RecentCapture) -> Void
    let onDelete: (RecentCapture) -> Void

    @State private var hoveredID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Recent", systemImage: "clock")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.captures.isEmpty {
                    Button {
                        store.clear()
                    } label: {
                        Text("Clear")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if store.captures.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No recent captures")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Capture list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.captures) { capture in
                            CaptureCard(
                                capture: capture,
                                isHovered: hoveredID == capture.id,
                                onSelect: { onSelect(capture) },
                                onReveal: { onReveal(capture) },
                                onDelete: { onDelete(capture) }
                            )
                            .onHover { isHovered in
                                hoveredID = isHovered ? capture.id : nil
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 180)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
}

// MARK: - Capture Card

/// A single capture card in the gallery showing thumbnail and metadata.
private struct CaptureCard: View {
    let capture: RecentCapture
    let isHovered: Bool
    let onSelect: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail
            ZStack {
                if let thumbnailData = capture.thumbnailData,
                   let nsImage = NSImage(data: thumbnailData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 90)
                        .clipped()
                } else {
                    // Placeholder
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 90)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                        }
                }

                // Hover overlay with actions
                if isHovered {
                    Color.black.opacity(0.4)
                        .overlay {
                            HStack(spacing: 12) {
                                Button {
                                    onReveal()
                                } label: {
                                    Image(systemName: "folder")
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white)
                                .help("Show in Finder")

                                Button {
                                    onDelete()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white)
                                .help("Remove from recent")
                            }
                        }
                }

                // File exists indicator
                if !capture.fileExists {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption)
                                .padding(4)
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Metadata
            VStack(alignment: .leading, spacing: 2) {
                Text(capture.filename)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(capture.captureDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - Gallery Toggle Button

/// Button to toggle the gallery sidebar visibility.
struct GalleryToggleButton: View {
    @Binding var isShowingGallery: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isShowingGallery.toggle()
            }
        } label: {
            Image(systemName: isShowingGallery ? "sidebar.left" : "sidebar.left")
                .symbolVariant(isShowingGallery ? .none : .none)
        }
        .buttonStyle(.accessoryBar)
        .background(
            isShowingGallery
                ? Color.accentColor.opacity(0.2)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .help(isShowingGallery ? "Hide Recent Captures" : "Show Recent Captures")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Gallery with captures") {
    let store = RecentCapturesStore()
    return RecentCapturesGallery(
        store: store,
        onSelect: { _ in },
        onReveal: { _ in },
        onDelete: { _ in }
    )
    .frame(height: 400)
}

#Preview("Empty gallery") {
    let store = RecentCapturesStore()
    return RecentCapturesGallery(
        store: store,
        onSelect: { _ in },
        onReveal: { _ in },
        onDelete: { _ in }
    )
    .frame(height: 400)
}
#endif
