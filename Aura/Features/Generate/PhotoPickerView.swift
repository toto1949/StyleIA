import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

enum PermissionKind: Identifiable {
    case camera
    case photoLibrary
    case photoSave

    var id: String {
        switch self {
        case .camera: "camera"
        case .photoLibrary: "photoLibrary"
        case .photoSave: "photoSave"
        }
    }

    var title: String {
        switch self {
        case .camera: L10n.string("permission.camera.title")
        case .photoLibrary: L10n.string("permission.photos.title")
        case .photoSave: L10n.string("permission.save.title")
        }
    }

    var subtitle: String {
        switch self {
        case .camera: L10n.string("permission.camera.subtitle")
        case .photoLibrary: L10n.string("permission.photos.subtitle")
        case .photoSave: L10n.string("permission.save.subtitle")
        }
    }

    var systemImage: String {
        switch self {
        case .camera: "camera.fill"
        case .photoLibrary: "photo.on.rectangle.angled"
        case .photoSave: "square.and.arrow.down.fill"
        }
    }
}

struct PermissionPrimerView: View {
    let kind: PermissionKind
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(width: 92, height: 92)
                .background(DesignSystem.Colors.surfaceRaised)
                .clipShape(Circle())

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text(kind.title)
                    .font(Typography.titleLarge)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(kind.subtitle)
                    .font(Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            VStack(spacing: DesignSystem.Spacing.sm) {
                PrimaryButton(title: L10n.string("permission.continue"), action: onContinue)
                SecondaryButton(title: L10n.string("common.cancel"), action: onCancel)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .background(DesignSystem.Colors.primary.ignoresSafeArea())
    }
}

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1

        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        _ = uiViewController
        _ = context
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onImage: (UIImage) -> Void

        init(onImage: @escaping (UIImage) -> Void) {
            self.onImage = onImage
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                return
            }

            provider.loadObject(ofClass: UIImage.self) { [onImage] object, _ in
                guard let image = object as? UIImage else {
                    return
                }

                Task { @MainActor in
                    onImage(image)
                }
            }
        }
    }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> CameraViewController {
        CameraViewController { image in
            onImage(image)
            dismiss()
        } onCancel: {
            dismiss()
        }
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        _ = uiViewController
        _ = context
    }
}

final class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let onImage: (UIImage) -> Void
    private let onCancel: () -> Void

    init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.onImage = onImage
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black
        configureSession()
        configureControls()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input),
            session.canAddOutput(output)
        else {
            session.commitConfiguration()
            showUnavailableMessage()
            return
        }

        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)
        self.previewLayer = previewLayer
    }

    private func configureControls() {
        let captureButton = UIButton(type: .system)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.backgroundColor = UIColor.white
        captureButton.layer.cornerRadius = 34
        captureButton.layer.borderWidth = 4
        captureButton.layer.borderColor = UIColor.black.withAlphaComponent(0.25).cgColor
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)

        let cancelButton = UIButton(type: .system)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        cancelButton.tintColor = .white
        cancelButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        cancelButton.layer.cornerRadius = 22
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        view.addSubview(captureButton)
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            captureButton.widthAnchor.constraint(equalToConstant: 68),
            captureButton.heightAnchor.constraint(equalToConstant: 68),
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),

            cancelButton.widthAnchor.constraint(equalToConstant: 44),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])
    }

    private func showUnavailableMessage() {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = L10n.string("permission.camera.unavailable")
        label.textColor = .white
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 0
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    @objc private func cancel() {
        onCancel()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        _ = output
        guard
            error == nil,
            let data = photo.fileDataRepresentation(),
            let image = UIImage(data: data)
        else {
            return
        }

        onImage(image)
    }
}

#Preview {
    PermissionPrimerView(kind: .camera, onContinue: {}, onCancel: {})
}
