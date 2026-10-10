//
//  SearchViewController.swift
//  iTunesSearch
//

import SnapKit
import UIKit

final class SearchViewController: UIViewController {
    private let interactor: SearchBusinessLogic
    private let router: SearchRouter
    private let imageDownloader: ImageDownloader
    private var sections: [Search.FetchApps.AppSection] = []

    private let searchBar = UISearchBar()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private let stateView = UIContentUnavailableView(configuration: .empty())

    static func build(imageDownloader: ImageDownloader = .shared) -> SearchViewController {
        let presenter = SearchPresenter()
        let interactor = SearchInteractor(presenter: presenter, imageDownloader: imageDownloader)
        let router = SearchRouter(imageDownloader: imageDownloader)
        let viewController = SearchViewController(interactor: interactor, router: router, imageDownloader: imageDownloader)
        presenter.viewController = viewController
        router.viewController = viewController
        return viewController
    }

    init(interactor: SearchBusinessLogic, router: SearchRouter, imageDownloader: ImageDownloader) {
        self.interactor = interactor
        self.router = router
        self.imageDownloader = imageDownloader
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "App Search"
        view.backgroundColor = .systemBackground
        setUpSearchBar()
        setUpCollectionView()
        displaySearch(viewModel: .idle)
    }

    // MARK: Setup

    private func setUpSearchBar() {
        searchBar.placeholder = "Search apps"
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none
        searchBar.returnKeyType = .search
        searchBar.delegate = self

        view.addSubview(searchBar)
        searchBar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(8)
        }
    }

    private func setUpCollectionView() {
        collectionView.backgroundColor = .systemBackground
        collectionView.backgroundView = stateView
        collectionView.keyboardDismissMode = .onDrag
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ScreenshotCell.self, forCellWithReuseIdentifier: ScreenshotCell.reuseIdentifier)
        collectionView.register(NoScreenshotsCell.self, forCellWithReuseIdentifier: NoScreenshotsCell.reuseIdentifier)
        collectionView.register(
            AppHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: AppHeaderView.reuseIdentifier
        )

        // Keeps the state view centered above the keyboard while typing.
        view.keyboardLayoutGuide.usesBottomSafeArea = false

        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(searchBar.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
        }
    }

    // MARK: Layout

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.interSectionSpacing = 4

        return UICollectionViewCompositionalLayout(sectionProvider: { [weak self] index, _ in
            let appSection = self.flatMap { index < $0.sections.count ? $0.sections[index] : nil }
            let section: NSCollectionLayoutSection
            if let appSection, !appSection.screenshotURLs.isEmpty {
                section = Self.makeScreenshotsSection(landscape: appSection.usesLandscapeScreenshots)
            } else {
                section = Self.makeNoScreenshotsSection()
            }
            section.boundarySupplementaryItems = [
                NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(64)),
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top
                ),
            ]
            return section
        }, configuration: configuration)
    }

    /// Portrait rows use a 9:16 cell, landscape rows a 16:9 cell, matching typical App Store screenshots.
    private static func makeScreenshotsSection(landscape: Bool) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1))
        )
        let size = landscape ? CGSize(width: 288, height: 162) : CGSize(width: 135, height: 240)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(size.width), heightDimension: .absolute(size.height)),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = 10
        section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 16, bottom: 20, trailing: 16)
        return section
    }

    private static func makeNoScreenshotsSection() -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(72))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 16, bottom: 20, trailing: 16)
        return section
    }

    // MARK: State

    private func stateConfiguration(for viewModel: Search.FetchApps.ViewModel) -> UIContentUnavailableConfiguration? {
        switch viewModel {
        case .results:
            return nil
        case .idle:
            var configuration = UIContentUnavailableConfiguration.empty()
            configuration.image = UIImage(systemName: "magnifyingglass")
            configuration.text = "Search the App Store"
            configuration.secondaryText = "Find apps and browse their screenshots."
            return configuration
        case .loading:
            var configuration = UIContentUnavailableConfiguration.loading()
            configuration.text = "Searching…"
            return configuration
        case .empty(let message):
            var configuration = UIContentUnavailableConfiguration.empty()
            configuration.image = UIImage(systemName: "magnifyingglass")
            configuration.text = "No Results"
            configuration.secondaryText = message
            return configuration
        case .error(let message):
            var configuration = UIContentUnavailableConfiguration.empty()
            configuration.image = UIImage(systemName: "exclamationmark.triangle")
            configuration.text = "Search Failed"
            configuration.secondaryText = message
            var button = UIButton.Configuration.borderedProminent()
            button.title = "Retry"
            configuration.button = button
            configuration.buttonProperties.primaryAction = UIAction { [weak self] _ in
                self?.interactor.retry()
            }
            return configuration
        }
    }
}

// MARK: - SearchDisplayLogic

extension SearchViewController: SearchDisplayLogic {
    func displaySearch(viewModel: Search.FetchApps.ViewModel) {
        if case .results(let sections) = viewModel {
            self.sections = sections
        } else {
            sections = []
        }

        if let configuration = stateConfiguration(for: viewModel) {
            stateView.configuration = configuration
            stateView.isHidden = false
        } else {
            stateView.isHidden = true
        }

        collectionView.reloadData()
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: false)
    }
}

// MARK: - UISearchBarDelegate

extension SearchViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        interactor.search(request: .init(term: searchText))
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - UICollectionViewDelegate

extension SearchViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        !sections[indexPath.section].screenshotURLs.isEmpty
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        searchBar.resignFirstResponder()
        router.routeToScreenshotPreview(url: sections[indexPath.section].screenshotURLs[indexPath.item])
    }
}

// MARK: - UICollectionViewDataSource

extension SearchViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        max(sections[section].screenshotURLs.count, 1)
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let section = sections[indexPath.section]

        guard !section.screenshotURLs.isEmpty else {
            return collectionView.dequeueReusableCell(withReuseIdentifier: NoScreenshotsCell.reuseIdentifier, for: indexPath)
        }

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ScreenshotCell.reuseIdentifier, for: indexPath) as! ScreenshotCell
        cell.configure(
            with: section.screenshotURLs[indexPath.item],
            imageDownloader: imageDownloader,
            accessibilityLabel: "\(section.title) screenshot \(indexPath.item + 1) of \(section.screenshotURLs.count)"
        )
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: AppHeaderView.reuseIdentifier,
            for: indexPath
        ) as! AppHeaderView
        let section = sections[indexPath.section]
        header.configure(title: section.title, subtitle: section.subtitle, showsSeparator: indexPath.section > 0)
        return header
    }
}
