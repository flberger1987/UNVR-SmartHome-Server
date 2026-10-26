# Dashboard styles for Home Assistant

Styles for YAML dashboards in the look of Apple Home on a dark theme: dark,
slightly translucent surfaces with rounded corners, sections as blocks,
tiles that turn light when the device is on, small upper-case section
headings, notices as rows with a coloured dot. They are not a theme: a theme
sets colours for the whole frontend, these style single cards and sections.
They go on top of a dark theme, here the dark-blue variant of
[iOS Themes](https://github.com/basnijholt/lovelace-ios-themes) (MIT) with a
gradient instead of its photo, see [Background](#background).

Needs [uix](https://github.com/Lint-Free-Technology/uix) 8.x (the successor of
card-mod; HACS → Integrations). It loads its frontend module itself.

## Styles

| File | For |
| --- | --- |
| `block.yaml` | sections (`uix:` on a grid section): one surface, the cards inside turn transparent |
| `tile.yaml` | tile cards; light when on (light, switch, input_boolean, fan, vacuum, lawn mower, media player while playing) |
| `tile-bar.yaml` | tiles with a narrow bar gauge: short in the row (`features_position: inline`), across the tile at the bottom (`bottom`) |
| `tile-signal.yaml` | tiles whose icon keeps its colour (alarm, start, stop) |
| `tile-dot.yaml` | notices: a dot in the tile's `color` instead of the icon |
| `button.yaml` | tiles used as buttons: centred text, no icon |
| `scene.yaml`, `scene-bar.yaml` | scenes as a segmented control: tiles with `scene.yaml` in a grid card with `scene-bar.yaml` |
| `area.yaml` | area cards; light while a light in the area is on |
| `card.yaml` | every other card (logbook, history, camera, energy, todo, markdown with a frame) |
| `heading.yaml` | heading cards (`heading_style: title` or `subtitle`) |
| `page-header.yaml` | a page header from markdown (`# Title`, a line below) |
| `note.yaml` | markdown with `text_only: true` |
| `rows.yaml`, `alarm.yaml` | notices as markdown rows; an alarm as a red band |

Colours: cards and blocks `#1C1C1F` at 88 % with a blur, radius 18 (blocks
24); a tile that is on `#F2F2F7` with dark text; secondary text `#A1A1AA`;
alarm `#C42B22`. Font: the system font (SF Pro on Apple devices).

The card styles take their surface from `--zh-kachel-bg` and their blur from
`--zh-unschaerfe` (falling back to the dark surface and `blur(24px)`);
`block.yaml` sets both on its section, which is how the cards inside turn
transparent.

## Use

Copy `styles/` next to the dashboard's YAML file. Each view includes the
styles it uses once as YAML anchors under a key Home Assistant ignores, and
every card points to one:

```yaml
# dashboards/home/start.yaml, a view of a YAML dashboard
title: Start
type: sections
styles:
  block: &block !include styles/block.yaml
  tile: &tile !include styles/tile.yaml
  heading: &heading !include styles/heading.yaml

sections:
  - type: grid
    uix: *block
    cards:
      - type: heading
        uix: *heading
        heading: Living room
        heading_style: subtitle
      - type: tile
        uix: *tile
        entity: light.living_room
```

A row of scenes:

```yaml
      - type: grid
        uix: *scene_bar
        columns: 3
        square: false
        grid_options: {columns: full}
        cards:
          - {type: tile, uix: *scene, entity: scene.evening, name: Evening, hide_state: true}
          - {type: tile, uix: *scene, entity: scene.bright, name: Bright, hide_state: true}
          - {type: tile, uix: *scene, entity: scene.off, name: Off, hide_state: true}
```

Notices as rows (`tile-dot.yaml`): the colour of the dot is the tile's
`color` (red alarm, orange fault, yellow maintenance, blue task, grey info).

Give every section with controls `uix: *block`: what belongs together (a
washing machine's progress and its end time) then reads as one block. Leave
page heads, a status line of badges and an alarm band without it, on the
background, and let them span the width (`column_span: 4`; Home Assistant
limits it to the columns there are), or a gap opens below them on wide
screens.

## Background

A theme of its own: copy the variables of `ios-dark-mode-dark-blue` from the
iOS Themes into a new theme (e.g. `Home`, keep `modes: {dark: {}}`) and
replace its photo:

```yaml
  background-image: >-
    radial-gradient(120% 60% at 15% 0%, #1D4ED8 0%, rgba(29, 78, 216, 0) 55%) fixed,
    radial-gradient(90% 55% at 100% 35%, #0E5A8A 0%, rgba(14, 90, 138, 0) 60%) fixed,
    radial-gradient(120% 70% at 30% 100%, #172554 0%, rgba(23, 37, 84, 0) 65%) fixed,
    linear-gradient(180deg, #0B1A3A 0%, #060B1C 100%) fixed #060B1C
```

Make it the default with `frontend.set_theme` (e.g. in an automation on
start). A browser whose profile has a theme selected keeps it: Profile →
Theme → "Backend-selected".

Home Assistant reloads a YAML dashboard's view files only when the
dashboard's main file changes; after editing a style, `touch` the main file
and reload the page.
