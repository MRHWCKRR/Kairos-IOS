# Kairos ambient sounds

Put local ambient audio files in this folder. Kairos currently looks for these basenames:

- `rain.mp3` (also m4a/wav)
- `forest.mp3` (also m4a/wav)
- `ocean.mp3` (also m4a/wav)

The Appearance screen's Ambient sound picker uses the matching filename. Audio loops while Focus is active/app is running and follows the saved volume setting.

If you add different sounds, the UI picker will need a matching option added in `AppearanceSettingsView.swift`.
