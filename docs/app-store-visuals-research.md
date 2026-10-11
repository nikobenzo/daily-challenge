# Daily Challenge — App Store screenshot research

Checked 11 October 2026. Deliverable: seven English (UK) marketing screenshots,
with the app's real fixture UI. These are screenshot-gallery assets, not the new
product-page header or search-result creative assets.

## What “well-performing” means here

Public listings expose ratings, reviews, some chart positions and editorial
recognition, not screenshot conversion rates. This is a study of established,
highly rated listings and one directly comparable challenge app, not evidence
that a particular screenshot design caused downloads. Rankings vary by country,
category and date; the sample below is the US iPhone storefront. Do not transfer
competitors' accolades, user counts or ranking claims to Daily Challenge.

## Listings studied

The screenshot galleries were inspected visually through Chrome on 11 October,
including the first two unique frames and subsequent feature frames. Responsive
image sources sometimes repeat the same frame; those duplicates were ignored.

| Listing / public signal | Visual observations | Useful lesson |
| --- | --- | --- |
| [Streaks](https://apps.apple.com/us/app/streaks/id963034692) — about 27K ratings, 4.8, displayed #2 Health & Fitness and Editors' Choice in the fetched listing | Full-bleed actual UI, no marketing caption; first frame's task rings are the hook, followed by statistics; saturated gradients and large icons | Recognisable progress shapes can sell the experience themselves. Captioned phone framing is a choice, not a universal rule. |
| [Habitify](https://apps.apple.com/us/app/habitify-habit-tracker/id1111447047) — about 7.1K ratings, 4.6 | First two frames lead with habit-building outcomes; large top-aligned blue/black headlines, small supporting line, pale backgrounds; angled journal/phone, enlarged UI cards; later widgets and multiple devices | One benefit per frame, short headings above the UI; use a focused enlargement when the original UI is too small. |
| [Productive](https://apps.apple.com/us/app/productive-habit-tracker/id983826477) — about 91K ratings, 4.6 | Dark backgrounds, white/yellow top captions; first frame is an illustrated promise, second shows habit planning in a phone; later frames cover goals and challenges | A consistent palette and simple verb-led messages make a series easy to scan. Lead Daily Challenge with actual UI rather than a general illustration. |
| [WaterMinder](https://apps.apple.com/us/app/water-tracker-by-waterminder/id653031147) — about 35K ratings, 4.7, Editors' Choice | Strong blue across the gallery; white top captions; first frames show reminders and visual water logging; phone/watch framing; an enlarged history panel; a dedicated Home Screen widget frame | Show the jug and the logging control clearly; widgets deserve their own recognisable Home Screen example. |
| [Strong](https://apps.apple.com/us/app/strong-workout-tracker-gym-log/id464254577) — about 109K ratings, 4.9 in the fetched App Store result | Slate backgrounds, top-left white text, consistently framed phones; first frame has a large user-count claim; subsequent screens demonstrate specific tools and graphs | Keep composition consistent; use product evidence rather than invented social proof. Its longer captions are less suited to Daily Challenge's thumbnail hook. |
| [75 Days Challenge: Better](https://apps.apple.com/us/app/75-days-challenge-better/id6667095733) — direct challenge-format comparator, not a substantiated high-chart performer | Black backgrounds, very short uppercase top captions, nearly full-height UI; daily checklist then progress grid; a later dedicated widget frame | Establish daily tracking first, then progress. Keep the wording generic and distinguish Daily Challenge's actual five requirements. |

## Recurring patterns and decisions

- **First two frames:** benefit or recognisable task UI first, a supporting feature
  second. We lead with “One day. Five clear goals.” and a Today capture, followed
  by “Check in. Keep moving.” and placed Home Screen widgets. The challenge tag
  says “75-day challenge”; it does not promise a transformation or a medical result.
- **Captions:** the captioned examples usually place their heading in the upper
  quarter, above the phone. Observed headlines range from a few words to longer
  sentences; short phrases suit this app. Ours use two lines and 4–6 words, with
  one supporting sentence. The headline is the reading priority at thumbnail size.
- **Framing:** five sampled sets use phone framing for at least some frames;
  Streaks uses full-bleed UI. We chose a restrained, front-facing device surround
  to distinguish real UI from marketing text. No perspective warping; the app UI
  remains proportionally scaled. Water and extras also get labelled enlargements
  from the exact same image, not reconstructed components.
- **Colour:** blue, pale or dark backgrounds recur, with palette continuity within
  a set. We use the existing Paper system: light glass `#F6F8FD`, ink `#0F172A`,
  water `#2E66F0`, accent `#1F56E0`, dark water `#5EA8FF`, and soft blue gradients.
  The widget frame is blue; the dark-mode frame uses a dark backdrop. System SF
  typography and the repository's real water-drop app icon carry the brand.
- **Widgets:** WaterMinder and Better show actual Home Screens; Habitify mixes
  feature cards and widget-like surfaces. Ours shows the captured SpringBoard
  page, rather than presenting an in-process widget render as a placed widget.
- **Social proof:** some observed sets include user counts or Apple accolades.
  We have no validated equivalent and use none. Apple's current guidance also
  excludes Apple-designated recognitions in assets. No pricing, fabricated
  ratings, testimonials, awards or “No. 1” claims appear in the delivered images.

These are design inferences from the sample. Performance must eventually be
measured in App Store Connect; it cannot be inferred from competitor screenshots.

## Apple's current requirements and guidance

[Apple's screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
currently require an iPhone screenshot for the **medium Dynamic Island display**.
Accepted portrait sizes there are **1179 × 2556** and **1206 × 2622**. For the
large Dynamic Island display (the brief's 6.9-inch class), Apple accepts
**1260 × 2736**, **1290 × 2796** and **1320 × 2868**. This set exports at
**1320 × 2868** and **1206 × 2622**. The page allows 1–10 JPEG/PNG screenshots
per device size, disallows alpha/transparency and explains automatic scaling
for smaller displays. It conditionally requires 13-inch iPad screenshots for
apps supporting iPadOS; this app's authoritative `iOS/project.yml` declares
`TARGETED_DEVICE_FAMILY: "1"`, and firstmate confirmed iPhone-only scope.
No iPad, Watch, Mac-listing or landscape screenshot set is required here.
Apple's future iPhone Duo requirement starts April 2027 for the iOS 27.1 SDK;
it is not a current deliverable. Re-check the linked specifications at submission.

[Apple's product-page guidance](https://developer.apple.com/app-store/product-page/)
says to use captured UI, give subsequent screenshots a distinct benefit, and
consider a dark-mode image. Without a preview, the first one to three screenshots
can appear in search, depending on orientation. This is why the hook and widgets
are first and why the set contains a real dark appearance.

[Apple's asset best practices](https://developer.apple.com/app-store/asset-best-practices/)
recommend a clear focal point, short text, readable key elements and safe areas,
consistent visual style, and strongest features first. They prohibit unverifiable
claims, specific pricing and Apple-designated awards in assets. These guidelines
also distinguish screenshot galleries from the newer header/search creative
asset formats. This task produces only the requested screenshot gallery.

## Chosen concept: a clear daily view

A pale blue editorial canvas, large benefit-led headline and a single real app
capture. The first frame makes the fixed five-goal challenge understandable;
the second shows quick Home Screen check-ins. Later frames build the story:
water, personal extras, completed-day history, appearance and daily completion.
This adapts the strong caption/UI hierarchy seen in Habitify, WaterMinder and
Better while preserving Daily Challenge's glass surfaces, jug, rings and icon.
It does not imitate their UI or claim their results.

Sources, captions and reproducible export instructions are in
[screenshots/app-store/marketing/README.md](screenshots/app-store/marketing/README.md).
