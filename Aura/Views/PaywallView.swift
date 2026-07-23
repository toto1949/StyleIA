import StoreKit
import SwiftUI

/// Full-screen paywall displayed whenever the user hits a gated feature.
struct PaywallView: View {
    /// Which feature the user was trying to use when the paywall appeared.
    let trigger: PaywallTrigger
    let onDismiss: () -> Void

    @ObservedObject private var service = SubscriptionService.shared
    @State private var billing: BillingCycle = .yearly
    @State private var selectedTier: SubscriptionTier
    @State private var purchaseError: String?
    @State private var isPurchasingID: SceneMeProductID?
    @State private var showComparison = false
    @State private var appeared = false
    @Environment(\.dismiss) private var dismiss
    @Namespace private var billingNamespace

    enum BillingCycle: String, CaseIterable, Identifiable {
        case monthly = "Monthly"
        case yearly = "Yearly"
        var id: String { rawValue }
    }

    init(trigger: PaywallTrigger, onDismiss: @escaping () -> Void) {
        self.trigger = trigger
        self.onDismiss = onDismiss
        _selectedTier = State(initialValue: trigger.suggestedTier == .free ? .pro : trigger.suggestedTier)
    }

    var body: some View {
        ZStack {
            atmosphere
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        header
                            .padding(.top, 52)
                            .padding(.horizontal, 28)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 14)

                        billingToggle
                            .padding(.top, 28)
                            .padding(.horizontal, 28)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 10)

                        planPicker
                            .padding(.top, 22)
                            .padding(.horizontal, 22)

                        selectedBenefits
                            .padding(.top, 28)
                            .padding(.horizontal, 28)

                        comparisonSection
                            .padding(.top, 26)
                            .padding(.horizontal, 28)

                        legalFooter
                            .padding(.top, 28)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 140)
                    }
                }
                .scrollIndicators(.hidden)
            }

            VStack {
                HStack {
                    Spacer()
                    closeButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                stickyCTA
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if service.products.isEmpty {
                await service.loadProducts()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86).delay(0.05)) {
                appeared = true
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
                    .padding(.bottom, 118)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { withAnimation { purchaseError = nil } }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: purchaseError)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: selectedTier)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: billing)
    }

    // MARK: - Atmosphere

    private var atmosphere: some View {
        ZStack {
            SceneMeTheme.ink

            RadialGradient(
                colors: [
                    SceneMeTheme.gold.opacity(0.22),
                    SceneMeTheme.gold.opacity(0.06),
                    .clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
            .offset(y: -80)

            RadialGradient(
                colors: [
                    SceneMeTheme.goldBright.opacity(0.08),
                    .clear
                ],
                center: UnitPoint(x: 0.85, y: 0.35),
                startRadius: 10,
                endRadius: 280
            )

            LinearGradient(
                colors: [
                    .clear,
                    SceneMeTheme.ink.opacity(0.55),
                    SceneMeTheme.ink
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(SceneMeTheme.gold.opacity(0.12))
                    .frame(width: 78, height: 78)
                    .blur(radius: 2)

                Image(systemName: "sparkle")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SceneMeTheme.goldBright, SceneMeTheme.gold],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .symbolEffect(.pulse, options: .repeating.speed(0.35), isActive: appeared)
            }
            .scaleEffect(appeared ? 1 : 0.86)

            (
                Text("Scene")
                    .foregroundStyle(SceneMeTheme.text)
                +
                Text("Me")
                    .foregroundStyle(SceneMeTheme.gold)
            )
            .font(.system(size: 40, weight: .regular, design: .serif))

            Text(trigger.headline)
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundStyle(SceneMeTheme.subtleText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

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
                                .shadow(color: SceneMeTheme.gold.opacity(0.18), radius: 10, y: 2)
                        }

                        HStack(spacing: 6) {
                            Text(cycle.rawValue.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.3)
                                .foregroundStyle(isSelected ? SceneMeTheme.text : SceneMeTheme.faintText)

                            if cycle == .yearly {
                                Text(yearlySavingsLabel)
                                    .font(.system(size: 9, weight: .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(Color.black.opacity(0.85))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(SceneMeTheme.gold)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                    }
                }
                .buttonStyle(SceneMePressButtonStyle())
                .frame(maxWidth: .infinity)
            }
        }
        .padding(4)
        .background(SceneMeTheme.panel.opacity(0.92))
        .clipShape(Capsule())
        .overlay { Capsule().stroke(SceneMeTheme.hairline, lineWidth: 1) }
    }

    private var yearlySavingsLabel: String {
        if let savings = yearlySavingsPercent(for: selectedTier) {
            return "SAVE \(savings)%"
        }
        return "SAVE 37%+"
    }

    // MARK: - Plan picker

    private var planPicker: some View {
        VStack(spacing: 12) {
            planOption(tier: .pro)
            planOption(tier: .creator)
        }
    }

    private func planOption(tier: SubscriptionTier) -> some View {
        let isSelected = selectedTier == tier
        let productID = productID(for: tier)
        let price = service.formattedPrice(for: productID)
        let perMonth = billing == .yearly ? service.monthlyEquivalent(for: productID) : nil
        let isCurrent = service.tier == tier

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                selectedTier = tier
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                selectionIndicator(isSelected: isSelected)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(tier.displayName.uppercased())
                            .font(.system(size: 12, weight: .heavy))
                            .tracking(2)
                            .foregroundStyle(isSelected ? SceneMeTheme.gold : SceneMeTheme.text)

                        if tier == .pro {
                            Text("MOST POPULAR")
                                .font(.system(size: 8, weight: .heavy))
                                .tracking(0.8)
                                .foregroundStyle(Color.black.opacity(0.85))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    LinearGradient(
                                        colors: [SceneMeTheme.goldBright, SceneMeTheme.gold],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(Capsule())
                        }

                        if isCurrent {
                            Text("CURRENT")
                                .font(.system(size: 8, weight: .heavy))
                                .tracking(0.8)
                                .foregroundStyle(SceneMeTheme.gold)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(SceneMeTheme.gold.opacity(0.14))
                                .clipShape(Capsule())
                        }
                    }

                    Text(planTagline(for: tier))
                        .font(.system(size: 13))
                        .foregroundStyle(SceneMeTheme.subtleText)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    if let price {
                        Text(price)
                            .font(.system(size: 22, weight: .regular, design: .serif))
                            .foregroundStyle(SceneMeTheme.text)
                            .contentTransition(.numericText())

                        if let perMonth {
                            Text(perMonth)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(SceneMeTheme.gold)
                        } else {
                            Text(billing == .yearly ? "billed yearly" : "per month")
                                .font(.system(size: 11))
                                .foregroundStyle(SceneMeTheme.faintText)
                        }
                    } else {
                        ProgressView()
                            .tint(SceneMeTheme.gold)
                            .scaleEffect(0.85)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous)
                    .fill(isSelected ? SceneMeTheme.panel.opacity(0.95) : SceneMeTheme.ink.opacity(0.35))
            )
            .overlay {
                RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius, style: .continuous)
                    .stroke(
                        isSelected ? SceneMeTheme.gold.opacity(0.65) : SceneMeTheme.hairline,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .shadow(color: isSelected ? SceneMeTheme.gold.opacity(0.16) : .clear, radius: 18, y: 6)
        }
        .buttonStyle(SceneMePressButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(isSelected ? SceneMeTheme.gold : SceneMeTheme.hairline, lineWidth: 1.5)
                .frame(width: 22, height: 22)

            if isSelected {
                Circle()
                    .fill(SceneMeTheme.gold)
                    .frame(width: 12, height: 12)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func planTagline(for tier: SubscriptionTier) -> String {
        switch tier {
        case .pro:
            return "Unlimited stills, Video Director, companions"
        case .creator:
            return "30 generations, custom scenes, clean exports"
        default:
            return ""
        }
    }

    // MARK: - Benefits

    private var selectedBenefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Included with \(selectedTier.displayName)")
                .font(.system(size: 20, weight: .regular, design: .serif))
                .foregroundStyle(SceneMeTheme.text)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(keyFeatures(for: selectedTier).enumerated()), id: \.offset) { index, feature in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SceneMeTheme.gold)
                            .frame(width: 22, height: 22)
                            .background(SceneMeTheme.gold.opacity(0.12))
                            .clipShape(Circle())

                        Text(feature)
                            .font(.system(size: 14))
                            .foregroundStyle(SceneMeTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(x: appeared ? 0 : 8)
                    .animation(
                        .spring(response: 0.45, dampingFraction: 0.86).delay(0.08 + Double(index) * 0.04),
                        value: appeared
                    )
                    .id("\(selectedTier.rawValue)-\(feature)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func keyFeatures(for tier: SubscriptionTier) -> [String] {
        switch tier {
        case .creator:
            return [
                "30 cinematic generations every month",
                "Custom scene templates you can reuse",
                "Outfit re-roll + cinematic filters",
                "Clean exports without the SceneMe mark"
            ]
        case .pro:
            return [
                "Unlimited still generations",
                "Video Director with voice & captions",
                "Companion photos in every scene",
                "Max quality output for stills and clips"
            ]
        default:
            return []
        }
    }

    // MARK: - Comparison

    private var comparisonSection: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    showComparison.toggle()
                }
            } label: {
                HStack {
                    Text("Compare plans")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SceneMeTheme.subtleText)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SceneMeTheme.faintText)
                        .rotationEffect(.degrees(showComparison ? 180 : 0))
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(SceneMePressButtonStyle())

            if showComparison {
                featureTable
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var featureTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Feature")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Free")
                    .frame(width: 52, alignment: .center)
                Text("Creator")
                    .frame(width: 64, alignment: .center)
                    .foregroundStyle(SceneMeTheme.gold)
                Text("Pro")
                    .frame(width: 52, alignment: .center)
                    .foregroundStyle(SceneMeTheme.gold)
            }
            .font(.system(size: 10, weight: .heavy))
            .tracking(1.2)
            .foregroundStyle(SceneMeTheme.subtleText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(SceneMeTheme.surface)

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
                .frame(width: 52)

            cell(feature.creatorValue)
                .frame(width: 64)

            cell(feature.proValue)
                .frame(width: 52)
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

    // MARK: - Sticky CTA

    private var stickyCTA: some View {
        let productID = productID(for: selectedTier)
        let price = service.formattedPrice(for: productID)
        let isLoading = isPurchasingID == productID || service.isPurchasing
        let isAvailable = price != nil
        let isCurrent = service.tier == selectedTier

        return VStack(spacing: 10) {
            Button {
                Task { await subscribe(to: productID) }
            } label: {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .tint(Color.black.opacity(0.7))
                    } else {
                        VStack(spacing: 2) {
                            Text(isCurrent ? "MANAGE SUBSCRIPTION" : ctaTitle(for: selectedTier))
                                .font(.system(size: 13, weight: .bold))
                                .tracking(1.8)

                            if let price, !isCurrent {
                                Text(billing == .yearly ? "\(price) / year" : "\(price) / month")
                                    .font(.system(size: 11, weight: .semibold))
                                    .opacity(0.72)
                            }
                        }
                        .foregroundStyle(Color.black.opacity(0.88))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    LinearGradient(
                        colors: [SceneMeTheme.goldBright, SceneMeTheme.gold],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(Capsule())
                .shadow(color: SceneMeTheme.gold.opacity(0.34), radius: 18, y: 8)
                .opacity(isLoading || !isAvailable ? 0.7 : 1)
            }
            .buttonStyle(SceneMePressButtonStyle())
            .disabled(isLoading || !isAvailable)

            if billing == .yearly, !isCurrent {
                Text("Best value — cancel anytime in Apple Subscriptions")
                    .font(.system(size: 11))
                    .foregroundStyle(SceneMeTheme.faintText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .background(
            LinearGradient(
                colors: [SceneMeTheme.ink.opacity(0), SceneMeTheme.ink.opacity(0.92), SceneMeTheme.ink],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func ctaTitle(for tier: SubscriptionTier) -> String {
        "CONTINUE WITH \(tier.displayName.uppercased())"
    }

    // MARK: - Legal footer

    private var legalFooter: some View {
        VStack(spacing: 14) {
            Button {
                Task {
                    await service.restorePurchases()
                    if service.tier > .free {
                        withAnimation { onDismiss() }
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 6) {
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
                "Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period. Manage or cancel in iPhone Settings → Apple ID → Subscriptions."
            )
            .font(.system(size: 10))
            .foregroundStyle(SceneMeTheme.faintText)
            .multilineTextAlignment(.center)

            SceneMeLegal.InlineLinks()
        }
    }

    // MARK: - Close

    private var closeButton: some View {
        Button {
            onDismiss()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SceneMeTheme.subtleText)
                .frame(width: 34, height: 34)
                .background(SceneMeTheme.surface.opacity(0.92))
                .clipShape(Circle())
                .overlay { Circle().stroke(SceneMeTheme.hairline, lineWidth: 1) }
        }
        .buttonStyle(SceneMePressButtonStyle())
    }

    // MARK: - Helpers

    private func productID(for tier: SubscriptionTier) -> SceneMeProductID {
        switch (tier, billing) {
        case (.pro, .yearly): return .proYearly
        case (.pro, .monthly): return .proMonthly
        case (.creator, .yearly): return .creatorYearly
        case (.creator, .monthly): return .creatorMonthly
        default: return .proYearly
        }
    }

    /// Live yearly savings vs 12× monthly when StoreKit prices are available.
    private func yearlySavingsPercent(for tier: SubscriptionTier) -> Int? {
        let monthlyID: SceneMeProductID = tier == .pro ? .proMonthly : .creatorMonthly
        let yearlyID: SceneMeProductID = tier == .pro ? .proYearly : .creatorYearly
        guard
            let monthly = service.product(for: monthlyID)?.price,
            let yearly = service.product(for: yearlyID)?.price,
            monthly > 0
        else {
            return nil
        }

        let annualIfMonthly = monthly * 12
        guard annualIfMonthly > yearly else { return nil }
        let saved = ((annualIfMonthly - yearly) / annualIfMonthly) * 100
        return NSDecimalNumber(decimal: saved).intValue
    }

    // MARK: - Action

    private func subscribe(to productID: SceneMeProductID) async {
        if service.tier == productID.tier {
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
        case .generationLimitReached:
            return "You've used all your free\ngenerations this month."
        case .featureLocked(let feature, _):
            return "Unlock \(feature)\nwith SceneMe."
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
        case .featureLocked(_, let tier): return tier
        case .manualUpgrade: return .pro
        }
    }
}
