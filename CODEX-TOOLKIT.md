# Ben's Codex toolkit

A shareable inventory of the skills and plugins that make this Codex setup useful.

## Best community skills

These are portable. Open a skill page to inspect it, or install all five public skills with the command below.

| Skill | What it adds | Link |
|---|---|---|
| Hallmark | Opinionated UI design, redesign, audits, and visual-DNA extraction without generic AI styling | [Skill page](https://skills.sh/nutlope/hallmark/hallmark) |
| I Have ADHD | Makes agent responses actionable: clear next steps, bounded lists, visible progress, and concrete time estimates | [Skill page](https://skills.sh/ayghri/i-have-adhd/i-have-adhd) |
| img2threejs | Rebuilds an object or character reference as a procedural, animation-ready Three.js model | [Skill page](https://skills.sh/hoainho/img2threejs/img2threejs) |
| Find Skills | Searches the public agent-skills ecosystem and supplies install commands | [Skill page](https://skills.sh/vercel-labs/skills/find-skills) |
| Watch | Downloads a video, samples frames, reads captions/transcripts, and answers questions about it | [Skill page](https://skills.sh/bradautomates/claude-video/watch) |

```sh
npx skills add nutlope/hallmark@hallmark -g -y
npx skills add ayghri/i-have-adhd@i-have-adhd -g -y
npx skills add hoainho/img2threejs@img2threejs -g -y
npx skills add vercel-labs/skills@find-skills -g -y
npx skills add bradautomates/claude-video@watch -g -y
```

### Local-only skill

- **iOS Simulator Dev** — a custom workflow for building, launching, interacting with, and visually validating iOS apps in Simulator. It is installed locally but has no verified public package page, so it needs to be copied or published before someone else can install it.

## Enabled Codex plugins

These are installed through Codex's plugin system rather than `npx skills`. A friend can search for the same names in Codex's plugin picker.

| Plugin | What it adds |
|---|---|
| Browser | Controls Codex's in-app browser and tests local websites |
| Chrome | Uses existing Chrome tabs, logins, cookies, and extensions |
| Computer Use | Operates macOS apps through their visible UI |
| Documents | Creates, edits, renders, and verifies Word documents |
| PDF | Reads, creates, renders, and verifies PDFs |
| Presentations | Creates and edits PowerPoint or Google Slides-ready decks |
| Spreadsheets | Creates, analyzes, charts, and verifies Excel/Sheets-ready workbooks |
| Template Creator | Turns Office files into reusable artifact-template skills |
| Sites | Builds and publishes websites |
| Visualize | Creates interactive charts, maps, simulations, 3D views, and UI previews |
| Supabase | Manages Postgres, Auth, Storage, Edge Functions, migrations, and project tooling ([source](https://github.com/supabase-community/supabase-plugin)) |

Google Calendar and Slack entries exist in the local configuration, but their connector tools were not active when this inventory was made. Treat those as needing reconnection, not as share-ready installs.

## Built into Codex

These system skills are supplied by Codex and normally do not need separate installation:

- Image generation and image editing
- Current OpenAI product/API documentation
- Skill creation and installation
- Plugin creation

## Configured helper tools

- Supabase MCP connection
- iOS Simulator MCP tooling
- Persistent Node.js REPL for browser/app orchestration
- Local workflow hooks around tool use, compaction, session start, prompts, and task completion

## Notes

- Inventory date: July 23, 2026
- Public skill links and install package names were resolved through [skills.sh](https://skills.sh/).
- This file intentionally excludes local paths, credentials, tokens, project history, and private configuration.
