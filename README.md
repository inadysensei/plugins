# inady agent plugins

Official inady agent plugins for development, office work, and other tasks.
Each plugin is a standalone directory at the repository root with its own .cursor-plugin/plugin.json manifest.

## Plugins

| Plugin |Description |
|--------|--------|
| [motoki](plugins/motoki) | `motoki` is a tool that helps you work with AI agents. |
| [aws-security-hub](plugins/aws-security-hub) | AWSのSecurity Hub FSBPを読み、失敗を直すか抑制するかに分けて先へ進める。 |

## Installation(Cursor)

1. Open **Settings → Plugins**.
2. Click `+Add`
3. Choose **From GitHub Repository** and paste:
   `https://github.com/inadysensei/plugins`
4. Search `motoki` or `aws-security-hub` and click `Add`

## Installation(skills command)

1. Run `npx skills add inadysensei/plugins`
