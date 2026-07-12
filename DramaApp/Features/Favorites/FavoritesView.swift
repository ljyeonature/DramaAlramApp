import SwiftUI
import SwiftData

struct FavoritesView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FavoriteDrama.addedAt, order: .reverse)
    private var favorites: [FavoriteDrama]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("즐겨찾기")
                .navigationDestination(for: Drama.self) { drama in
                    DramaDetailView(drama: drama)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if favorites.isEmpty {
            ContentUnavailableView(
                "아직 즐겨찾기가 없습니다",
                systemImage: "heart",
                description: Text("드라마 상세에서 ♡ 버튼을 눌러 추가하세요.")
            )
        } else {
            List {
                Section {
                    ForEach(favorites) { fav in
                        NavigationLink(value: fav.toDrama()) {
                            FavoriteRow(favorite: fav)
                        }
                    }
                    .onDelete(perform: deleteFavorites)
                } header: {
                    Text("\(favorites.count)편")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
        }
    }

    private func deleteFavorites(at offsets: IndexSet) {
        // FavoritesService 로 위임해서 로그인 시 서버에서도 함께 삭제.
        let targets = offsets.map { favorites[$0].toDrama() }
        Task {
            for drama in targets {
                await deps.favoritesService.setFavorite(false, drama: drama, in: modelContext)
            }
        }
    }
}

// MARK: - Row

private struct FavoriteRow: View {
    let favorite: FavoriteDrama

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            poster

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(favorite.title)
                    .font(AppTypography.body)
                    .lineLimit(2)
                if let titleEn = favorite.titleEn {
                    Text(titleEn)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: AppSpacing.sm) {
                    statusBadge
                    if let total = favorite.totalEpisodes {
                        Text("\(total)부작")
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, AppSpacing.xs)
    }

    @ViewBuilder
    private var poster: some View {
        AsyncImage(url: favorite.posterURL) { phase in
            switch phase {
            case .success(let img): img.resizable().scaledToFill()
            default:
                ZStack {
                    AppColors.cardBackground
                    Image(systemName: "tv").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 56, height: 78)
        .clipShape(.rect(cornerRadius: AppCornerRadius.sm))
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch favorite.status {
        case .onAir:
            badge(text: "방영중", color: .green)
        case .upcoming:
            badge(text: "방영 예정", color: .orange)
        case .ended:
            badge(text: "종영", color: .secondary)
        }
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(AppTypography.badge)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }
}

#Preview {
    FavoritesView()
        .environment(AppDependencies())
        .modelContainer(for: FavoriteDrama.self, inMemory: true)
}
