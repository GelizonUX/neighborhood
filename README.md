# Neighborhood

A 3D city life-sim in the making. Walk or drive around a city of about
780 × 530 metres: 500 houses, shops, a downtown of towers, four parks with
ponds, and a river crossed by thirteen bridges. Built with Godot 4 and Kenney's
free low-poly models.

**Play in your browser:** https://gelizonux.github.io/neighborhood/

A desktop browser with a keyboard is needed. Loading and building the city
takes roughly half a minute.

## What happens in the city

- **A clock.** One game minute passes every second, so a day lasts 24 minutes.
  The sun rises at 6:00 and sets at 18:00.
- **Residents with routines.** Every house has a resident with a home and a
  job or a favourite park. They commute in the morning, walk at lunchtime,
  come home in the evening and stay in at night.
- **Traffic** that keeps to its lane, turns at intersections and stops for
  people and cars in its way.
- **Physics.** Cars you can drive ride on sprung wheels; cones, boxes and
  balls can be knocked around; the river and ponds are real dips you can wade
  into.
- **Boats** drift down the river and clouds cross the sky.

## Controls

| On foot | In a car |
|---|---|
| WASD move, Shift run, Space jump | W/S accelerate and reverse, A/D steer, Space brake |
| E get into a nearby parked car | E get out (the car must be nearly stopped) |
| V change camera view | V change camera view |

Look around by dragging with a mouse button held, or with the arrow keys.
Clicking the game also captures the mouse for free look where the browser
allows it (Esc releases it). The mouse wheel zooms.

## Running it on your computer

1. Install [Godot 4.7](https://godotengine.org/download).
2. Open Godot, choose **Import** and pick `project.godot`.
3. Press **F5**.

## How it is put together

- `scripts/city_builder.gd` builds the city when the game starts. Its size and
  layout are constants at the top: the number of roads, what each band of
  blocks contains, where the parks are. Identical models are drawn in batches
  so a city this size stays fast.
- `scripts/population.gd` is the residents and their routines;
  `scripts/day_cycle.gd` is the clock and sky.
- `scripts/traffic_car.gd` is self-driving traffic; `scripts/car.gd` is a car
  you can drive; `scripts/player.gd` and `scripts/camera_rig.gd` are you and
  your camera.
- `docs/` is the browser build that the play link serves. `publish.sh`
  rebuilds it and uploads everything.

## Credits

3D models by [Kenney](https://kenney.nl) (City Kit Suburban, City Kit Roads,
City Kit Commercial, Nature Kit, Car Kit, Mini Characters), released under
CC0. Made with [Godot Engine](https://godotengine.org).
