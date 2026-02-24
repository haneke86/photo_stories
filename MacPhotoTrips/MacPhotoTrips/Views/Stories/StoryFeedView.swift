import SwiftUI

/// Full-screen vertical-swipe story feed.
struct StoryFeedView: View {
    @ObservedObject var feedVM: StoryFeedViewModel
    @ObservedObject var dashboardVM: DashboardViewModel
    @ObservedObject var authVM: AuthViewModel

    var body: some View {
        Group {
            switch feedVM.state {
            case .idle:
                idleState
            case .loading:
                loadingState
            case .generating:
                generatingState
            case .partial, .ready:
                feedState
            case .error(let message):
                errorState(message: message)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if feedVM.cards.isEmpty && feedVM.state == .idle {
                await feedVM.loadCachedCards()
            }
            await feedVM.refreshUsage()
        }
    }

    // MARK: - Idle State

    private var idleState: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(DesignTokens.gradient)

                Text("Trip Stories")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)

                Text("Generate AI-powered stories about your trips, years, seasons, and favorite places.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if !feedVM.isAvailable {
                    Button {
                        Task { await authVM.signIn() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo")
                                .font(.body)
                            Text("Sign in to generate stories")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(DesignTokens.teal.opacity(0.3))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(DesignTokens.teal.opacity(0.5), lineWidth: 1))
                    }
                    .disabled(authVM.isLoading)
                }

                if feedVM.isAtStoryLimit {
                    Text("Monthly story limit reached")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                    if let info = feedVM.usageInfo {
                        Text("Resets \(info.resetsAt)")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.textTertiary)
                    }
                } else if let remaining = feedVM.remainingStoriesText {
                    Text(remaining)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textTertiary)
                }

                Button {
                    Task { await feedVM.generate(timeline: dashboardVM.timeline) }
                } label: {
                    Label("Generate Stories", systemImage: "wand.and.stars")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(feedVM.isAtStoryLimit ? DesignTokens.teal.opacity(0.3) : DesignTokens.teal)
                        .clipShape(Capsule())
                }
                .disabled(!feedVM.isAvailable || feedVM.isAtStoryLimit)
                .padding(.top, 8)

                Spacer()
                Spacer()
            }
        }
        .refreshable {
            await feedVM.regenerate(timeline: dashboardVM.timeline)
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(DesignTokens.teal)

                Text("Loading stories...")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
    }

    // MARK: - Generating State

    private var generatingState: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 16) {
                Spacer()

                ProgressView()
                    .scaleEffect(1.2)
                    .tint(DesignTokens.teal)

                Text(feedVM.generationProgress)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textSecondary)

                Spacer()
            }
        }
    }

    // MARK: - Feed State (vertical swipe)

    private var feedState: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(feedVM.cards) { card in
                    FullScreenStoryCard(card: card)
                        .containerRelativeFrame(.vertical)
                }

                // End card
                endCard
                    .containerRelativeFrame(.vertical)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .refreshable {
            await feedVM.regenerate(timeline: dashboardVM.timeline)
        }
    }

    // MARK: - End Card

    private var endCard: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 16) {
                Spacer()

                if feedVM.isGenerating {
                    ProgressView()
                        .scaleEffect(1.0)
                        .tint(DesignTokens.teal)

                    Text("More stories being crafted...")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(DesignTokens.teal)

                    Text("All caught up")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("Come back later for new stories")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)

                    Button {
                        Task { await feedVM.generate(timeline: dashboardVM.timeline) }
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(DesignTokens.teal.opacity(0.2))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(DesignTokens.teal.opacity(0.3), lineWidth: 1))
                    }
                    .padding(.top, 8)
                }

                Spacer()
            }
        }
    }

    // MARK: - Error State

    private func errorState(message: String) -> some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Something went wrong")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    Task { await feedVM.generate(timeline: dashboardVM.timeline) }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(DesignTokens.teal)
                        .clipShape(Capsule())
                }

                Spacer()
            }
        }
    }
}
