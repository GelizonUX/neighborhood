# Neighborhood

A small 3D life-sim in the making: walk around a suburban street, switch camera
views and drive the cars. Built with Godot 4 and Kenney's free low-poly models.

**Play in your browser:** https://gelizonux.github.io/neighborhood/

It takes a few seconds to load. A desktop browser with a keyboard is needed.

## Controls

| On foot | In a car |
|---|---|
| WASD move, Shift run, Space jump | W/S accelerate and reverse, A/D steer, Space brake |
| E get into a nearby car | E get out (the car must be nearly stopped) |
| V change camera view | V change camera view |

Look around by dragging with a mouse button held, or with the arrow keys.
Clicking the game also captures the mouse for free look where the browser
allows it (Esc releases it). The mouse wheel zooms.

## Running it on your computer

1. Install [Godot 4.7](https://godotengine.org/download).
2. Open Godot, choose **Import** and pick `project.godot`.
3. Press **F5**.

## How it is put together

- `scripts/street_builder.gd` builds the street when the game starts. The
  number of houses, lot size and which models are used are constants at the top.
- `scripts/player.gd` is the character; `scripts/car.gd` is a drivable car;
  `scripts/camera_rig.gd` holds the camera views.
- `docs/` is the browser build that the play link serves. `publish.sh`
  rebuilds it and uploads everything.

## Credits

3D models by [Kenney](https://kenney.nl) (City Kit Suburban, City Kit Roads,
Car Kit, Mini Characters), released under CC0. Made with
[Godot Engine](https://godotengine.org).
