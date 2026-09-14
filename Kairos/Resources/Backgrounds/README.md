# Kairos backgrounds

Put bundled background images in this folder.

## Recommended format

- `.jpg`, `.jpeg`, `.png`, or `.heic`
- Prefer iPhone-friendly dimensions and compressed files.
- Avoid huge source images; they increase app size and memory use.

## Suggested names

Use stable lowercase names matching the Appearance setting values where applicable:

- `gradient` is the built-in Kairos gradient and does not need an image.
- `minimal` is the built-in minimal treatment and does not need an image.
- Custom image assets can use names such as `study-room.jpg` and be mapped by the background layer later.

The current Appearance settings persist the background choice and optional custom URL. Local bundled-image playback/rendering is intentionally kept separate from this settings UI so the visual layer can be wired without changing the settings schema.
