# Snapwell — Collect images, let AI organize them.

A local-first image library for macOS and iOS — drop in screenshots, references, inspiration, and video. Snapwell categorizes everything, makes it searchable, and syncs across your devices.

![Snapwell Preview](assets/preview.png)

Built by [@gustavscirulis](https://github.com/gustavscirulis).

## Use cases

- **UI & design references** — Screenshot interfaces, collect patterns, track visual systems. AI tags and categorizes so you can search by what's in the image, not what you named the file
- **Project inspiration** — Planning a renovation, picking furniture, collecting style references. Organize into spaces per project and let AI surface connections
- **Mood boards & curation** — Gather visual inspiration from anywhere — drag in images, paste from the web, import from X/Twitter. AI groups and tags automatically
- **Design systems** — Capture component states, track UI patterns across products, maintain a visual inventory

## Features

- **Local-first storage** — All images, metadata, and preferences stay on your device
- **AI-powered analysis** — Categorize and tag using OpenAI, Claude, Google Gemini, or OpenRouter with your own API key
- **Custom analysis prompts** — Configure AI instructions per space for tailored categorization
- **Spaces** — Organize images into collections with drag-and-drop and per-space export
- **Search by content** — Find images based on what AI detected in them, not filenames
- **iCloud sync** — Sync your library between Mac and iOS
- **iOS Share Extension** — Send images and videos to Snapwell from any app
- **Video support** — Import and analyze video alongside images

## Installation

Download the latest release from the [Releases](https://github.com/gustavscirulis/snapwell/releases) page, or build from source.

## Requirements

AI analysis requires an API key for at least one provider: OpenAI, Anthropic (Claude), Google Gemini, or OpenRouter. Add your key in Settings and pick your preferred model. The app works without AI too — you just won't get automatic tagging and search.

## Privacy

Snapwell has no servers and collects no data. If you enable AI analysis, images are sent directly from your device to the provider you chose. See [PRIVACY.md](PRIVACY.md) for details.

## File storage

Snapwell stores files in `~/Documents/Snapwell/` or iCloud Drive:

- `images/` — Media files (PNG, MP4, etc.)
- `metadata/` — JSON sidecar for each media item
- `thumbnails/` — Generated thumbnails
- `spaces.json` — Space definitions and AI prompt configuration
- `.trash/` — Deleted items (auto-emptied after 30 days)
- `queue/` — iOS import staging, auto-watched by the Mac app

## Development

Snapwell is built with Swift 6, SwiftUI, and SwiftData. The Mac app uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation.

### macOS

```sh
cd macos
xcodegen generate
open Snapwell.xcodeproj
```

### iOS

```sh
open ios/Snapwell.xcodeproj
```

### Running tests

```sh
# Mac
cd macos && xcodegen generate && xcodebuild test \
  -project Snapwell.xcodeproj -scheme Snapwell \
  -destination 'platform=macOS' 2>&1 | xcbeautify --quiet

# iOS
cd ios && xcodebuild test \
  -project Snapwell.xcodeproj -scheme Snapwell \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | xcbeautify --quiet
```

## Contributing

Contributions welcome — open a Pull Request or file an issue.

## License

This project is licensed under the GNU General Public License v3.0 — see [LICENSE](LICENSE) for details. As an additional permission under GPL-3.0 section 7, this software may be distributed through the Apple App Store.

## Acknowledgments

- Built entirely with [Claude Code](https://claude.ai/code) by Anthropic
- App icon by [Midjourney](https://www.midjourney.com/)
- AI analysis powered by [OpenAI](https://openai.com/), [Anthropic](https://anthropic.com/), [Google Gemini](https://deepmind.google/technologies/gemini/), and [OpenRouter](https://openrouter.ai/)
