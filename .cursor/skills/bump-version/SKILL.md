---
name: bump-plugin-version
description: >-
  Bump this repository's plugin and marketplace versions together.
  Use when the user asks to raise, bump, or increment the version or you update the plugin.
---

# Bump plugin version

Raise these fields by the same amount. If the user names an increment such as `0.0.1`, add it to the current semver. If they name a target version, set that.

- `plugins/*/plugin.json` — `version`
- `plugins/*/.cursor-plugin/plugin.json` — `version`
- `.cursor-plugin/marketplace.json` — `metadata.version`

