# Release Checklist

## Launcher and script versioning

When the .ps1 version bumps (for example, v3.6.ps1 -> v3.7.ps1), regenerate Run-Koolbox.bat so its -File reference matches the new filename. The .bat must always sit in the same directory as the .ps1.

Write the .bat with CRLF line endings, a trailing newline, and ANSI-compatible plain ASCII content

## Release assets

Every GitHub release ships THREE assets:

1. The .ps1 raw script.
2. Run-Koolbox.bat.
3. Optionally, the compiled Wilko Koolbox.exe from task [C].

## README requirements

README must document: double-click the .bat -> approve UAC -> menu. Fallback: right-click .ps1 -> Run with PowerShell.

## Publication rule

Never push, tag, or publish without explicit user approval.
