# Snow Globe Simulator

A customisable snow globe toy made with Godot 4.7 (GL Compatibility renderer), built to run in the browser and on phones.

Swing and toss globes around a shelf (up to three at once), shake them, turn them upside down, or step inside one. Fill them with snow, rain, glitter, bubbles, dust, wind, clouds, fireworks, cobwebs, dynamite, sea monkeys, butterflies, ants, tiny people or a plasma ball, in sphere, tube, diamond, egg, hourglass, box or pyramid glass. Everything can be edited live, saved as presets, or rolled at random.

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
| Shake | Space, bottom-left button | Bottom-left button, or shake the phone |
| Editor | E, top-right button | Top-right button |

Add `?fps` to the page address to show the frame rate.

## Project layout

- `scripts/main.gd` — the shelf of globes and all input. `max_globes` sets how many fit.
- `scripts/globe/globe_body.gd` — physics for one globe (carrying, tossing, shaking, respawning).
- `scripts/snow_globe.gd` — the globe itself: glass, stand, floor, props.
- `scripts/globe/` — glass shapes, stands, props, creatures, plasma, randomizer.
- `scripts/globe_particles.gd`, `scripts/globe_particle_style.gd` — snow / rain / bubbles / glitter.
- `scripts/globe_preset.gd` — saving and loading presets (JSON).
- `scripts/ui/` — on-screen buttons and the in-game editor.
- `presets/`, `particles/`, `creatures/` — built-in presets and styles.

## Publishing the website

`tools/deploy_web.sh` exports the web build and pushes it to the `gh-pages` branch, which GitHub Pages serves. It needs Godot's web export templates installed.
