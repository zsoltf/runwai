# CI/CD

This repo uses one GitHub Actions workflow for pull requests and pushes to `main`.

## What CI runs

CI runs a single macOS job:

1. select Xcode 16.0
2. install `xcodegen`
3. generate the project
4. build the app
5. run the test suite

Workflow file:

- `.github/workflows/ci.yml`

## Local equivalent

Run the same steps locally from the repo root:

```bash
xcodegen generate
xcodebuild -project runwai.xcodeproj -scheme Runwai -destination "platform=macOS" build
xcodebuild -project runwai.xcodeproj -scheme Runwai -destination "platform=macOS" test
```

## Run one step locally

Build only:

```bash
xcodebuild -project runwai.xcodeproj -scheme Runwai -destination "platform=macOS" build
```

Test only:

```bash
xcodebuild -project runwai.xcodeproj -scheme Runwai -destination "platform=macOS" test
```

## Update tool versions

- Xcode version is set in `.github/workflows/ci.yml` and `project.yml`
- if the repo moves to a newer Xcode, update both places together
- if `xcodegen` ever needs pinning, replace `brew install xcodegen` with a versioned install step

## Common failures

- `xcodegen: command not found`
  - install it locally with `brew install xcodegen`
- Xcode version mismatch
  - check `xcodebuild -version`
  - align local Xcode with `project.yml` and CI
- generated project drift
  - rerun `xcodegen generate`
  - commit the updated `runwai.xcodeproj/project.pbxproj`
- test failures after UI or sync changes
  - rerun the exact `xcodebuild ... test` command locally to reproduce before pushing
