# Authelia asset overrides

Files in this directory replace built-in Authelia branding assets when
`server.asset_path` points here (see `configuration.yml`).

Authelia's theming ceiling is intentionally low — only logo and favicon are
overridable. Deeper changes (colors, layout) require a fork.

## Supported files

| Filename       | Purpose                                                           |
| -------------- | ------------------------------------------------------------------|
| `logo.png`     | Shown above the login form. Recommended size: 256×256 transparent |
| `favicon.ico`  | Browser tab icon                                                  |

Drop the files in alongside this README and restart the Authelia container.

## Brand assets

Source SVGs live in `branding/` at the repo root. Render them to PNG/ICO at the
sizes above when you're ready to install. Quick recipe with ImageMagick:

```bash
magick branding/favicon.svg -resize 256x256 services/authelia/assets/logo.png
magick branding/favicon.svg -resize 64x64   services/authelia/assets/favicon.ico
```

If you don't have ImageMagick handy, use any SVG → PNG converter (or open in
Figma and export). The login page is the only public-facing surface Authelia
exposes, and a logo is the single highest-ROI change here.
