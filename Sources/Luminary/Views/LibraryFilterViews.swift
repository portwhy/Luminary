import JellyfinKit
import SwiftUI

/// Wraps its children onto new lines, like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

/// A pill that toggles on tap; with `onRemove` set it shows a ✕ instead (used for the active-filter row).
struct FilterChip: View {
    let title: String
    var isSelected = false
    var showsRemove = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).lineLimit(1)
                if showsRemove { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isSelected || showsRemove ? AnyShapeStyle(Color.accentColor.opacity(0.85)) : AnyShapeStyle(.quaternary), in: Capsule())
            .foregroundStyle(isSelected || showsRemove ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// Filter button + popover for a library page.
struct LibraryFilterButton: View {
    let options: FilterOptions?
    @Binding var filter: LibraryFilter

    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Label(filter.isEmpty ? "Filter" : "Filter · \(filter.count)", systemImage: "line.3.horizontal.decrease")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(filter.isEmpty ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.accentColor.opacity(0.85)), in: Capsule())
                .foregroundStyle(filter.isEmpty ? Color.primary : Color.white)
        }
        .buttonStyle(.plain)
        .disabled(options == nil)
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            if let options { FilterPanel(options: options, filter: $filter) }
        }
    }
}

private struct FilterPanel: View {
    let options: FilterOptions
    @Binding var filter: LibraryFilter

    @State private var tagSearch = ""

    /// Selected tags first, then matches for the search; with no search, the first few alphabetically.
    private var visibleTags: [String] {
        let selected = options.tags.filter { filter.tags.contains($0) }
        let query = tagSearch.trimmingCharacters(in: .whitespaces)
        let others = options.tags.filter { !filter.tags.contains($0) && (query.isEmpty || $0.localizedCaseInsensitiveContains(query)) }
        return selected + others.prefix(query.isEmpty ? 30 : 80)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Filter").font(.headline)
                Spacer()
                Button("Clear All") { filter = LibraryFilter() }
                    .buttonStyle(.borderless)
                    .disabled(filter.isEmpty)
            }
            .padding([.horizontal, .top], 14)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !options.genres.isEmpty {
                        section("Genres") {
                            ForEach(options.genres, id: \.self) { genre in
                                FilterChip(title: genre, isSelected: filter.genres.contains(genre)) { toggle(&filter.genres, genre) }
                            }
                        }
                    }
                    if !options.years.isEmpty {
                        section("Year") {
                            ForEach(options.years.sorted(by: >), id: \.self) { year in
                                FilterChip(title: String(year), isSelected: filter.years.contains(year)) { toggle(&filter.years, year) }
                            }
                        }
                    }
                    if !options.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tags").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            TextField("Search \(options.tags.count) tags", text: $tagSearch)
                                .textFieldStyle(.roundedBorder)
                            FlowLayout {
                                ForEach(visibleTags, id: \.self) { tag in
                                    FilterChip(title: tag, isSelected: filter.tags.contains(tag)) { toggle(&filter.tags, tag) }
                                }
                            }
                            if tagSearch.isEmpty && options.tags.count > 30 {
                                Text("Type to search the rest.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 380, height: 460)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            FlowLayout { content() }
        }
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}

/// The selected filters as removable pills under the page title.
struct ActiveFilterRow: View {
    @Binding var filter: LibraryFilter

    var body: some View {
        FlowLayout {
            ForEach(filter.genres.sorted(), id: \.self) { genre in
                FilterChip(title: genre, showsRemove: true) { filter.genres.remove(genre) }
            }
            ForEach(filter.years.sorted(by: >), id: \.self) { year in
                FilterChip(title: String(year), showsRemove: true) { filter.years.remove(year) }
            }
            ForEach(filter.tags.sorted(), id: \.self) { tag in
                FilterChip(title: tag, showsRemove: true) { filter.tags.remove(tag) }
            }
            // Same height and padding as a chip so it sits level with them.
            Button { filter = LibraryFilter() } label: {
                Text("Clear All")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }
}
