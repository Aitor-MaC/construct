# Contributing

Thanks for wanting to help! Bug reports, ideas and pull requests are welcome.

## Before you start

- For anything bigger than a small fix, open an issue first so we can agree on the approach.
- Security problems: follow [SECURITY.md](SECURITY.md) instead of opening an issue.

## Development

- Xcode with Swift 6 and macOS 27.2 or later.
- Always open `Macterminal.xcworkspace`.
- To sign with your own account, choose your team in the target's **Signing & Capabilities** tab, or add `DEVELOPMENT_TEAM=<your team ID>` to `xcodebuild`.

```bash
# Logic tests (local package)
swift test --package-path Packages/MacterminalCore --parallel

# App build and all tests, in English and Spanish
xcodebuild test -workspace Macterminal.xcworkspace -scheme Macterminal \
  -destination 'platform=macOS' -skipPackagePluginValidation -testLanguage en -testRegion US
xcodebuild test -workspace Macterminal.xcworkspace -scheme Macterminal \
  -destination 'platform=macOS' -skipPackagePluginValidation -testLanguage es -testRegion ES
```

## Pull requests

- Keep pure logic in `Packages/MacterminalCore` and cover it with Swift Testing tests. A test should fail without your change.
- No warnings in the project's own code.
- User-visible text goes through `String(localized:comment:)` and needs both English and Spanish entries in the string catalogs.
- Don't weaken the protections listed in [SECURITY.md](SECURITY.md) (nonce-signed shell messages, literal prompt values, no clipboard writes from programs).

By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE).
