//
//  SearchRouter.swift
//  iTunesSearch
//

import UIKit

protocol SearchRoutingLogic: AnyObject {
    func routeToScreenshotPreview(url: URL)
}

final class SearchRouter: SearchRoutingLogic {
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
