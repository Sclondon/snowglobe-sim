# Snow Globe Simulator

A customisable snow globe toy made with Godot 4.7 (GL Compatibility renderer), built to run in the browser and on phones.

Swing and toss globes around a tablecloth-covered shelf (up to eight at once), shake them, knock them over, turn them upside down, or step inside one. Fill them with snow, rain, glitter, bubbles, dust, wind, clouds, fireworks, cobwebs, dynamite, fireflies, aurora, heat waves, sun rays, rainbows, sea monkeys, butterflies, ants, tiny people or a plasma ball, plus props — some of which (balls, rings, hopping frogs, swaying seaweed) move with the globe. Globes come tiny to big, in sphere, tube, diamond, egg, hourglass, box or pyramid shapes, with a glass, ice, soap bubble, water, force field, magnetic field or no shell at all. Everything can be edited live, saved as presets, or rolled at random; the editor's Scene tab sets the lighting (spotlight, fireplace glow or both), tablecloth and room dust and fog.

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
