# Changelog

## Unreleased (2026-10-17)

### Fixed

- **The cheapest item sometimes disappeared after a delete.** After items were deleted from the bar,
  the first (larger) cell could stay blank: its space was kept, but it had no icon, border, price or
  glow until something else in the bags changed. Two changes fix this:
  - After every click on the bar (delete, sell or ignore), the bar draws itself again about 0.6
    seconds later, after the bags have settled.
  - Each time the bar is drawn, every cell is checked on the next frame. A cell must be shown,
    placed, opaque, sized and have an icon. If one fails, the bar is redrawn once.
- Shown cells are always reset to full opacity when the bar is laid out.

### Added

- `/bagcleaner debug` turns diagnostic chat messages on and off. When a cell fails the check, it
  prints which cell it was, what was wrong and whether the redraw fixed it. Include these lines
  when you report a display problem.
