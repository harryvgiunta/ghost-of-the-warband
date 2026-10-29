# The Blood Ledger — the shared menu language

Concept gate for the Ghost of the Warband menu overhaul. Nothing in this
document is wired into the game yet; it is the target the production pass is
built against.

Boards: `media/concept/00_contact_sheet.png` (all nine on one page),
`01_theme_sheet.png` … `08_altar.png`. The gear board composites
`media/concept/preview_ranger.png`, captured from the game's own character
preview viewport (`tools/ui_theme/capture_preview.gd`).

## The one object

Every window in the game is the same object at a different size:

> a forged iron clamp gripping a torn vellum page, titled on the clamp,
> sealed in wax, with its action plates on the page.

Screens do not invent furniture. The tutorial card, the warband ledger, the
gear page, the quick menu and the title all use the same clamp, the same
header, the same plate rack, the same seal and the same keycaps. Content is
what changes.

## Materials

Every material is generated from seeded value noise by
`tools/ui_theme/materials.py`; nothing is a downloaded texture and no lighting
is baked in (bevelling is applied per shape against one fixed light from the
upper left).

| Material | Used for | Generator |
| --- | --- | --- |
| Forged iron | window clamp, header rail, medallion discs | `materials.iron` |
| Vellum | every page body | `materials.parchment` |
| Oxblood leather | title furniture, HUD plate backing | `materials.leather` |
| Brass | primary action plate, inlay hairline, small medallions | `materials.brass` |
| Sealing wax | one seal per window, danger plate (lacquer) | `materials.wax` |
| Carved bone | keycaps, engraved labels | `materials.bone` |
| Soul light | possession-only accents; never a menu surface | `materials.soul` |

Palette:

| Token | Hex | Use |
| --- | --- | --- |
| iron | `#202527` | clamp, plates |
| vellum | `#c9b083` | page |
| ink | `#2b1c10` | body text, rules |
| ink muted | `#684e34` | marginal notes |
| brass | `#9d7a3f` | primary plate, inlay |
| wax | `#6a1114` | seal, danger |
| bone | `#e9e0c9` | keycaps, header type |
| blood | `#761819` | section labels, selected slot |
| ember | `#e08a3c` | downed state, active chapter stamp |
| soul | `#7fd7c4` | favourable state (alive, saved) |

## Type

Three registers, no more:

| Register | Face | Size / tracking | Colour |
| --- | --- | --- | --- |
| Title | Pirata One | 29 header, 45 page title | bone on iron, ink on vellum |
| Body | IM Fell English | 23 / 36, 17 italic marginal | ink |
| Label | IM Fell English caps | 10–13, tracking 2.4–3.6 | blood or ink muted |

Pirata One and IM Fell English are OFL, shipped in `assets/ui/fonts/` with
their licences. Numerals in a window title or seal use Pirata One (roman
numerals preferred: `I`, `III`). Body copy never sits in Pirata One.

## Geometry (at 1440 × 900)

| Measure | Value |
| --- | --- |
| Clamp width | 21 px |
| Frame radius | 14 px |
| Header height | 60 px |
| Page padding | 40 px (x), 30 px (top), 34 px (bottom) |
| Plate height | 54 px, full page width for menu stacks |
| Keycap | 35 px, 3 px radius, bone |
| Header medallion | r 23 (page rail), r 14 (table rows) |
| Header seal | r 18 |
| Chapter stamp | r 8, gap 30 |
| 9-slice safety | all ornaments inside 24 px of the outer edge |

## Components

- **Clamp.** Outer black keyline, planished iron face, brass hairline inset
  5 px, four corner rivets and two side rivets, engraved groove, chipped
  silhouette. Never a clean rectangle.
- **Page.** Torn deckle edge, scorched rim, fibres, freckles, folds, a warm
  light pool at the heart. The clamp's lip shadows it on all four sides.
- **Header.** Medallion left, engraved title centred between two hairlines
  with diamond ends, one wax seal right. The seal carries the step numeral or
  the horned skull; under ~56 px the die presses only a hollow.
- **Plate rack.** Three variants — iron (secondary), brass (primary), lacquer
  (danger) — each with idle, hover, pressed, disabled. States change light and
  depth only; geometry and label never move. Primary plates carry one bone
  keycap.
- **Keycap.** Carved bone tile, dark engraved glyph, thin iron keyline.
- **State chip.** Inked box: teal alive, ochre downed, grey dead.
- **Medallion.** Large: hammered iron disc, brass-etched pictogram (headers).
  Small: brass button, dark cut glyph (table rows, slots).
- **Divider.** Inked rule with a thorned lozenge at its heart; used once per
  section break.
- **Chapter stamps.** One thorned ring per tutorial beat, live ones ember,
  roman numeral beneath.

## Screen map

| Screen | Uses |
| --- | --- |
| Tutorial card | clamp 880 × 580, chapter name, drop-cap body, keycaps, chapter stamps, brass CONTINUE, step seal |
| Warband (O) | ledger header (purse/worth), mercenary rows, state chips, brass CONTROL, recruiter rows |
| Gear (P) | the frontier equipment page in the new skin: warband tabs on top, ten worn slots left, live ranger stage centre, trinket rail + KIT column right, collective stash as the grid underneath |
| Quick menu (ESC) | rubricated sections, resume primary, save/display secondary, two lacquer exits, last-writing block |
| Title | wordmark, skull seal, plate stack, no clamp |
| Quartermaster | narrow clamp, stock rows (mark, name, category, price, BUY), purse and held-count header |
| Altar | wide clamp, three rubricated columns (unbind / distil / brand), spines with thorns, one brass BRAND |
| Lobby (next) | the same clamp and plates; no new furniture |

## Production status

Wired and verified in the running game:

| Screen | State |
| --- | --- |
| Tutorial card | `LedgerFrame` + plate rack + bone keycaps + chapter stamps + step seal |
| Quick menu (Esc) | `LedgerFrame`, rubricated sections, brass resume, lacquer exits |
| Warband (O) | `LedgerFrame`, Pirata names, chip textures, brass CONTROL, recruiter |
| Gear (P) | frontier layout in the new skin: tabs on top, worn slots with marks, live ranger preview stage, stash rows |
| Quartermaster | `LedgerFrame`, purse in Pirata, stock rows with BUY plates |
| Sacrificial altar | `LedgerFrame`, tier rail, three ritual columns, brass BURN THE SIGIL |
| Title | concept layout: camp still, wax seal, Pirata wordmark, six centred plate doors; the warband host/join panel is the WARBAND LOBBY door |
| Warband lobby | iron slab beside the title, themed fields, brass HOST |

Theme assets: `assets/ui/theme/` (generated by `tools/render_ui_theme.py`),
shared theme `scripts/ui/ledger_theme.gd`, frame `scripts/ui/ledger_frame.gd`,
keycap `scripts/ui/ledger_keycap.gd`. Captures: `media/concept/game_capture.png`,
`game_menu.png`, `game_warband.png`, `game_gear.png`, `game_quartermaster.png`,
`game_altar.png`, `game_title.png`.

The frontier's own inventory (`world_ui.gd`, Ironwood mode) keeps its old chrome:
it is the menu the gear page was merged *from*, not a warband surface.

Polish landed: 256 px page texture with softened fibres (no banding under the
stretch), focus state = hover plate, keycaps wrapped by an `HFlowContainer`.

### Pointer

A visible window owns the pointer. `LedgerFrame` keeps `Input.mouse_mode`
`VISIBLE` for as long as it is visible (including the paused tutorial card, whose
open runs before `world_scene` captures the mouse in `_ready`), and every menu's
`open()` sets it on the same frame as the press. Closing does not capture: the
scene's own policy takes the pointer back once no panel is open.

## Production plan (original)

1. `tools/render_ui_theme.py` emits the production atlas from the same
   material fields: `assets/ui/theme/clamp.png` (9-slice), `plate_iron.png`,
   `plate_brass.png`, `plate_lacquer.png` (4 states each), `page_*.png`
   corners, plate `hover` glow, `keycap.png`, chips, seal sheet, icon set.
2. One `Theme` resource plus `scripts/ui/ledger.gd` helpers; the screens keep
   their current signals and public fields — only construction changes:
   `tutorial_card.gd`, `warband_screen.gd`, `warband_paperdoll.gd`,
   `pause_menu.gd`, `quartermaster_menu.gd`, `altar_menu.gd`, `title.gd`,
   `warband_lobby.gd`.
3. Import the two OFL fonts as Godot font resources with size overrides.
4. Verification: launch the warband world, open every screen, capture at
   1440 × 900 and 1920 × 1080; the existing `warband_ui`, tutorial and layout regressions must still pass; no `StyleBoxFlat` chrome left on
   the converted screens.

## Gate

The direction is not wired. Approve it, or pick a change: darker/satanic,
warm illuminated manuscript, heavier hardware, or a full-bleed panel instead
of a floating page.
