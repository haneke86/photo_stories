# Onboarding Background Image — ChatGPT DALL-E Prompts

## Shared Style Suffix (append to any prompt if needed)

> Style: dark moody atmospheric, cinematic lighting, portrait orientation (9:19.5 aspect ratio for iPhone), deep navy-black base color (#080a14), accent colors teal and lavender, center area kept dark and minimal for white text overlay, no text or UI elements in the image, premium mobile app background quality, high resolution.

---

## Page 1: "Your Travel Timeline"

**Asset name:** `onboarding_timeline`

### Option A — Aerial Globe View
```
A dark, atmospheric vertical portrait image of Earth seen from a high aerial perspective at night, showing scattered city lights glowing in warm tones across continents. The globe curves gently at the bottom of the frame. The upper portion fades into deep navy-black space. Soft teal and lavender light gradients wash across the atmosphere at the horizon. The center of the image is intentionally soft and dark to allow white text overlay. Cinematic, moody, premium travel app aesthetic. No text, no UI elements, no watermarks. Photorealistic, high resolution.
```

### Option B — World Map with Pins
```
A dark moody vertical portrait image showing a stylized world map from above, with soft glowing pin-point lights marking various cities across Europe, Asia, and the Americas. The map is rendered in deep navy and charcoal tones with subtle topographic texture. Faint connecting lines between the pins form travel routes, glowing in soft teal (#4DD9C0). The center is intentionally dark and blurred for text overlay. Edges have more visual detail — coastlines, mountain textures. Atmospheric, cinematic lighting. No text, no labels, no UI elements. Premium quality, suitable as a mobile app background.
```

---

## Page 2: "AI-Powered Trip Stories"

**Asset name:** `onboarding_stories`

### Option A — Open Book with Travel Scenes
```
A dark, atmospheric vertical portrait image evoking travel storytelling. An ethereal, softly glowing open book floats in a deep navy-black void, with faint wisps of light rising from its pages like memories materializing. The wisps subtly suggest travel scenes — a distant cityscape silhouette, mountain outlines, a coastline — all rendered as translucent, dreamlike forms in teal and warm lavender tones. The center of the image is soft and dark for text overlay. Moody, cinematic, magical realism style. No text on the book or anywhere in the image. No UI elements. Premium quality mobile wallpaper aesthetic.
```

### Option B — Collage of Travel Memories
```
A dark, moody vertical portrait image showing overlapping translucent travel photographs scattered at artistic angles, as if floating in deep navy-black space. The photos show faint glimpses of iconic travel scenes — a Mediterranean coastline, a bustling Asian market, European architecture — all heavily darkened and desaturated with only hints of warm amber and soft teal light bleeding through. The photos fade to near-black toward the center, creating a dark zone for text overlay. Dreamy, nostalgic atmosphere with soft bokeh light particles. No readable text anywhere in the image. Cinematic, premium app background quality.
```

---

## Page 3: "Your Privacy Matters"

**Asset name:** `onboarding_privacy`

### Option A — Abstract Shield / Encryption
```
A dark, atmospheric vertical portrait image conveying digital privacy and security. Abstract geometric shapes — hexagons, subtle grid patterns, and flowing encrypted data streams — are rendered in deep navy and charcoal with faint teal (#4DD9C0) edge-glow accents. A soft, barely-visible shield shape is suggested by converging light rays in the upper portion. The overall mood is calm and protective, not threatening. The center is intentionally dark and minimal for white text overlay. Subtle particle effects float gently. No text, no icons, no UI elements. Futuristic but warm. Premium quality, suitable as a dark mobile app background.
```

### Option B — Secure Vault / Radial Layers
```
A dark, moody vertical portrait image showing an abstract representation of digital security. Soft concentric circles of faint teal light radiate outward from a subtle focal point, suggesting protective layers or a force field. The background is deep navy-black (#080a14) with delicate mesh-like geometric patterns barely visible in the darker areas. Small particles of light float gently, suggesting encrypted data. The mood is serene, trustworthy, and calming — not ominous. The center is soft and dark for text legibility. No locks, no padlocks, no literal security icons. No text. Abstract and elegant. Premium mobile app background quality.
```

---

## Page 4: "Let's Get Started"

**Asset name:** `onboarding_getstarted`

### Option A — Sunrise Over Landscape
```
A dark, atmospheric vertical portrait image of a dramatic sunrise breaking over a distant mountain landscape, viewed from a high vantage point. The sun is low and partially hidden, casting long rays of warm golden and soft teal light across layers of misty mountain ridges. The foreground and upper sky remain deep navy-black, creating natural dark space in the center for white text overlay. The sunrise is positioned in the lower third. Volumetric light rays cut through morning mist. Cinematic, inspirational, premium travel photography aesthetic. No people, no text, no UI elements. High resolution mobile wallpaper quality.
```

### Option B — Path Leading Forward
```
A dark, moody vertical portrait image of a winding path or trail disappearing into a beautiful misty landscape at twilight. The path is subtly illuminated by soft warm light, while the surrounding environment — rolling hills, distant city lights, or a coastline — fades into deep navy-black tones. The composition draws the eye downward along the path, suggesting a journey about to begin. Teal and lavender tones in the distant sky. The center-upper area is intentionally dark and soft for text overlay. Atmospheric, cinematic, aspirational mood. No people, no text, no signs. Premium quality, suitable as a dark mobile app background.
```

---

## After Generating

1. Save each image as JPG (high quality) or PNG
2. Drop into the Xcode asset catalog: `MacPhotoTrips/Resources/OnboardingImages.xcassets/`
   - `onboarding_timeline.imageset/` — drag image into Universal slot
   - `onboarding_stories.imageset/` — drag image into Universal slot
   - `onboarding_privacy.imageset/` — drag image into Universal slot
   - `onboarding_getstarted.imageset/` — drag image into Universal slot
3. Build & run — images appear automatically behind the onboarding text
4. Tune opacity if needed: `OnboardingPageView.swift` line 71 (`.opacity(0.4)`) — range 0.3–0.5
