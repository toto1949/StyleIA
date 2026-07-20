import SwiftUI
import UIKit

/// Pinch-to-zoom + pan via UIScrollView so any region of the image can be inspected,
/// not only a center-anchored scaleEffect.
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    var minZoom: CGFloat = 1
    var maxZoom: CGFloat = 4
    var onSingleTap: (() -> Void)?
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(minZoom: minZoom, maxZoom: maxZoom, onSingleTap: onSingleTap)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = maxZoom
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false

        let hosted = context.coordinator.hostingController
        hosted.view.backgroundColor = .clear
        hosted.view.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 16.4, *) {
            hosted.safeAreaRegions = []
        }
        scrollView.addSubview(hosted.view)

        NSLayoutConstraint.activate([
            hosted.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hosted.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hosted.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hosted.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hosted.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hosted.view.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap(_:))
        )
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.hostingController.rootView = AnyView(content())
        context.coordinator.hostingController.view.setNeedsLayout()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var minZoom: CGFloat
        var maxZoom: CGFloat
        var onSingleTap: (() -> Void)?
        weak var scrollView: UIScrollView?
        let hostingController = UIHostingController(rootView: AnyView(EmptyView()))

        init(minZoom: CGFloat, maxZoom: CGFloat, onSingleTap: (() -> Void)?) {
            self.minZoom = minZoom
            self.maxZoom = maxZoom
            self.onSingleTap = onSingleTap
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Keep zoomed content centered when smaller than the viewport.
            let boundsSize = scrollView.bounds.size
            let contentSize = scrollView.contentSize
            let offsetX = max((boundsSize.width - contentSize.width) * 0.5, 0)
            let offsetY = max((boundsSize.height - contentSize.height) * 0.5, 0)
            hostingController.view.center = CGPoint(
                x: contentSize.width * 0.5 + offsetX,
                y: contentSize.height * 0.5 + offsetY
            )
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > minZoom + 0.01 {
                scrollView.setZoomScale(minZoom, animated: true)
                return
            }

            let point = gesture.location(in: hostingController.view)
            let target = min(maxZoom, 2.5)
            let width = scrollView.bounds.width / target
            let height = scrollView.bounds.height / target
            let rect = CGRect(
                x: point.x - width / 2,
                y: point.y - height / 2,
                width: width,
                height: height
            )
            scrollView.zoom(to: rect, animated: true)
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            onSingleTap?()
        }
    }
}
