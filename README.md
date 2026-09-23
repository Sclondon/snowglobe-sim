# Snow Globe Simulator

A customisable snow globe toy made with Godot 4.7 (GL Compatibility renderer), built to run in the browser and on phones.

Shake it, turn it upside down, and fill it with snow, rain, glitter, bubbles, sea monkeys, butterflies, ants, tiny people or a plasma ball. Everything can be edited live, saved as presets, or rolled at random.

## Controls

| | Mouse / keyboard | Touch |
|---|---|---|
| Move the globe | Drag it | Drag it |
| Look around | Drag elsewhere / right-drag | Drag elsewhere, two fingers |
| Zoom | Wheel | Pinch |
| Inspect (turn freely) | Double-click, I, bottom-right button | Double-tap, bottom-right button |
| Shake | Space, bottom-left button | Bottom-left button, or shake the phone |
| Editor | E, top-right button | Top-right button |

Add `?fps` to the page address to show the frame rate.

## Project layout

- `scripts/snow_globe.gd` — the globe: glass, stand, floor, props, movement.
- `scripts/globe/` — glass shapes, stands, props, creatures, plasma, randomizer.
- `scripts/globe_particles.gd`, `scripts/globe_particle_style.gd` — snow / rain / bubbles / glitter.
- `scripts/globe_preset.gd` — saving and loading presets (JSON).
- `scripts/ui/` — on-screen buttons and the in-game editor.
- `presets/`, `particles/`, `creatures/` — built-in presets and styles.

## Publishing the website

`tools/deploy_web.sh` exports the web build and pushes it to the `gh-pages` branch, which GitHub Pages serves. It needs Godot's web export templates installed.
