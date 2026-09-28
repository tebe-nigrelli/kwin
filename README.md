<p align="center">
  <img src="logo.png" width="112" alt="KWin logo">
</p>

<h1 align="center">KWin Topos</h1>

<p align="center">
  <strong>Virtual desktops, liberated from the grid.</strong><br>
  A KWin fork that turns your workspace into a graph you can see, shape, and traverse.
</p>

---

Most desktop pagers assume every workspace belongs in a rectangle. Topos keeps
that familiar grid as the default, then adds a graph on top: every virtual
desktop is a vertex and every direction you can travel is an editable edge.

That means **east can lead to any desktop**, a corner can become a shortcut,
an edge can be one-way, and an entire layout can wrap like a cylinder, torus,
or sphere.

```mermaid
flowchart LR
    I((1<br>Inbox)) -- E --> W((2<br>Work))
    W -- W --> I
    W -- E --> C((3<br>Code))
    C -- W --> W
    W -- SE shortcut --> M((4<br>Music))
    M -- N --> I
    C -. blocked east .-> X[×]

    classDef current fill:#3daee9,color:#fff,stroke:#1d79a8,stroke-width:3px
    classDef desktop fill:#232629,color:#eff0f1,stroke:#7f8c8d,stroke-width:2px
    classDef blocked fill:transparent,color:#da4453,stroke:transparent
    class W current
    class I,C,M desktop
    class X blocked
```

## Fork features

| | Feature | What it unlocks |
|---|---|---|
| ◉ | **A real workspace graph** | Connect any desktop to any other desktop instead of accepting row-and-column routing. |
| ↗ | **Eight directional ports** | Route north, north-east, east, south-east, south, south-west, west, and north-west independently. |
| ⇄ | **Directed or two-way edges** | Build deliberate one-way flows, symmetric paths, shortcuts, dead ends, and hubs. |
| ◇ | **Interactive graph editor** | Open Grid View and drag a desktop port onto another desktop. The live bridge preview shows exactly what will be connected. |
| ⟳ | **Orientation transport** | Rotate movement in 45-degree steps or mirror it as an edge is crossed, so traversal can model non-flat spaces. |
| ≋ | **Continuous traversal** | KWin resolves the graph while desktop gestures are in progress, including diagonal routes, blocked feedback, and animated placement. |
| ⌘ | **Topology HUD** | See the graph in Grid View with directional arrows, the current desktop, grid or loose-DAG layout, and adjustable spread. |
| ⟲ | **History and profiles** | Undo, redo, revisit history, and save named topologies for different activities. |

### Built-in shapes

Start with a preset and customize from there:

- **Base Grid** — standard KWin behavior, with topology tools ready when you need them.
- **Cylinder X / Cylinder Y** — wrap on one axis and keep boundaries on the other.
- **Torus** — wrap both axes; every edge leads somewhere.
- **Sphere** — wrap horizontally and cross the poles with orientation-aware routing.

The graph is not just decoration. Topos plugs its resolver into KWin's normal
virtual-desktop navigation, screen-edge switching, and interactive gesture
path. The map you edit is the map KWin actually follows.

## Set it up

> [!WARNING]
> This is an experimental KWin fork, not a standalone compositor. Replacing
> the compositor can interrupt your graphical session, so save your work and
> keep a recovery path available.

This branch targets the Plasma 6.7 KWin codebase. To install it, follow the
[build and recovery guide](BUILD.md). It currently documents the Arch Linux
package workflow.

After installation:

1. Log out of Plasma and back in so the forked KWin is running.
2. Create at least two virtual desktops on the **Virtual Desktops** page in
   System Settings.
3. Press <kbd>Meta</kbd>+<kbd>G</kbd> (the default shortcut) to open **Grid
   View**. Each desktop card has eight topology handles, and the topology map
   and preset controls appear in the HUD.
4. Choose a built-in preset, or drag a handle onto another desktop to create a
   custom route.

Topos initially inherits the ordinary KWin grid, so no extra configuration is
needed to keep existing desktop navigation working. To edit a route:

- drop in the inner target to create a two-way connection;
- drop in the outer target to create a one-way connection;
- double-click a connection to remove that route, or drag it again to replace it;
- use the HUD to inspect the whole graph, switch layouts, and load or save a preset.

Run `toposctl status` to confirm that the D-Bus service is available and inspect
the active topology.

## Script the graph

`toposctl` exposes the same model for terminal workflows and automation:

```bash
# Inspect the active topology
toposctl status
toposctl edge list

# Try a built-in topology
toposctl preset list
toposctl preset apply Torus

# Make Focus → Build the eastward route, and create the inverse edge too
toposctl --bidirectional edge set Focus E Build

# Turn the north-east edge of Focus into a boundary
toposctl edge block Focus NE

# Save the result and undo the latest edit if needed
toposctl config save "Deep Work"
toposctl undo
```

Desktop selectors can use a desktop name, ID, or index. The public
`org.kde.KWin.Topos` D-Bus interface also exposes graph state, profiles,
history, edits, and runtime settings for other tools.

## Under the hood

The implementation is intentionally part of KWin rather than a pager-only
simulation:

- `ToposManager` resolves graph edges and owns traversal, profiles, and history.
- the Overview effect provides the visual editor, bridge preview, and graph HUD;
- virtual-desktop and screen-edge navigation consult the topology resolver;
- `.topos` profiles are watched and loaded at runtime;
- `toposctl` talks to KWin through a versioned D-Bus API.

The result is a small change in vocabulary with a large change in possibility:
**workspaces are places, directions are choices, and the path between them is
yours to design.**

## About KWin

[KWin](https://invent.kde.org/plasma/kwin) is KDE Plasma's flexible Wayland
compositor and window manager. This project is a downstream experimental fork;
the Topos additions are not part of upstream KWin. For issues specific to this
fork, use this repository rather than KDE's bug tracker.

KWin and this fork are distributed under the licenses listed in
[`LICENSES/`](LICENSES/).
