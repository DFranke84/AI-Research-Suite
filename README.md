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
  AI-Research-Suite\    <- this repo (installer helpers, updater)
  AIPortable-JustAI\
  Research\
  LibraryViewer\
```

## Installing

Download **Suite-Setup-&lt;version&gt;.exe** from the [latest release](https://github.com/DFranke84/AI-Research-Suite/releases/latest)
and double-click it. No administrator rights are needed. Setup:

1. checks the PC (Windows, memory, graphics card, free space, internet speed),
2. asks which pieces you want (AIPortable **or** JustAI, the Research library, the Library Viewer)
   and where to put them (it suggests the drive with the most room),
3. lets you pick an AI model size up to your graphics card's memory, a model, voice input and
   (AIPortable) offline map regions,
4. lets you pick starter packs (every page a full article), offline archives - complete English
   Wikipedia (text only, or with pictures) and about 40 more, as much or as little as you like -
   and a **Local Area** for where you live (plants, wildlife, fungi, weather, USGS topo maps and,
   for AIPortable, a street map of the area),
5. shows the download size, the space needed and about how long it will take,
6. then downloads and sets up everything in its own window. The PC is kept awake meanwhile, each
   step is tried three times, and partial downloads are kept: close it any time, or lose the
   connection, and running Setup again carries on from the same point.

Archives go into the Research library's folder when the library is installed (the AI apps read
them there), or into AIPortable's own folder when it is installed without the library. With a
full Wikipedia in the library, the Wikipedia articles pack and Local Area read their articles from
it instead of wikipedia.org, so Setup downloads it first.

Run Setup again later to **update and repair** (keeps your choices) or to **change your choices**.
Uninstalling asks whether to remove the apps' program files too; your chats, models, maps and
library are kept either way.

Windows may show "Windows protected your PC" because the installer isn't code-signed yet - click
**More info → Run anyway**.

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

The installer: `tools\build-installer.ps1` (needs Inno Setup 6) refreshes `installer\catalog.ini` from
the apps' own catalogs (models, maps, starter packs) and writes `dist\Suite-Setup-<VERSION>.exe`;
attach it to this repo's release. For an unattended test install:
`Suite-Setup-<v>.exe /VERYSILENT /DIR=C:\AI-Test\Suite /SOURCE=<folder of release zips> /PLANFILE=<plan.ini>`
(the plan.ini keys are listed at the top of `install.ps1`).

## Licence

MIT - see LICENSE.
