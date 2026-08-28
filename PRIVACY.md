# Snapwell Privacy Policy

**Last updated:** August 28, 2026

Snapwell is a local-first media library app. Your privacy is fundamental to how Snapwell is built.

## Data Storage

All your media files, metadata, and thumbnails are stored on your devices and your personal iCloud Drive — not on our servers. Snapwell does not operate any backend infrastructure and has no access to your data.

- **Media files** are stored in `~/Documents/Snapwell/` (Mac) or your iCloud Drive container (iOS).
- **App preferences** are stored locally using UserDefaults on your device.
- **API keys** you provide are stored locally on your Mac and optionally synced to your iOS device via your iCloud Drive using AES-GCM encryption.

## AI Analysis (Optional)

If you choose a cloud AI provider, Snapwell sends your images directly to that provider using your own API key:

- **OpenAI** (api.openai.com)
- **Anthropic** (api.anthropic.com)
- **Google Gemini** (generativelanguage.googleapis.com)
- **OpenRouter** (openrouter.ai)

Images and sampled video frames are sent directly from your device to the provider's API using your personal API key. Snapwell does not proxy, store, or have access to this data in transit. Each provider's own privacy policy governs how they handle your data.

On Mac, you can instead choose Ollama. Snapwell then sends images and sampled video frames only to Ollama running at `localhost` on that Mac. Items saved on iOS remain unanalyzed until they sync to the Mac. Ollama models are installed and managed separately by you.

You can disable cloud analysis by removing your API key, or disable local analysis by choosing another provider or stopping Ollama.

## Data Collection

Snapwell collects **no analytics, telemetry, or usage data**. There are:

- No crash reporting SDKs
- No analytics frameworks
- No advertising identifiers
- No user tracking of any kind

## Third-Party Services

Snapwell does not include any third-party SDKs. All network requests are made using Apple's built-in frameworks (URLSession) directly to the services listed above or to Ollama on your Mac, only when you explicitly configure them.

When importing media from X/Twitter URLs, Snapwell accesses Twitter's public syndication API to retrieve the media you requested.

## iCloud Sync

Snapwell uses your personal iCloud Drive to sync media and settings between your Mac and iOS devices. This sync happens entirely through Apple's iCloud infrastructure using your Apple Account. Snapwell has no server-side component and cannot access your iCloud data.

## Children's Privacy

Snapwell is not directed at children under 13 and does not knowingly collect personal information from children.

## Changes

We may update this policy from time to time. The latest version will always be available at [snapwell.co/privacy](https://snapwell.co/privacy).

## Contact

If you have questions about this privacy policy, send us a message using the chat widget at [snapwell.co](https://snapwell.co).
