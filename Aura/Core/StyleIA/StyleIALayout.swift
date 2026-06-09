import SwiftUI
import UIKit

struct StyleIALayout {
    let size: CGSize

    var safeBottom: CGFloat {
        max(0, UIApplication.shared.connectedScenes
            .compactMap { scene in
                (scene as? UIWindowScene)?
                    .windows
                    .first(where: { $0.isKeyWindow })?
                    .safeAreaInsets
                    .bottom
            }
            .first ?? 0)
    }

    var sidePadding: CGFloat {
        min(max(size.width * 0.085, 22), 34)
    }

    var cardGap: CGFloat {
        size.width < 360 ? 8 : 12
    }

    var markSize: CGFloat {
        min(size.width * 0.62, size.height * 0.3, 250)
    }

    var analysisMarkSize: CGFloat {
        min(size.width * 0.7, size.height * 0.27, 270)
    }

    var avatarLarge: CGFloat {
        min(size.width * 0.32, 118)
    }

    var profileAvatarSize: CGFloat {
        min(size.width * 0.36, 132)
    }

    var personaAvatarHeight: CGFloat {
        size.height < 720 ? 78 : 98
    }

    var uploadHeight: CGFloat {
        min(max(size.height * 0.26, 210), 284)
    }

    var primaryButtonHeight: CGFloat {
        size.height < 720 ? 52 : 58
    }

    var secondaryButtonHeight: CGFloat {
        size.height < 720 ? 50 : 56
    }

    var brandSize: CGFloat {
        min(max(size.width * 0.15, 46), 64)
    }

    var heroTitleSize: CGFloat {
        min(max(size.width * 0.098, 34), 43)
    }

    var resultTitleSize: CGFloat {
        min(max(size.width * 0.075, 25), 32)
    }

    var ctaSize: CGFloat {
        size.width < 360 ? 15 : 17
    }

    var heightScale: CGFloat {
        min(max(size.height / 852, 0.78), 1.12)
    }

    func vertical(_ value: CGFloat) -> CGFloat {
        value * heightScale
    }

    var lookGridColumnCount: Int {
        if size.width >= 1_000 { return 4 }
        if size.width >= 700 { return 3 }
        return 2
    }

    var lookGridSpacing: CGFloat {
        size.width < 360 ? 10 : 12
    }

    var lookCardAspectRatio: CGFloat {
        3 / 4
    }

    var contentMaxWidth: CGFloat {
        min(size.width, 720)
    }

    var feedCardWidth: CGFloat {
        min(size.width - sidePadding * 2, 420)
    }

    var feedCardHeight: CGFloat {
        min(feedCardWidth * 0.74, size.height * 0.42, 340)
    }

    var topPickCardWidth: CGFloat {
        min(size.width - sidePadding * 2, 420)
    }

    func lookGridColumns() -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: lookGridSpacing, alignment: .top),
            count: lookGridColumnCount
        )
    }
}
