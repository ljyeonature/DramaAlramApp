import SwiftUI
import SwiftData

struct DramaDetailView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.modelContext) private var modelContext
    let drama: Drama

    @Query private var matchingFavorites: [FavoriteDrama]
    @State private var cast: [CastMember] = []
    @State private var availableOTT: [Channel] = []
    @State private var isLoadingCast = false

    init(drama: Drama) {
        self.drama = drama
        let id = drama.id
        _matchingFavorites = Query(filter: #Predicate<FavoriteDrama> { $0.dramaId == id })
    }

    private var isFavorited: Bool { !matchingFavorites.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                hero
                if !availableOTT.isEmpty {
                    sectionView(title: "다시 보기") {
                        ottRow
                    }
                }
                if let synopsis = drama.synopsis, !synopsis.isEmpty {
                    sectionView(title: "시놉시스") {
                        Text(synopsis)
                            .font(.body)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                sectionView(title: "출연") {
                    castContent
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xxl)
        }
        .navigationTitle(drama.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorited ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorited ? .red : .primary)
                        .symbolEffect(.bounce, value: isFavorited)
                }
                .accessibilityLabel(isFavorited ? "즐겨찾기 해제" : "즐겨찾기 추가")
            }
        }
        .refreshable {
            await loadCast()
            await loadAvailability()
        }
        .task {
            await loadCast()
            await loadAvailability()
        }
    }

    // MARK: - Favorite toggle

    private func toggleFavorite() {
        if let existing = matchingFavorites.first {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FavoriteDrama(drama: drama))
        }
        try? modelContext.save()
    }

    // MARK: - 다시보기 (OTT)

    private var ottRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(availableOTT) { ch in
                    Text(ch.name)
                        .font(AppTypography.caption.weight(.semibold))
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(AppColors.accent.opacity(0.12), in: .capsule)
                        .foregroundStyle(AppColors.accent)
                }
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: AppSpacing.lg) {
            AsyncImage(url: drama.posterURL) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default:
                    ZStack {
                        AppColors.cardBackground
                        Image(systemName: "tv").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 110, height: 154)
            .clipShape(.rect(cornerRadius: AppCornerRadius.md))

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(drama.title).font(.title3).bold()
                if let titleEn = drama.titleEn {
                    Text(titleEn)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                statusBadge
                metaLines
                Spacer(minLength: 0)
            }
            Spacer()
        }
        .padding(.top, AppSpacing.md)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch drama.status {
        case .onAir:
            Text("방영중")
                .font(AppTypography.badge)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.green.opacity(0.2), in: .capsule)
                .foregroundStyle(.green)
        case .upcoming:
            Text("방영 예정")
                .font(AppTypography.badge)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.orange.opacity(0.2), in: .capsule)
                .foregroundStyle(.orange)
        case .ended:
            Text("종영")
                .font(AppTypography.badge)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.gray.opacity(0.2), in: .capsule)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var metaLines: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let total = drama.totalEpisodes {
                Text("\(total)부작")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let start = drama.startDate {
                Text("첫방 \(start, format: .dateTime.year().month().day())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func sectionView<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    // MARK: - Cast

    @ViewBuilder
    private var castContent: some View {
        if isLoadingCast && cast.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if cast.isEmpty {
            Text("출연진 정보가 없습니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: AppSpacing.md) {
                    ForEach(cast) { member in
                        CastAvatar(member: member)
                    }
                }
                .padding(.vertical, AppSpacing.xs)
            }
        }
    }

    // MARK: - Loader

    private func loadCast() async {
        isLoadingCast = true
        defer { isLoadingCast = false }
        cast = (try? await deps.dramaRepository.cast(for: drama.id)) ?? []
    }

    private func loadAvailability() async {
        let all = (try? await deps.dramaRepository.availability(for: drama.id)) ?? []
        // OTT 채널만, 본방 채널은 헤더에 이미 표시되므로 제외.
        availableOTT = all.filter { $0.type == .ott && $0.id != drama.channelId }
    }
}

// MARK: - Cast avatar

private struct CastAvatar: View {
    let member: CastMember

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            AsyncImage(url: member.person.profileURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    ZStack {
                        Circle().fill(AppColors.cardBackground)
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())

            Text(member.person.name)
                .font(.caption)
                .lineLimit(1)
            if let character = member.character, !character.isEmpty {
                Text(character)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 84)
    }
}

#Preview {
    NavigationStack {
        DramaDetailView(drama: Drama(
            id: UUID(),
            title: "샘플 드라마",
            titleEn: "Sample Drama",
            synopsis: "예시 시놉시스입니다. 한국 드라마의 흥미진진한 이야기를 다룹니다.",
            posterURL: nil,
            channelId: nil,
            status: .onAir,
            totalEpisodes: 16,
            startDate: Date(),
            endDate: nil,
            tmdbId: nil
        ))
        .environment(AppDependencies(repository: MockDramaRepository()))
    }
}
