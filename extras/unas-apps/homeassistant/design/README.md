# Dashboard styles for Home Assistant

Styles for YAML dashboards in the look of Apple Home on a dark theme: dark,
slightly translucent cards with rounded corners, tiles that turn light when
the device is on, small upper-case section headings, notices as rows with a
coloured dot. They are not a theme: a theme sets colours for the whole
frontend, these style single cards. They go on top of a dark theme, here the
dark-blue variant of [iOS Themes](https://github.com/basnijholt/lovelace-ios-themes)
(`ios-dark-mode-dark-blue`, with its background image).

Needs [uix](https://github.com/Lint-Free-Technology/uix) 8.x (the successor of
card-mod; HACS → Integrations). It loads its frontend module itself.

## Styles

| File | For |
| --- | --- |
| `tile.yaml` | tile cards; light when on (light, switch, input_boolean, fan, vacuum, media player while playing) |
| `tile-bar.yaml` | tiles with a bar gauge in the row (`features_position: inline`) |
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

Colours: cards `#1C1C1F` at 88 % with a blur, radius 18; a tile that is on
`#F2F2F7` with dark text; secondary text `#A1A1AA`; alarm `#C42B22`. Font: the
system font (SF Pro on Apple devices).

## Use

Copy `styles/` next to the dashboard's YAML file. Each view includes the
styles it uses once as YAML anchors under a key Home Assistant ignores, and
every card points to one:

```yaml
# dashboards/home/start.yaml, a view of a YAML dashboard
title: Start
type: sections
styles:
  tile: &tile !include styles/tile.yaml
  heading: &heading !include styles/heading.yaml

sections:
  - type: grid
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

Home Assistant reloads a YAML dashboard's view files only when the
dashboard's main file changes; after editing a style, `touch` the main file
and reload the page.
