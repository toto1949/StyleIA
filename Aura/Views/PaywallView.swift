import StoreKit
import SwiftUI

/// Full-screen paywall displayed whenever the user hits a gated feature.
struct PaywallView: View {
    /// Which feature the user was trying to use when the paywall appeared.
    let trigger: PaywallTrigger
    let onDismiss: () -> Void

    @ObservedObject private var service = SubscriptionService.shared
    @State private var billing: BillingCycle = .yearly
    @State private var purchaseError: String?
    @State private var isPurchasingID: SceneMeProductID?
    @Environment(\.dismiss) private var dismiss

    enum BillingCycle: String, CaseIterable, Identifiable {
        case monthly = "Monthly"
        case yearly  = "Yearly"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack(alignment: .top) {
            SceneMeTheme.ink.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 56)
                        .padding(.horizontal, 26)

                    billingToggle
                        .padding(.top, 28)
                        .padding(.horizontal, 26)

                    planCards
                        .padding(.top, 20)
                        .padding(.horizontal, 20)

                    featureTable
                        .padding(.top, 28)
                        .padding(.horizontal, 26)

                    legalFooter
                        .padding(.top, 22)
                        .padding(.horizontal, 26)
                        .padding(.bottom, 50)
                }
            }
            .scrollIndicators(.hidden)

            closeButton
        }
        .preferredColorScheme(.dark)
        .task {
            // Retry loading products if the initial fetch at launch failed.
            if service.products.isEmpty {
                await service.loadProducts()
            }
        }
        .overlay(alignment: .bottom) {
            if let error = purchaseError {
                Text(error)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.42))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(SceneMeTheme.surface.opacity(0.97))
                    .clipShape(Capsule())
                    .padding(.horizontal, 26)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { withAnimation { purchaseError = nil } }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: purchaseError)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            (
                Text("Scene")
                    .foregroundStyle(SceneMeTheme.text)
                +
                Text("Me")
                    .foregroundStyle(SceneMeTheme.gold)
            )
            .font(.system(size: 32, weight: .regular, design: .serif))

            Text(trigger.headline)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .foregroundStyle(SceneMeTheme.subtleText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            SceneMeEyebrow(text: trigger.subline, alignment: .center)
                .padding(.top, 2)
        }
    }

    // MARK: - Billing toggle

    private var billingToggle: some View {
        HStack(spacing: 0) {
            ForEach(BillingCycle.allCases) { cycle in
                let isSelected = billing == cycle

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        billing = cycle
                    }
                } label: {
                    ZStack {
                        if isSelected {
                            Capsule()
                                .fill(SceneMeTheme.surface)
                                .matchedGeometryEffect(id: "billingSelection", in: billingNamespace)
                        }

                        HStack(spacing: 5) {
                            Text(cycle.rawValue.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(isSelected ? SceneMeTheme.text : SceneMeTheme.faintText)

                            if cycle == .yearly {
                                savingsBadge
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                    }
                }
                .buttonStyle(SceneMePressButtonStyle())
                .frame(maxWidth: .infinity)
            }
        }
        .padding(4)
        .background(SceneMeTheme.panel)
        .clipShape(Capsule())
        .overlay { Capsule().stroke(SceneMeTheme.hairline, lineWidth: 1) }
    }

    @Namespace private var billingNamespace

    private var savingsBadge: some View {
        Text("SAVE 37%+")
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(SceneMeTheme.gold)
            .clipShape(Capsule())
    }

    // MARK: - Plan cards

    private var planCards: some View {
        HStack(alignment: .top, spacing: 12) {
            planCard(tier: .creator, highlight: trigger.suggestedTier == .creator)
            planCard(tier: .pro,     highlight: trigger.suggestedTier == .pro)
        }
    }

    private func planCard(tier: SubscriptionTier, highlight: Bool) -> some View {
        let monthlyID: SceneMeProductID = tier == .pro ? .proMonthly     : .creatorMonthly
        let yearlyID:  SceneMeProductID = tier == .pro ? .proYearly      : .creatorYearly
        let productID  = billing == .yearly ? yearlyID : monthlyID
        let price      = service.formattedPrice(for: productID)
        let perMonth   = billing == .yearly ? service.monthlyEquivalent(for: yearlyID) : nil
        let isLoading  = isPurchasingID == productID || service.isPurchasing
        let isAvailable = price != nil

        return VStack(alignment: .leading, spacing: 16) {
            // Plan label
            HStack {
                Text(tier.displayName.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(highlight ? Color.black.opacity(0.85) : SceneMeTheme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(highlight ? SceneMeTheme.gold : SceneMeTheme.surface)
                    .clipShape(Capsule())

                if service.tier == tier {
                    Text("CURRENT")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(SceneMeTheme.gold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SceneMeTheme.gold.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()
            }

            // Price block
            VStack(alignment: .leading, spacing: 3) {
                if let price {
                    Text(price)
                        .font(.system(size: 26, weight: .regular, design: .serif))
                        .foregroundStyle(SceneMeTheme.text)

                    if let perMonth {
                        Text(perMonth)
                            .font(.system(size: 12))
                            .foregroundStyle(SceneMeTheme.gold)
                    } else {
                        Text(billing == .yearly ? "billed yearly" : "per month")
                            .font(.system(size: 12))
                            .foregroundStyle(SceneMeTheme.subtleText)
                    }
                } else {
                    // Products haven't loaded from the App Store yet.
                    ProgressView()
                        .tint(SceneMeTheme.gold)
                        .frame(height: 32)

                    Text("Loading price…")
                        .font(.system(size: 12))
                        .foregroundStyle(SceneMeTheme.subtleText)
                }
            }

            // Key features for this tier
            VStack(alignment: .leading, spacing: 8) {
                ForEach(keyFeatures(for: tier), id: \.self) { feature in
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(SceneMeTheme.gold)
                        Text(feature)
                            .font(.system(size: 12))
                            .foregroundStyle(SceneMeTheme.text)
                    }
                }
            }

            // Subscribe button
            Button {
                Task { await subscribe(to: productID) }
            } label: {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .tint(highlight ? Color.black.opacity(0.7) : SceneMeTheme.gold)
                    } else {
                        Text(service.tier == tier ? "MANAGE" : "SUBSCRIBE")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(highlight ? Color.black.opacity(0.88) : SceneMeTheme.text)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    Group {
                        if highlight {
                            LinearGradient(
                                colors: [SceneMeTheme.goldBright, SceneMeTheme.gold],
                                startPoint: .top, endPoint: .bottom
                            )
                        } else {
                            LinearGradient(
                                colors: [SceneMeTheme.surface, SceneMeTheme.surface],
                                startPoint: .top, endPoint: .bottom
                            )
                        }
                    }
                )
                .clipShape(Capsule())
                .overlay {
                    if !highlight {
                        Capsule().stroke(SceneMeTheme.hairline, lineWidth: 1)
                    }
                }
                .opacity(isLoading || !isAvailable ? 0.7 : 1)
            }
            .buttonStyle(SceneMePressButtonStyle())
            .disabled(isLoading || !isAvailable)
        }
        .padding(16)
        .background(highlight ? SceneMeTheme.panel : SceneMeTheme.ink)
        .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous)
                .stroke(
                    highlight ? SceneMeTheme.gold.opacity(0.5) : SceneMeTheme.hairline,
                    lineWidth: highlight ? 1.5 : 1
                )
        }
    }

    private func keyFeatures(for tier: SubscriptionTier) -> [String] {
        switch tier {
        case .creator:
            return ["30 generations/mo", "Custom scenes", "Outfit re-roll", "Cinematic filters"]
        case .pro:
            return ["Unlimited generations", "Video animation", "Companion photos", "Max quality"]
        default:
            return []
        }
    }

    // MARK: - Feature comparison table

    private var featureTable: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                Text("Feature")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Free")
                    .frame(width: 56, alignment: .center)
                Text("Creator")
                    .frame(width: 64, alignment: .center)
                    .foregroundStyle(SceneMeTheme.gold)
                Text("Pro")
                    .frame(width: 56, alignment: .center)
                    .foregroundStyle(SceneMeTheme.gold)
            }
            .font(.system(size: 10, weight: .heavy))
            .tracking(1.2)
            .foregroundStyle(SceneMeTheme.subtleText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(SceneMeTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous))

            ForEach(Array(SubscriptionTier.featureTable.enumerated()), id: \.offset) { index, feature in
                featureRow(feature: feature, isEven: index.isMultiple(of: 2))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SceneMeTheme.innerRadius, style: .continuous)
                .stroke(SceneMeTheme.hairline, lineWidth: 1)
        }
    }

    private func featureRow(feature: SubscriptionTier.Feature, isEven: Bool) -> some View {
        HStack {
            Text(feature.title)
                .font(.system(size: 12))
                .foregroundStyle(SceneMeTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            cell(feature.freeValue)
                .frame(width: 56)

            cell(feature.creatorValue)
                .frame(width: 64)

            cell(feature.proValue)
                .frame(width: 56)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isEven ? SceneMeTheme.panel : SceneMeTheme.ink)
    }

    @ViewBuilder
    private func cell(_ value: String?) -> some View {
        if let value {
            Text(value)
                .font(.system(size: 12, weight: value == "✓" ? .bold : .regular))
                .foregroundStyle(value == "✓" ? SceneMeTheme.gold : SceneMeTheme.text)
                .multilineTextAlignment(.center)
        } else {
            Image(systemName: "minus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SceneMeTheme.faintText)
        }
    }

    // MARK: - Legal footer

    private var legalFooter: some View {
        VStack(spacing: 12) {
            // Restore link
            Button {
                Task {
                    await service.restorePurchases()
                    if service.tier > .free {
                        withAnimation { onDismiss() }
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if service.isRestoring {
                        ProgressView().tint(SceneMeTheme.gold).scaleEffect(0.75)
                    }
                    Text("Restore Purchases")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SceneMeTheme.subtleText)
                }
            }
            .buttonStyle(SceneMePressButtonStyle())

            Text(
                "Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period. Manage or cancel in iPhone Settings > Apple ID > Subscriptions."
            )
            .font(.system(size: 10))
            .foregroundStyle(SceneMeTheme.faintText)
            .multilineTextAlignment(.center)

            SceneMeLegal.InlineLinks()
        }
    }

    // MARK: - Close button

    private var closeButton: some View {
        HStack {
            Spacer()
            Button {
                onDismiss()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SceneMeTheme.subtleText)
                    .frame(width: 34, height: 34)
                    .background(SceneMeTheme.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(SceneMePressButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    // MARK: - Action

    private func subscribe(to productID: SceneMeProductID) async {
        if service.tier == productID.tier {
            // Already on this tier — open system Manage Subscriptions
            if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                await UIApplication.shared.open(url)
            }
            return
        }

        isPurchasingID = productID
        withAnimation { purchaseError = nil }

        do {
            try await service.purchase(productID)
            if service.tier >= productID.tier {
                withAnimation { onDismiss() }
                dismiss()
            }
        } catch {
            withAnimation {
                purchaseError = (error as? LocalizedError)?.errorDescription
                    ?? "Purchase failed. Please try again."
            }
        }
        isPurchasingID = nil
    }
}

// MARK: - Trigger context

/// Why the paywall is being shown — drives the headline and the highlighted plan.
enum PaywallTrigger: Identifiable {
    case generationLimitReached(remaining: Int, tierNeeded: SubscriptionTier)
    case featureLocked(feature: String, tierNeeded: SubscriptionTier)
    case manualUpgrade

    var id: String {
        switch self {
        case .generationLimitReached: return "limit"
        case .featureLocked(let f, _): return "locked-\(f)"
        case .manualUpgrade: return "upgrade"
        }
    }

    var headline: String {
        switch self {
        case .generationLimitReached(_, _):
            return "You've used all your free\ngenerations this month."
        case .featureLocked(let feature, _):
            return "Unlock \(feature)\nwith a SceneMe subscription."
        case .manualUpgrade:
            return "Create stunning scenes\nwith no limits."
        }
    }

    var subline: String {
        switch self {
        case .generationLimitReached:
            return "Upgrade to keep going"
        case .featureLocked:
            return "Choose your plan"
        case .manualUpgrade:
            return "Choose your plan"
        }
    }

    var suggestedTier: SubscriptionTier {
        switch self {
        case .generationLimitReached(_, let tier): return tier
        case .featureLocked(_, let tier):          return tier
        case .manualUpgrade:                       return .pro
        }
    }
}

// MARK: - Preview stub
