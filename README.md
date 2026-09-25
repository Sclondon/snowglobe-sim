# Snow Globe Simulator

A customisable snow globe toy made with Godot 4.7 (GL Compatibility renderer), built to run in the browser and on phones.

Swing and toss globes around a shelf dressed with antique velvet cloths (up to eight at once), shake them, knock them over, turn them upside down, or step inside one. Fill them with snow, snowfall, rain, glitter, bubbles, dust, wind, clouds, fireworks, cobwebs, dynamite, fireflies, aurora, heat waves, sun rays, rainbows, lava-lamp wax, sea monkeys, butterflies, songbirds (they take off when shaken), ants, tiny people, a snake, a dragon, noodles or a plasma ball, plus props — some of which (balls, rings, hopping frogs, swaying seaweed) move with the globe. Globes come tiny to big, in sphere, tube, diamond, egg, hourglass, box or pyramid shapes, with a glass, ice, soap bubble, water, force field, magnetic field or no shell at all. Everything can be edited live, saved as presets, or rolled at random; the editor's Scene tab sets the lighting (spotlight, fireplace glow or both), tablecloth and room dust and fog.

## Controls

| | Mouse / keyboard | Touch |
|---|---|---|
| Select a globe | Click it | Tap it |
| Swing / toss a globe | Drag it and let go | Drag it and let go |
| Add a globe | + button | + button |
| Look from inside | V, eye button | Eye button |
| Look around | Drag elsewhere / right-drag | Drag elsewhere, two fingers |
| Zoom | Wheel | Pinch |
| Inspect (turn freely) | Double-click, I, bottom-right button | Double-tap, bottom-right button |
| Stand a fallen globe back up | Inspect, then put it back | Inspect, then put it back |
| Shake | Space, bottom-left button | Bottom-left button, or shake the phone |
| Editor | E, top-right button | Top-right button |

Add `?fps` to the page address to show the frame rate.

## Project layout

- `scripts/main.gd` — the shelf of globes and all input. `max_globes` sets how many fit.
- `scripts/globe/globe_body.gd` — physics for one globe (carrying, tossing, shaking, respawning).
- `scripts/snow_globe.gd` — the globe itself: glass, stand, floor, props.
- `scripts/globe/` — glass shapes, stands, props (and loose props), creatures, effect layers, randomizer.
- `scripts/scene/` — the room: tablecloth, lighting, ambient dust and fog, scene settings.
- `shaders/glass_common.gdshaderinc` — the shell shader (glass, ice, bubble, water, force field, magnetic).
- `scripts/globe_particles.gd`, `scripts/globe_particle_style.gd` — snow / rain / bubbles / glitter.
- `scripts/globe_preset.gd` — saving and loading presets (JSON).
- `scripts/ui/` — on-screen buttons and the in-game editor.
- `presets/`, `particles/`, `creatures/` — built-in presets and styles.

## Publishing the website

`tools/deploy_web.sh` exports the web build and pushes it to the `gh-pages` branch, which GitHub Pages serves. It needs Godot's web export templates installed.

## Arcade integration (tickets, unlocks, community shelf)

Nothing is wired to accounts yet; these are the hooks the site can use.

**Unlocks.** Effects are locked or free per `scripts/unlocks.gd` (`CATALOG` holds every unlockable id with a placeholder ticket price, e.g. `layer:lava`, `layer:dragon`, `shell:forcefield`, `shape:pyramid`, `stand:platform`, `prop:frog`). Locked items show greyed out with their price in the editor, the randomizers never use them, and built-in presets that need them are hidden. Viewing is never locked.
- Set before the game loads: `window.snowglobe = { unlocks: ["layer:lava", "shell:ice"] }`
- Change any time: `window.snowglobe.setUnlocks(["layer:lava", ...])`
- Saved to `user://unlocks.json` (`{"unlocked": [...]}`) alongside the session.
- Testing: add `?unlock=all` to the page address.

**Labels.** Each globe has a `name` (players edit it in the editor's Globe tab) and a `creator` (set by the site) in its preset JSON; both show on a brass plaque at the front of the stand.

**Community shelf.** The people button opens a display cabinet of everyone's globes (view-only; tap one for a closer look). It loads a JSON array of globe presets (or `{"globes": [...]}`) from, in order: `window.snowglobe.community` (the array, or a URL), `?community=<url>`, or `community.json` next to `index.html`. Without any of those it shows a generated demo shelf.

**Performance.** Every globe has a detail level: full, lite (stepped every few frames, fewer particles, no per-globe lights) or asleep (off screen). Settled snow stops simulating until the globe moves. Add `?fps` to the address to see frame rate and how many globes are awake.
