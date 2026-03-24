# GitHub hosting and release

This is the clean path for publishing a new `runwai` download on GitHub.

Current GitHub references:

- [Creating a new repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-new-repository)
- [Managing releases in a repository](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)

## 1. create the repo

Create a repo named `runwai`.

Use:

- owner: your personal account
- visibility: public for launch, private for one more quiet pass
- no README from GitHub
- no `.gitignore` from GitHub

## 2. push the local repo

From this folder:

```bash
cd /path/to/runwai
git init
git add .
git commit -m "Initial runwai release prep"
git branch -M main
git remote add origin git@github.com:YOUR_GITHUB_USERNAME/runwai.git
git push -u origin main
```

If you want the GitHub CLI path instead:

```bash
cd /path/to/runwai
gh repo create runwai --public --source=. --remote=origin --push
```

## 3. make the repo page look good

Set:

- description: `macOS menu bar pacing for codex, spark, and gemini`
- website: leave blank until the release exists
- topics: `macos`, `swiftui`, `menubar`, `ai-tools`, `productivity`

The README screenshot already lives at:

- `docs/assets/runwai-codex.png`

## 4. prepare the signed build

Follow:

- [macOS signing and notarization](./macos-release.md)

The output you want is:

- `build/release/dist/runwai-macos.zip`

## 5. publish the next release

Web flow:

1. open the repo
2. click `Releases`
3. click `Draft a new release`
4. create tag `v0.1.1`
5. title it `runwai 0.1.1`
6. upload `build/release/dist/runwai-macos.zip`
7. paste short notes
8. publish

CLI flow:

```bash
gh release create v0.1.1 \
  build/release/dist/runwai-macos.zip \
  --title "runwai 0.1.1" \
  --notes-file docs/product/release-notes-v0.1.1.md
```

## 6. final pre-post check

Do not post yet unless all of these are true:

- README renders cleanly
- screenshot loads
- release zip downloads
- app opens on another Mac without scary warnings
- `spctl` accepts the release build

Then post the release when the repo page, download flow, and install flow all feel clean.
