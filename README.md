# iTunesSearch

A UIKit-based iOS application that searches for apps using the iTunes Search API and displays their screenshots in horizontally scrollable galleries.

## Demo
https://github.com/user-attachments/assets/09fa098f-298b-480d-8dd1-568ba9e48926

## Features

- Live app search with 350 ms debounce
- Search cancellation and stale-response protection
- Horizontally scrollable screenshot galleries
- Full-screen screenshot preview
- Asynchronous image loading and in-memory caching
- Maximum of three concurrent image downloads
- Loading, empty, and error states

## Architecture & Tech Stack

- **Language:** Swift 6
- **UI:** UIKit, programmatic layout, SnapKit
- **Architecture:** Clean Swift (VIP)
- **Concurrency:** Swift Concurrency (`async/await`, actors, tasks)
- **Networking:** URLSession
- **Image caching:** NSCache
- **Minimum deployment target:** iOS 17.0

The application follows the VIP pattern to separate business logic, presentation, and UI responsibilities.

Image downloading is managed by an actor that coordinates concurrent requests, caching, and cancellation.

## Getting Started

1. Clone the repository.
2. Open `iTunesSearch.xcodeproj` in Xcode 26 or later.
3. Select an iOS simulator.
4. Build and run the application.

No API key is required.

## Tests

The project includes unit tests covering search behavior, response mapping, networking, and image downloading, including concurrency limits and cancellation scenarios.

Run the tests using **Product → Test** in Xcode.
