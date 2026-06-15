# Media assets

Hero and demo media for the README and the family banner.

| File | Used by | Status |
|---|---|---|
| `hero.gif` | top of root `README.md` | **placeholder slot** — record the seed session |
| `hero.png` | static OG/social fallback | optional |

## Recording the hero GIF (the seed session)

The hero shows the canonical reference session — the same
[`fixtures/seed-session.json`](../fixtures/seed-session.json) every runtime
replays — correcting itself in place (cue→Q3, to→two, …) and redacting
Acme/Sarah, with the **Diff-morph ⭐** effect selected.

```bash
npm install && npm run dev          # opens the React lab on http://localhost:5173
# select "Diff-morph ⭐", let one full loop play, then capture the surface:
#   • macOS:  Cmd-Shift-5 → record region → export → convert to GIF
#   • or:     gifski / ffmpeg  (ffmpeg -i screen.mov -vf "fps=24,scale=900:-1" hero.gif)
```

Drop the result here as `hero.gif` (≤ ~3 MB, ~900px wide). The README already
points at `assets/hero.gif`; no markdown change needed once the file lands.
