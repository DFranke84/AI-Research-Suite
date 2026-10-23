# AI Research Suite

One place to install and update the four apps of the AI Research Suite:

| Piece | What it is |
|---|---|
| [AIPortable](https://github.com/DFranke84/AIPortable) | Full offline AI app: chat, library search, offline maps, Wikipedia |
| [AIPortable-JustAI](https://github.com/DFranke84/AIPortable-JustAI) | Slim offline AI app: chat and library search |
| [Research](https://github.com/DFranke84/Research) | Your offline library and the Library Manager |
| [LibraryViewer](https://github.com/DFranke84/LibraryViewer) | Read the library on a tablet |

People use AIPortable **or** JustAI, not both; Research and the Library Viewer are optional add-ons.
All pieces sit side by side in one folder, with this one next to them:

```
D:\AI-Research\
  AI-Research-Suite\    <- this repo (updater, later the installer)
  AIPortable-JustAI\
  Research\
  LibraryViewer\
```

## Updating

Double-click **Check for updates.bat**. It asks GitHub for the newest release of each installed
piece, shows what's new, and on your OK replaces only the program files. Chats, models, maps, the
library, notes and settings are never touched. Replaced files are saved in `backups\`, so
`update.ps1 -Rollback <piece>` can undo the last update.

No internet on that PC? Copy the release zips to a USB stick and run
`update.ps1 -Source F:\Updates`.

Folders that are git checkouts are left alone - update those with `git pull`.

## For the author: making a release

1. Bump the piece's `VERSION` file, commit, tag `v<version>`, push.
2. `tools\make-release.ps1 -Repo ..\<piece>` - writes `dist\<piece>-<version>.zip` and `.zip.sha256`.
3. Create the GitHub release for that tag and attach both files.

The zip is built from git, so only tracked files can be in it.

## Licence

MIT - see LICENSE.
