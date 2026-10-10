//
//  SearchRouter.swift
//  iTunesSearch
//

import UIKit

final class SearchRouter {
    weak var viewController: UIViewController?
    private let imageDownloader: ImageDownloader

    init(imageDownloader: ImageDownloader) {
        self.imageDownloader = imageDownloader
    }

    func routeToScreenshotPreview(url: URL) {
        let preview = ScreenshotPreviewViewController(url: url, imageDownloader: imageDownloader)
        preview.modalPresentationStyle = .fullScreen
        viewController?.present(preview, animated: true)
    }
}
