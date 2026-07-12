import SwiftUI
import SwiftData

struct ScheduleView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var date = Date()
    @State private var channels: [Channel] = []
    @State private var selectedChannelID: UUID? = nil   // nil = 전체

    @State private var schedule: [ScheduledEpisode] = []
    @State private var isLoading = false
    @State private var loadError: String?

    @Query private var allFavorites: [FavoriteDrama]

    private var favoriteIDs: Set<UUID> {
        Set(allFavorites.map(\.dramaId))
    }

    private func toggleFavorite(_ drama: Drama) {
        // 로컬 SwiftData + (로그인 시) Supabase 양쪽에 반영.
        let willBeFavorite = !allFavorites.contains { $0.dramaId == drama.id }
        Task {
            await deps.favoritesService.setFavorite(willBeFavorite, drama: drama, in: modelContext)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                channelFilter
                Divider()
                content
            }
            .navigationTitle("편성표")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            .task { await loadChannels() }
            .task(id: filterKey) { await loadSchedule() }
            .onChange(of: scenePhase) { _, phase in
                // 앱을 백그라운드에 두고 크롤러 돌린 뒤 돌아왔을 때 자동 갱신.
                if phase == .active {
                    Task { await loadSchedule() }
                }
            }
        }
    }

    // 날짜 또는 채널 선택이 바뀌면 재로드.
    private var filterKey: String {
        "\(date.timeIntervalSince1970)|\(selectedChannelID?.uuidString ?? "all")"
    }

    // MARK: - Channel filter (방송 / OTT 2단)

    @ViewBuilder
    private var channelFilter: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            categoryRow(label: "방송", items: broadcastChannels, showAllChip: true)
            if !ottChannels.isEmpty {
                categoryRow(label: "OTT", items: ottChannels, showAllChip: false)
            }
        }
        .padding(.vertical, AppSpacing.sm)
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func categoryRow(label: String, items: [Channel], showAllChip: Bool) -> some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            Text(label)
                .font(AppTypography.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
                .padding(.leading, AppSpacing.lg)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    if showAllChip {
                        chip(label: "전체", selected: selectedChannelID == nil) {
                            selectedChannelID = nil
                        }
                    }
                    ForEach(items) { ch in
                        chip(label: ch.name, selected: selectedChannelID == ch.id) {
                            selectedChannelID = ch.id
                        }
                    }
                }
                .padding(.trailing, AppSpacing.lg)
            }
        }
    }

    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(AppTypography.caption)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs + 2)
                .background(selected ? AppColors.accent : Color(.systemBackground))
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(.capsule)
                .overlay(
                    Capsule().stroke(
                        selected ? Color.clear : AppColors.separator,
                        lineWidth: 0.5
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // 사용자 친숙도 기반 표시 순서. seed에 없는 코드는 자동 무시됨.
    private static let channelDisplayOrder: [String] = [
        // 방송: 지상파 → 종편 → 케이블
        "KBS2", "MBC", "SBS", "tvN", "JTBC", "ENA", "MBN", "GENIE_TV",
        // OTT
        "NETFLIX", "TVING", "WAVVE", "COUPANG_PLAY", "DISNEY_PLUS",
    ]

    private var broadcastChannels: [Channel] {
        orderedChannels(of: .broadcast)
    }

    private var ottChannels: [Channel] {
        orderedChannels(of: .ott)
    }

    private func orderedChannels(of type: Channel.ChannelType) -> [Channel] {
        let filtered = channels.filter { $0.type == type }
        let map = Dictionary(uniqueKeysWithValues: filtered.map { ($0.code, $0) })
        // displayOrder 에 있는 것 먼저, 나머지는 알파벳 순으로 뒤에.
        let ordered = Self.channelDisplayOrder.compactMap { map[$0] }
        let remaining = filtered
            .filter { !Self.channelDisplayOrder.contains($0.code) }
            .sorted { $0.code < $1.code }
        return ordered + remaining
    }

    // MARK: - Main content

    @ViewBuilder
    private var content: some View {
        if isLoading && schedule.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            ContentUnavailableView(
                "불러오기 실패",
                systemImage: "exclamationmark.triangle",
                description: Text(loadError)
            )
        } else if schedule.isEmpty {
            ContentUnavailableView(
                "편성된 드라마가 없습니다",
                systemImage: "tv",
                description: Text("다른 날짜나 채널을 선택해보세요.")
            )
        } else {
            List(schedule) { item in
                NavigationLink(value: item.drama) {
                    ScheduleRow(
                        item: item,
                        isFavorited: favoriteIDs.contains(item.drama.id),
                        onToggleFavorite: { toggleFavorite(item.drama) }
                    )
                }
            }
            .listStyle(.plain)
            .refreshable { await loadSchedule() }
            .navigationDestination(for: Drama.self) { drama in
                DramaDetailView(drama: drama)
            }
        }
    }

    // MARK: - Loaders

    private func loadChannels() async {
        // 정렬/그룹핑은 broadcastChannels/ottChannels computed 속성에서 처리.
        channels = (try? await deps.dramaRepository.channels()) ?? []
    }

    private func loadSchedule() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        let ids: [UUID]? = selectedChannelID.map { [$0] }
        do {
            schedule = try await deps.dramaRepository.schedule(date: date, channelIDs: ids)
        } catch {
            loadError = error.localizedDescription
            schedule = []
        }
    }
}

private struct ScheduleRow: View {
    let item: ScheduledEpisode
    let isFavorited: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            posterThumb

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.sm) {
                    Text(item.episode.airTime, format: .dateTime.hour().minute())
                        .font(AppTypography.timeMono)
                        .foregroundStyle(.secondary)
                    if isLive {
                        Text("LIVE")
                            .font(AppTypography.badge)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(AppColors.liveBadge, in: .capsule)
                            .foregroundStyle(.white)
                    }
                }
                Text(item.drama.title)
                    .font(AppTypography.body)
                    .lineLimit(2)
                Text("\(item.channel.name) · \(item.episode.number)회")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            favoriteButton
        }
        .padding(.vertical, AppSpacing.xs)
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
        // 행 전체 탭(NavigationLink) 과 분리되도록 borderless 스타일.
        .buttonStyle(.borderless)
        .accessibilityLabel(isFavorited ? "즐겨찾기 해제" : "즐겨찾기 추가")
    }

    @ViewBuilder
    private var posterThumb: some View {
        AsyncImage(url: item.drama.posterURL) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFill()
            case .failure, .empty:
                ZStack {
                    AppColors.cardBackground
                    Image(systemName: "tv")
                        .foregroundStyle(.secondary)
                }
            @unknown default:
                AppColors.cardBackground
            }
        }
        .frame(width: 50, height: 70)
        .clipShape(.rect(cornerRadius: AppCornerRadius.sm))
    }

    private var isLive: Bool {
        let now = Date()
        let end = item.episode.airTime.addingTimeInterval(Double(item.episode.durationMin) * 60)
        return now >= item.episode.airTime && now < end
    }
}

#Preview {
    ScheduleView()
        .environment(AppDependencies.preview())
}
