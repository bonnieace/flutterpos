# Stitch MCP capability inventory — 2026-08-20

This is a schema inventory of all 15 tools exposed by the connected `stitch` MCP server. No mutating
tool was called. “Existing screen” means the tool accepts an existing screen or screen-instance ID,
not merely an existing project.

| Exact tool name | What it does | Required parameters | Optional parameters | Read-only / mutating | Existing project | Existing screen | Creates variants | Canvas grouping/reorganization |
|---|---|---|---|---|---:|---:|---:|---|
| `apply_design_system` | Applies one design system's tokens to selected screen instances. | `assetId`, `projectId`, `selectedScreenInstances[]` (`id`, `sourceScreen`) | None | Mutating | Yes | Yes, by instance | No | No |
| `create_design_system` | Creates a design system from structured theme values. | `designSystem` (`displayName`, `theme.bodyFont`, `colorMode`, `customColor`, `headlineFont`, `roundness`) | `projectId`; theme `colorVariant`, `designMd`, `labelFont`, neutral/primary/secondary/tertiary overrides, `spacing`, `typography` | Mutating | Optional | No | No | No |
| `create_design_system_from_design_md` | Creates a project design system from a previously uploaded DESIGN.md instance. | `projectId`, `selectedScreenInstance` (`id`, `sourceScreen`) | `deviceType` | Mutating | Yes | Uploaded DESIGN.md instance only | No | No |
| `create_project` | Creates a Stitch project. | None | `title` | Mutating | No | No | No | No |
| `delete_project` | Permanently deletes a named project after confirmation. | `name` | None | Mutating/destructive | Yes | No | No | No |
| `edit_screens` | Edits selected existing screens using a text prompt. | `projectId`, `prompt`, `selectedScreenIds[]` | `deviceType`, `modelId` | Mutating | Yes | Yes | No | No |
| `generate_screen_from_text` | Generates a new screen in an existing project from a prompt. | `projectId`, `prompt` | `designSystem`, `deviceType`, `modelId` | Mutating | Yes | No | No | No |
| `generate_variants` | Generates 1-5 variants of selected screens. | `projectId`, `prompt`, `selectedScreenIds[]`, `variantOptions` | `deviceType`, `modelId`; options `aspects`, `creativeRange`, `variantCount` | Mutating | Yes | Yes | Yes | No |
| `get_project` | Retrieves project metadata and screen instances. | `name` | None | Read-only | Yes | No | No | No |
| `get_screen` | Retrieves one screen, including title, dimensions, screenshot, and HTML references. | `name`, `projectId`, `screenId` | None | Read-only | Yes | Yes | No | No |
| `list_design_systems` | Lists project-specific or global design systems. | None | `projectId` | Read-only | Optional | No | No | No |
| `list_projects` | Lists owned or shared projects. | None | `filter` (`view=owned` or `view=shared`) | Read-only | No | No | No | No |
| `list_screens` | Lists screens in a project. | `projectId` | None | Read-only | Yes | No specific target | No | No |
| `update_design_system` | Updates a named project design system and its structured theme. | `designSystem`, `name`, `projectId` | Theme `colorVariant`, `designMd`, `labelFont`, neutral/primary/secondary/tertiary overrides, `spacing`, `typography` | Mutating | Yes | No | No | No |
| `upload_design_md` | Uploads base64 UTF-8 DESIGN.md content and creates a design-MD screen instance for later conversion. | `designMdBase64`, `projectId` | None | Mutating | Yes | No; creates an instance | No | No explicit control |

## Canvas limitation

None of the 15 exposed tools directly moves, aligns, groups, labels, hides, renames, or reorders
existing screen instances on the project canvas. `upload_design_md` may return grouping/layout
metadata and generation may auto-place output, but neither provides explicit reorganization control.
Canvas housekeeping therefore needs the Stitch UI or a future MCP capability.
