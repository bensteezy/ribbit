# ribbit product video

## target

- 55 seconds, 16:9, 1920 × 1080, 60 fps
- silent-first with concise captions; optional voiceover can reuse the captions
- window capture only—no desktop, menu bar, notifications, or personal paths
- one continuous recording, tightened in Screen Studio afterward

## preflight

1. Turn on Do Not Disturb.
2. Open `/Users/Shared/ribbit-demo` as a ribbit project.
3. In the first terminal, run `export PS1='demo %1~ %# '` and then `clear`.
4. Use the dark scheme, 15 pt terminal text, and 13 pt interface text.
5. Size ribbit to roughly 1440 × 900. Keep the files pane narrow but readable.
6. Close unrelated tabs and leave one terminal named `terminal`.

## shot list

| Time | Action | Caption |
| --- | --- | --- |
| 0:00–0:04 | Hold on the clean ribbit window. Move the cursor only after the title appears. | `ribbit` / `native terminals + raw notes for macOS` |
| 0:04–0:12 | Click the project selector, briefly choose `base`, then return to `ribbit-demo`. | `a workspace for every project` |
| 0:12–0:20 | Create a terminal with `⌘T`. Rename it `agent` and assign green. Run `printf 'agent ready\n'`. | `launch agents from the project root` |
| 0:20–0:28 | Create another terminal. Rename it `tests` and assign blue. Run the three-line demo command below. | `keep independent terminal sessions organized` |
| 0:28–0:36 | Create a note with `⌘N`. Type the four-line note below. | `keep raw notes beside the work` |
| 0:36–0:43 | Switch to `base`, showing its own tabs, then return to `ribbit-demo`. | `switch projects without losing state` |
| 0:43–0:49 | Return to `agent`, press `⌘F`, and search for `ready`. | `find anything in terminal output` |
| 0:49–0:55 | Hold on the composed app view; fade to the end title. | `ribbit` / `open source · MIT` |

## terminal content

Agent terminal:

```sh
printf 'agent ready\n'
```

Tests terminal:

```sh
for step in index plan build; do printf '✓ %s\n' "$step"; done
```

Note content:

```text
release checklist

- verify the build
- review agent output
- ship
```

## Screen Studio treatment

- Use a near-black solid background with 56–72 px outer padding.
- Keep corner radius and shadow subtle. Do not add device frames.
- Use automatic zoom only for the project selector, tab rename, and search field.
- Keep zooms below 125% and ease them over 250–350 ms.
- Remove pauses longer than 0.6 seconds and visible setup mistakes.
- Keep cursor smoothing modest; do not enlarge the cursor excessively.
- Use one neutral sans-serif caption style, lower-case, bottom-left aligned.
- Avoid music for the GitHub master. A social cut may add quiet, non-lyrical music.

## export

- Master: H.264 MP4, 1920 × 1080, 60 fps, high quality.
- GitHub preview: H.264 MP4, 1920 × 1080, target under 25 MB.
- Thumbnail: export the 0:02 frame as a 1280 × 720 PNG.

