//
//  NoScreenshotsCell.swift
//  iTunesSearch
//

import SnapKit
import UIKit

final class NoScreenshotsCell: UICollectionViewCell {
    static let reuseIdentifier = "NoScreenshotsCell"

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous

        let iconView = UIImageView(image: UIImage(systemName: "photo.on.rectangle.angled"))
        iconView.tintColor = .tertiaryLabel
        iconView.contentMode = .scaleAspectFit

        let label = UILabel()
        label.text = "No screenshots available"
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.spacing = 8
        stack.alignment = .center

        contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().inset(16)
        }

        isAccessibilityElement = true
        accessibilityLabel = label.text
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
