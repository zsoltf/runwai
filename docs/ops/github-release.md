# GitHub releases

runwai lives at [zsoltf/runwai](https://github.com/zsoltf/runwai).
Downloads live on its [Releases page](https://github.com/zsoltf/runwai/releases).

## Prepare

1. Update the version and build number in `project.yml` and add short release notes.
2. Run the build and tests. Refresh the README screenshot when the interface changes.
3. Follow [macOS signing and notarization](./macos-release.md). Use only the final
   `dist/runwai-macos.zip`, not the notarization upload archive.
4. Extract the zip, verify its signature and Gatekeeper acceptance, then open it
   and check live sync, Settings, all three Usage chart ranges, and Activity.

## Publish 0.3.0

Confirm the repository, branch, tag, and public destination before publishing.
The release tag must point to the exact tested source commit.

1. Merge the tested release changes into `main` and push the confirmed branch.
2. Open Releases and choose **Draft a new release**.
3. Create tag `v0.3.0` on that commit and title it `runwai 0.3.0`.
4. Paste `docs/product/release-notes-v0.3.0.md` and attach
   `build/release-0.3.0/dist/runwai-macos.zip`. Include `SHA256SUMS.txt` from the
   same folder if available. Do not upload `runwai-notary-upload.zip`.
5. Publish, then download that attachment and check the installation again.

Users quit runwai, unzip the download, and drag `runwai.app` into Applications,
replacing the previous copy. Existing local history and preferences stay intact.
