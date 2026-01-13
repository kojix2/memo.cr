# memo

[![Build macOS Package](https://github.com/kojix2/memo.cr/actions/workflows/mac.yml/badge.svg)](https://github.com/kojix2/memo.cr/actions/workflows/mac.yml)
[![Build MinGW Package](https://github.com/kojix2/memo.cr/actions/workflows/mingw.yml/badge.svg)](https://github.com/kojix2/memo.cr/actions/workflows/mingw.yml)
[![Build Debian Package](https://github.com/kojix2/memo.cr/actions/workflows/deb.yml/badge.svg)](https://github.com/kojix2/memo.cr/actions/workflows/deb.yml)
[![Lines of Code](https://img.shields.io/endpoint?url=https%3A%2F%2Ftokei.kojix2.net%2Fbadge%2Fgithub%2Fkojix2%2Fmemo.cr%2Flines)](https://tokei.kojix2.net/github/kojix2/memo.cr)
![Static Badge](https://img.shields.io/badge/PURE-VIBE_CODING-magenta)

Practice with [WebView](https://github.com/naqvis/webview)

<img width="1012" height="712" alt="image" src="https://github.com/user-attachments/assets/f1612da2-7e5c-494e-8df7-2b99e39cf396" />

- This project was made to explore how to build and distribute apps with Crystal and WebView in a simple and practical way.

- It’s not meant to be a serious note-taking app, though I do plan to use it from time to time myself.

## Installation

```sh
shards build --release -Dpreview_mt -Dexecution_context
```

Generate app package for your platform:

Debian/Ubuntu

```sh
./build-deb.sh   # for Debian/Ubuntu
```

macOS

```sh
./build-mac.sh
```

Windows

```sh
bash build-mingw.sh
```

```
powershell.exe -ExecutionPolicy Bypass -File package-win.ps1 # INNO SETUP
```

## Usage

```
bin/memo
```
