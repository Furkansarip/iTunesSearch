//
//  ScreenshotPreviewViewController.swift
//  iTunesSearch
//

import SnapKit
import UIKit

final class ScreenshotPreviewViewController: UIViewController {
    private let url: URL
    private let imageDownloader: ImageDownloader
    private var loadTask: Task<Void, Never>?

    private let imageView = UIImageView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let failureView = UIContentUnavailableView(configuration: .empty())
    private lazy var closeButton = UIButton(
        configuration: Self.closeButtonConfiguration(),
        primaryAction: UIAction { [weak self] _ in self?.close() }
    )

    init(url: URL, imageDownloader: ImageDownloader) {
        self.url = url
        self.imageDownloader = imageDownloader
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black
        setUpViews()
        loadImage()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Stops only this controller's wait; the shared download continues for other consumers.
        loadTask?.cancel()
    }

    // MARK: Setup

    private func setUpViews() {
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Screenshot"

        activityIndicator.hidesWhenStopped = true

        var failure = UIContentUnavailableConfiguration.empty()
        failure.image = UIImage(systemName: "exclamationmark.triangle")
        failure.text = "Couldn't Load Screenshot"
        failure.secondaryText = "Check your connection and try again later."
        failureView.configuration = failure
        failureView.isHidden = true

        view.addSubview(imageView)
        view.addSubview(activityIndicator)
        view.addSubview(failureView)
        view.addSubview(closeButton)

        imageView.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
        // Overlay: the button floats above the image and does not affect its layout.
        closeButton.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(8)
            make.trailing.equalTo(view.safeAreaLayoutGuide).inset(16)
            make.height.equalTo(36)
        }
        activityIndicator.snp.makeConstraints { $0.center.equalTo(imageView) }
        failureView.snp.makeConstraints { $0.edges.equalTo(imageView) }
    }

    private static func closeButtonConfiguration() -> UIButton.Configuration {
        var configuration = UIButton.Configuration.gray()
        configuration.title = "Close"
        configuration.image = UIImage(systemName: "xmark")
        configuration.imagePadding = 6
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .footnote, scale: .medium)
        configuration.cornerStyle = .capsule
        return configuration
    }

    // MARK: Loading

    private func loadImage() {
        if let cached = imageDownloader.cachedImage(for: url) {
            imageView.image = cached
            return
        }

        activityIndicator.startAnimating()
        loadTask = Task { [weak self, url, imageDownloader] in
            do {
                let image = try await imageDownloader.image(for: url)
                guard let self, !Task.isCancelled else { return }
                self.activityIndicator.stopAnimating()
                self.imageView.image = image
            } catch is CancellationError {
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.activityIndicator.stopAnimating()
                self.failureView.isHidden = false
            }
        }
    }

    private func close() {
        loadTask?.cancel()
        dismiss(animated: true)
    }
}
