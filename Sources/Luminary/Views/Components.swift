import JellyfinKit
import SwiftUI

struct Shelf: View {
    let title: String
    let items: [BaseItemDto]
    let style: ItemCard.Style
    let client: JellyfinClient
    var playsDirectly = false

    /// id of the card at the leading edge; driven by scrolling and by the arrow buttons.
    @State private var leadingID: String?
    @Environment(\.interfaceScale) private var scale

    private var leadingIndex: Int { items.firstIndex { $0.id == leadingID } ?? 0 }
    private var pageSize: Int { style == .poster ? 4 : 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .scaledFont(.title2, weight: .semibold)
                Spacer()
                // Arrow buttons, like the Jellyfin apps, for mice without horizontal scrolling.
                HStack(spacing: 6) {
                    arrow("chevron.left", enabled: leadingIndex > 0) { move(-pageSize) }
                    arrow("chevron.right", enabled: leadingIndex < items.count - 1) { move(pageSize) }
                }
            }
            .padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18 * scale) {
                    ForEach(items) { item in
                        ItemLink(item: item, playsDirectly: playsDirectly) {
                            ItemCard(item: item, style: style, client: client)
                        }
                        .frame(width: (style == .poster ? 150 : 290) * scale)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            }
            .scrollPosition(id: $leadingID, anchor: .leading)
            // Let the hover zoom and shadow draw past the row's edges instead of being cut off.
            .scrollClipDisabled()
        }
    }

    private func move(_ delta: Int) {
        let target = min(max(leadingIndex + delta, 0), items.count - 1)
        withAnimation(.smooth(duration: 0.35)) { leadingID = items[target].id }
    }

    private func arrow(_ systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .scaledFont(size: 12, weight: .semibold)
                .frame(width: 26, height: 26)
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
    }
}

struct ItemCard: View {
    enum Style { case poster, landscape }

    let item: BaseItemDto
    let style: Style
    let client: JellyfinClient

    @State private var isHovering = false

    private var artworkURL: URL? {
        switch style {
        case .poster: client.posterURL(for: item, maxWidth: 400)
        case .landscape: client.landscapeURL(for: item, maxWidth: 640)
        }
    }

    private var title: String {
        if item.type == .episode, let series = item.seriesName { return series }
        return item.name ?? "Untitled"
    }

    private var subtitle: String? {
        if let label = item.episodeLabel {
            return [label, item.name].compactMap { $0 }.joined(separator: " · ")
        }
        return item.productionYear.map(String.init)
    }

    @ViewBuilder
    private var badge: some View {
        if let unplayed = item.userData?.unplayedItemCount, unplayed > 0, item.type == .series || item.type == .season {
            Text("\(unplayed)")
                .scaledFont(.caption2, weight: .bold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.tint, in: Capsule())
                .foregroundStyle(.white)
        } else if item.userData?.played == true {
            Image(systemName: "checkmark.circle.fill")
                .scaledFont(.body)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
                .shadow(radius: 2)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Artwork(url: artworkURL, aspectRatio: style == .poster ? 2.0 / 3.0 : 16.0 / 9.0)
                .overlay(alignment: .bottom) {
                    if let progress = item.progress {
                        ProgressBar(value: progress).padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) { badge.padding(6) }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(isHovering ? 0.5 : 0.08), lineWidth: isHovering ? 2 : 1)
                }
                .scaleEffect(isHovering ? 1.03 : 1)
                .shadow(color: .black.opacity(isHovering ? 0.45 : 0.2), radius: isHovering ? 14 : 6, y: 4)

            Text(title)
                .scaledFont(.callout, weight: .medium)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isHovering = hovering }
        }
    }
}

/// Artwork box backed by ImagePipeline (cached, retried, downsampled off-main).
struct Artwork: View {
    let url: URL?
    /// nil = fill whatever frame the parent gives (backdrops).
    let aspectRatio: CGFloat?
    var maxPixelSize = 700

    @State private var image: DecodedImage?
    @State private var failed = false

    init(url: URL?, aspectRatio: CGFloat?, maxPixelSize: Int = 700) {
        self.url = url
        self.aspectRatio = aspectRatio
        self.maxPixelSize = maxPixelSize
        // Already decoded? Show it on the first frame, no placeholder flash.
        _image = State(initialValue: url.flatMap { ImagePipeline.shared.cachedImage(for: $0) })
    }

    @ViewBuilder
    private var sizingBox: some View {
        if let aspectRatio {
            Color.clear.aspectRatio(aspectRatio, contentMode: .fit)
        } else {
            Color.clear
        }
    }

    var body: some View {
        sizingBox
            .background(.quaternary)
            .overlay {
                if let image {
                    Image(decorative: image.cgImage, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else if failed || url == nil {
                    Image(systemName: "photo")
                        .scaledFont(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
            .clipped()
            .task(id: url) {
                guard let url else { image = nil; return }
                if let hit = ImagePipeline.shared.cachedImage(for: url) {
                    image = hit
                    return
                }
                image = nil
                failed = false
                let result = await ImagePipeline.shared.image(for: url, maxPixelSize: maxPixelSize)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    image = result
                    failed = result == nil
                }
            }
    }
}

struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.55))
                Capsule().fill(.tint).frame(width: proxy.size.width * value)
            }
        }
        .frame(height: 4)
    }
}

/// One line of text that ends in "…" when it doesn't fit. While `isActive` (hover), a cut-off line slowly
/// scrolls to show the rest, pauses, and slides back, like Music. Text that fits never moves, and nothing
/// runs unless the line is cut off and hovered.
struct MarqueeText: View {
    let text: String
    let isActive: Bool

    @State private var fullWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isScrolling = false

    private var overflow: CGFloat { max(0, (fullWidth - boxWidth).rounded(.up)) }

    var body: some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
            .opacity(isScrolling ? 0 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { boxWidth = $0 }
            .background(alignment: .leading) {
                // Measures the full single-line width without affecting layout.
                Text(text)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { fullWidth = $0 }
            }
            .overlay(alignment: .leading) {
                if isScrolling {
                    Text(text)
                        .lineLimit(1)
                        .fixedSize()
                        .offset(x: offset)
                }
            }
            .clipped()
            .task(id: isActive && overflow > 0) {
                guard isActive, overflow > 0 else {
                    isScrolling = false
                    offset = 0
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
                isScrolling = true
                while !Task.isCancelled {
                    let duration = Double(overflow) / 35 // points per second
                    withAnimation(.linear(duration: duration)) { offset = -overflow }
                    try? await Task.sleep(for: .seconds(duration + 1.2))
                    guard !Task.isCancelled else { break }
                    withAnimation(.easeInOut(duration: 0.35)) { offset = 0 }
                    try? await Task.sleep(for: .seconds(1.5))
                }
            }
    }
}

struct ErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).scaledFont(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Retry", action: retry)
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
