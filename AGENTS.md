# Repository Guidelines

This repository contains a SwiftUI app managed with Xcode. Use this guide to keep structure, style, and workflows consistent.

## Project Structure & Module Organization

- `chatGLM/`: App sources (`chatGLMApp.swift`, `ContentView.swift`, models such as `Item.swift`).
- `chatGLM/Assets.xcassets`: Images, app icons, and color assets.
- `chatGLM.xcodeproj`: Xcode project; create and organize new files through Xcode, stored under `chatGLM/`.

## Build, Test, and Development Commands

- Open in Xcode: `open chatGLM.xcodeproj`.
- Build & run: use the `chatGLM` scheme from Xcode (⌘R) targeting the desired simulator or device.
- CLI build example: `xcodebuild -scheme chatGLM -destination 'platform=iOS Simulator,name=iPhone 15' build`.
- CLI tests (when tests exist): `xcodebuild test -scheme chatGLM -destination 'platform=iOS Simulator,name=iPhone 15'`.

## Coding Style & Naming Conventions

- Language: Swift 5, SwiftUI; 4-space indentation, spaces not tabs.
- Types and views use `UpperCamelCase`; variables, functions, and properties use `lowerCamelCase`.
- Prefer `struct` over `class` for views and value-like models.
- Name files after the primary type (e.g., `ChatView.swift` for `ChatView`); use `// MARK:` to group related members.

## Testing Guidelines

- Use `XCTest` with test classes ending in `Tests` (e.g., `ChatViewModelTests`).
- Place unit tests in `chatGLMTests/` and UI tests in `chatGLMUITests/` (create these targets if absent).
- Run tests via Xcode (⌘U) or the `xcodebuild test` command above.
- Add or update tests for new features, bug fixes, and non-trivial logic.

## Commit & Pull Request Guidelines

- Write concise, imperative commit messages (e.g., `Add chat history persistence`).
- Keep each commit focused on a coherent change; avoid mixing unrelated updates.
- PRs should include a clear summary, motivation, testing notes, and screenshots or screen recordings for visible UI changes.
- Reference related issues or tasks in the PR description when applicable.

## Security & Configuration Tips

- Never commit secrets, API keys, or personal tokens; prefer configuration files or environment-based settings excluded via `.gitignore`.
- Avoid committing user-specific Xcode settings or derived data; rely on the shared project configuration.

## Agent-Specific Instructions

- When editing this repository programmatically, preserve the existing Swift style and structure.
- Minimize unrelated changes, and do not alter bundle identifiers, signing settings, or deployment targets unless explicitly required.

