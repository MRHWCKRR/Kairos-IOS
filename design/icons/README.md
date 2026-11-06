# Shared Kairos icons

Both apps vendor the same 77 MIT Phosphor SVGs and semantic manifest. Source hashes pin the exact artwork; iOS template assets and Android ImageVectors use the same path data. Apple SF Symbols are not distributed.

Android: run `node tools/generate-icons.cjs` after updating the SVGs/manifest; run `node tools/check-icons.cjs` to check generation, hashes and call sites.

iOS: run `node Tools/check-icons.cjs` to verify every semantic mapping and byte-identical template asset in the app and both widget source roots. Copy updated SVG bytes to the corresponding imagesets and update each target's KairosIconCatalog together with the manifest.

Keep these sources identical in Kairos-Android and Kairos-IOS. The manifest's SHA256 values make drift explicit in review. Android-only alias names are in android-aliases.json. The upstream MIT notice is PHOSPHOR-LICENSE.txt.
