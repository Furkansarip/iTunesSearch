//
//  ScreenshotCell.swift
//  iTunesSearch
//

import SnapKit
import UIKit

final class ScreenshotCell: UICollectionViewCell {
    static let reuseIdentifier = "ScreenshotCell"

    private let imageView = UIImageView()
    private let statusImageView = UIImageView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    private var configurationGeneration = 0
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true

        imageView.contentMode = .scaleAspectFit

        statusImageView.image = UIImage(systemName: "exclamationmark.triangle")
        statusImageView.tintColor = .tertiaryLabel
        statusImageView.contentMode = .scaleAspectFit

        activityIndicator.hidesWhenStopped = true

        contentView.addSubview(imageView)
        contentView.addSubview(statusImageView)
        contentView.addSubview(activityIndicator)

        imageView.snp.makeConstraints { $0.edges.equalToSuperview() }
        statusImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(28)
        }
        activityIndicator.snp.makeConstraints { $0.center.equalToSuperview() }

        isAccessibilityElement = true
        accessibilityTraits = .image
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelLoad()
        showEmpty()
    }

    func configure(with url: URL, imageDownloader: ImageDownloader, accessibilityLabel: String) {
        self.accessibilityLabel = accessibilityLabel
        cancelLoad()
        let generation = configurationGeneration

        if let cached = imageDownloader.cachedImage(for: url) {
            show(image: cached)
            return
        }

        showLoading()
        loadTask = Task { [weak self] in
            do {
                let image = try await imageDownloader.image(for: url)
                guard let self, self.isCurrent(generation) else { return }
                self.show(image: image)
            } catch is CancellationError {
            } catch {
                guard let self, self.isCurrent(generation) else { return }
                self.showFailure()
            }
        }
    }

    /// Invalidates any in-flight load: its completion will no longer match the generation.
    private func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        configurationGeneration += 1
    }

    /// The same URL can be configured repeatedly, so only the latest, non-cancelled load may update the cell.
    private func isCurrent(_ generation: Int) -> Bool {
        !Task.isCancelled && generation == configurationGeneration
    }

    private func showEmpty() {
        imageView.image = nil
        statusImageView.isHidden = true
        activityIndicator.stopAnimating()
    }

    private func showLoading() {
        imageView.image = nil
        statusImageView.isHidden = true
        activityIndicator.startAnimating()
    }

    private func show(image: UIImage) {
        imageView.image = image
        statusImageView.isHidden = true
        activityIndicator.stopAnimating()
    }

    private func showFailure() {
        imageView.image = nil
        statusImageView.isHidden = false
        activityIndicator.stopAnimating()
    }
}
