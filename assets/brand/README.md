# Brand assets

Masters that are not part of the app bundle. The shipped images live in
`OneCart/Resources/Assets.xcassets`.

| File | Role |
|------|------|
| `onecart-icon-classic.svg` | App icon master, default emerald theme |
| `onecart-icon-ocean.svg`, `onecart-icon-sunset.svg`, `onecart-icon-midnight.svg` | Alternate icon themes |
| `onecart-app-icon-1024.png` | Flattened classic icon at App Store size |
| `onecart-app-icon-master.png` | Flattened classic icon at 2048 px |
| `onecart-launch-master.png` | Launch chrome artwork |

## Icon design

A cream outline cart with an amber check mark breaking its rim, on a vertical
gradient. The check refers to the Completed state in the cart. The mark keeps
its silhouette at 60 px, which is what the Home Screen and Settings use.

Theme colors come from `AppAccentColor.swift`, so the icon and the in-app accent
stay in step. Sunset uses a brighter amber (`#FFC332`) because the default amber
sits too close to its orange background.

## Regenerating the raster sets

The SVG masters are the source. Each icon set is rendered from them with
ImageMagick (`brew install imagemagick`). ImageMagick's built-in SVG renderer
does not draw gradients, so the background is generated separately and the
foreground composited on top:

```bash
magick -size 1024x1024 gradient:'#3E9370-#285F47' bg.png
magick -background none -density 384 foreground.svg -resize 1024x1024 fg.png
magick bg.png fg.png -composite -alpha remove -colorspace sRGB classic-1024.png
```

Every entry in each `*.appiconset/Contents.json` is then resized from that
master, and the `IconPreview-*` imagesets used by the in-app picker are rendered
at 512 px.

## Icon Composer

The app still ships flat PNG icon sets. iOS 26 and later prefer a layered
Icon Composer (`.icon`) document, which lets the system apply Liquid Glass and
generate the dark, clear and tinted appearances instead of using the flat image
for all of them. Building that document is a manual Xcode step and has not been
done. The separated layers to import are kept outside this repository with the
design notes; the flattened SVGs here can also be re-separated into background,
cart and check.
