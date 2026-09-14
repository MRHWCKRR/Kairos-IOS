# Kairos ambient sounds

Put bundled focus audio files in this folder.

## Recommended format

- `.mp3` or `.m4a`
- Short seamless loops work best.
- Keep files reasonably compressed for an iOS app bundle.

## Suggested names

Use stable lowercase names matching the Appearance setting values:

- `rain.mp3`
- `forest.mp3`
- `ocean.mp3`

`none` intentionally has no asset.

The Appearance settings currently persist the selected sound and volume. Playback wiring should resolve these names from `Bundle.main` when the Focus Timer audio layer is implemented.
