# Devin Smells Of Dog Farts and Soup 🐕💨🍲

A gag website dedicated to the undeniable truth: Devin smells of dog farts and soup.

## What Is This?

A single-page static website that displays a chaotic collage of photos of Devin, interspersed with juvenile references to dog farts and soup. It's deliberately absurd and built to embarrass one specific Devin — my brother.

## Prerequisites

- **Python 3.10+** (stdlib only — no pip dependencies)
- **AWS CLI v2** (configured with credentials for deploy)

## Architecture

The entire site is a **single self-contained HTML file** (`index.html`). All assets — HTML, CSS, JavaScript, images, and fart sounds — are bundled into one file. Images are base64-encoded data URIs. Fart sounds are programmatically generated WAVs, also base64-encoded.

### Why a Single File?

- **Cheap AWS hosting**: Served via **S3 + CloudFront CDN** for pennies a month.
- **Zero backend**: No server, no database, no Lambda — just a static file on a CDN.
- **Fast globally**: CloudFront edge caching means Devin's shame loads quickly worldwide.

## AWS Deployment

### Infrastructure

| Service | Purpose |
|---|---|
| **S3** | Stores `index.html` (static website hosting enabled) |
| **CloudFront** | CDN distribution — caches and serves the file globally |
| **Route 53** | *(Optional)* Custom domain, e.g. `devinsmellsofdogfartsandsoup.com` |
| **ACM** | *(Optional)* Free SSL certificate for HTTPS |

### Estimated Cost

- **S3 storage**: ~$0.00 (one file, a few MB)
- **CloudFront**: Free tier covers 1 TB/month of transfer and 10M requests
- **Total**: Effectively **$0/month** unless this goes mega-viral (in which case, worth it)

### Deploy Steps

1. **Build the site**:
   ```bash
   python build.py
   ```
2. **First-time domain setup** (creates S3 bucket, CloudFront distribution, ACM cert, Route 53 zone):
   ```bash
   # Edit BUCKET_NAME, DOMAIN_NAME in setup-domain.sh first
   bash setup-domain.sh
   ```
   Then update your domain registrar's nameservers as instructed.
3. **Deploy updates** (upload + cache invalidation):
   ```bash
   # Edit DISTRIBUTION_ID in deploy.sh first (printed by setup-domain.sh)
   bash deploy.sh
   ```

## Project Structure

```
├── readme.md              # You are here
├── .gitignore             # Ignores generated index.html
├── pics/                  # Drop Devin photos here (jpg, jpeg, png, gif, webp)
├── build.py               # Build script — encodes images, generates sounds, outputs index.html
├── deploy.sh              # Upload to S3 + invalidate CloudFront cache
├── setup-domain.sh        # One-time: ACM cert, Route 53, CloudFront distribution
├── src/
│   └── template.html      # HTML/CSS/JS template (images/sounds injected at build time)
└── index.html             # Generated output (gitignored) — the single deployable file
```

## Adding Photos

1. Drop images of Devin into the `pics/` folder.
2. Supported formats: `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`
3. Run the build script to regenerate the site.

## Building

```bash
python build.py
```

This will:
- Scan `pics/` for `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp` files
- Base64-encode each image into data URIs
- Programmatically generate 5 fart sound WAV files and base64-encode them
- Inject everything into `src/template.html`
- Output a single `index.html` ready for deployment
- Print file size summary (warns if >10 MB)

> **Tip:** For faster page loads, resize photos to ~800px wide before building.

## The Site

The page features:

- **Hero section** with pulsing title and rotating taglines ("A fact. Not an opinion.", "Science has confirmed it.", etc.)
- **Photo collage** — Polaroid-style frames at random angles with captions ("Exhibit A", "Caught in 4K"). Hover triggers wobble + 💨 burst
- **15 floating emojis** (🐕💨🍲🥣💩🤢) continuously drifting across the screen via CSS animations
- **Scrolling text banners** — "WHY DOES DEVIN SMELL LIKE DOG FARTS?" and friends, slow-drifting behind content
- **Smell Rating Generator** — button generates random "73% dog fart / 27% minestrone" with animated progress bar. 12 soup types, 8 fart descriptors
- **Fart Soundboard** — 5 buttons (The Silent But Deadly, The Wet One, The Squeaker, The Foghorn, Soup Bubble) with synthesized audio, ripple effect, and emoji explosion on click
- **Wall of Shame** — scroll-revealed fake testimonials from "Mom", "Dad", "Probably Real Scientists", etc.
- **Parallax background** — subtle depth effect on scroll
- **Responsive design** — mobile-friendly grid reflow, touch-friendly buttons
- **`prefers-reduced-motion` support** — respects accessibility preferences

## Tech Stack

- **HTML5** / **CSS3** / **Vanilla JS** — no frameworks, no dependencies
- **Python** build script for image encoding and template generation
- **AWS S3 + CloudFront** for hosting

## License

This project is licensed under the **Devin Smells Public License (DSPL)** — you may freely use, modify, and redistribute this code, provided you acknowledge that Devin smells of dog farts and soup.
