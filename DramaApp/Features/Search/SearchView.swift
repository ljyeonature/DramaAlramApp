import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.modelContext) private var modelContext

    @State private var query = ""
    @State private var results: SearchResults = .empty
    @State private var isSearching = false

    @Query private var allFavorites: [FavoriteDrama]

    private var favoriteIDs: Set<UUID> {
        Set(allFavorites.map(\.dramaId))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("검색")
                .searchable(text: $query, prompt: "드라마 제목 또는 출연 배우")
                .task(id: query) { await runSearch() }
                .navigationDestination(for: Drama.self) { drama in
                    DramaDetailView(drama: drama)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if query.isEmpty {
            ContentUnavailableView(
                "검색",
                systemImage: "magnifyingglass",
                description: Text("드라마 제목이나 출연 배우를 입력하세요.")
            )
        } else if isSearching && results.isEmpty {
            ProgressView()
        } else if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        List {
            if !results.dramas.isEmpty {
                Section("제목 (\(results.dramas.count))") {
                    ForEach(results.dramas) { drama in
                        NavigationLink(value: drama) {
                            DramaSearchRow(
                                drama: drama,
                                isFavorited: favoriteIDs.contains(drama.id),
                                onToggleFavorite: { toggleFavorite(drama) }
                            )
                        }
                    }
                }
            }
            ForEach(results.personMatches) { match in
                Section("출연: \(match.person.name)") {
                    ForEach(match.dramas) { drama in
                        NavigationLink(value: drama) {
                            DramaSearchRow(
                                drama: drama,
                                isFavorited: favoriteIDs.contains(drama.id),
                                onToggleFavorite: { toggleFavorite(drama) }
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = .empty
            return
        }
        // 디바운스 — 빠른 타이핑 중 중간 쿼리는 버림.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled, trimmed == query.trimmingCharacters(in: .whitespaces) else {
            return
        }
        isSearching = true
        defer { isSearching = false }
        results = (try? await deps.dramaRepository.search(query: trimmed)) ?? .empty
    }

    private func toggleFavorite(_ drama: Drama) {
        if let existing = allFavorites.first(where: { $0.dramaId == drama.id }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FavoriteDrama(drama: drama))
        }
        try? modelContext.save()
    }
}

private struct DramaSearchRow: View {
    let drama: Drama
    let isFavorited: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            AsyncImage(url: drama.posterURL) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: AppColors.cardBackground
                }
            }
            .frame(width: 44, height: 62)
            .clipShape(.rect(cornerRadius: AppCornerRadius.sm))

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(drama.title).font(AppTypography.body).lineLimit(2)
                if let titleEn = drama.titleEn {
                    Text(titleEn)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                statusBadge
            }
            Spacer(minLength: 0)
            favoriteButton
        }
    }

    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: isFavorited ? "heart.fill" : "heart")
                .font(.title3)
                .foregroundStyle(isFavorited ? .red : .secondary)
                .symbolEffect(.bounce, value: isFavorited)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isFavorited ? "즐겨찾기 해제" : "즐겨찾기 추가")
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch drama.status {
        case .onAir:
            Text("방영중")
                .font(AppTypography.badge)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.green.opacity(0.2), in: .capsule)
                .foregroundStyle(.green)
        case .upcoming:
            Text("방영 예정")
                .font(AppTypography.badge)
                .foregroundStyle(.orange)
        case .ended:
            Text("종영")
                .font(AppTypography.badge)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SearchView()
        .environment(AppDependencies.preview())
        .modelContainer(for: FavoriteDrama.self, inMemory: true)
}
