//
//  SearchViewController.swift
//  iTunesSearch
//

import SnapKit
import UIKit

final class SearchViewController: UIViewController {
    private let interactor: SearchBusinessLogic
    private let imageDownloader: ImageDownloader
    private var sections: [Search.FetchApps.AppSection] = []

    private let searchBar = UISearchBar()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private let stateView = UIContentUnavailableView(configuration: .empty())

    static func build(imageDownloader: ImageDownloader = .shared) -> SearchViewController {
        let presenter = SearchPresenter()
        let router = SearchRouter(imageDownloader: imageDownloader)
        let interactor = SearchInteractor(presenter: presenter, router: router, imageDownloader: imageDownloader)
        let viewController = SearchViewController(interactor: interactor, imageDownloader: imageDownloader)
        presenter.viewController = viewController
        router.viewController = viewController
        return viewController
    }

    init(interactor: SearchBusinessLogic, imageDownloader: ImageDownloader) {
        self.interactor = interactor
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
        collectionView.prefetchDataSource = self
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
            if let appSection, !appSection.screenshots.isEmpty {
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

    func displayFavorite(viewModel: Search.ToggleFavorite.ViewModel) {
        let indexPath = IndexPath(item: viewModel.itemIndex, section: viewModel.sectionIndex)
        guard item(at: indexPath)?.id == viewModel.item.id else { return }
        sections[indexPath.section].screenshots[indexPath.item] = viewModel.item
        collectionView.reconfigureItems(at: [indexPath])
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
        item(at: indexPath) != nil
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard let item = item(at: indexPath) else { return }
        searchBar.resignFirstResponder()
        interactor.selectScreenshot(request: .init(screenshot: item.id))
    }

    /// Index paths are only used to look up the currently displayed item; requests carry its identity.
    private func item(at indexPath: IndexPath) -> Search.ScreenshotItemViewModel? {
        guard sections.indices.contains(indexPath.section),
              sections[indexPath.section].screenshots.indices.contains(indexPath.item)
        else { return nil }
        return sections[indexPath.section].screenshots[indexPath.item]
    }
}

// MARK: - UICollectionViewDataSourcePrefetching

extension SearchViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        interactor.prefetchScreenshots(request: .init(screenshots: indexPaths.compactMap { item(at: $0)?.id }))
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        interactor.cancelScreenshotPrefetching(request: .init(screenshots: indexPaths.compactMap { item(at: $0)?.id }))
    }
}

// MARK: - UICollectionViewDataSource

extension SearchViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        max(sections[section].screenshots.count, 1)
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let item = item(at: indexPath) else {
            return collectionView.dequeueReusableCell(withReuseIdentifier: NoScreenshotsCell.reuseIdentifier, for: indexPath)
        }

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ScreenshotCell.reuseIdentifier, for: indexPath) as! ScreenshotCell
        cell.configure(with: item, imageDownloader: imageDownloader)
        let screenshot = item.id
        cell.onToggleFavorite = { [weak self] in
            self?.interactor.toggleFavorite(request: .init(screenshot: screenshot))
        }
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
