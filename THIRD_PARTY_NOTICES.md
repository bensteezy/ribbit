# third-party notices

ribbit is licensed under the MIT License. The following components are included
in downloadable builds and remain under their respective licenses. Complete
license texts are in `ThirdPartyLicenses/` in the repository and in
`ribbit.app/Contents/Resources/ThirdPartyLicenses/` in the application bundle.

| component | version | license |
| --- | --- | --- |
| Ghostty / libghostty | 1.3.1 | MIT |
| FreeType | 2.13.2 | FreeType License |
| libpng | 1.6.43 | PNG Reference Library License 2.0 |
| zlib | 1.3.1 | zlib License |
| Oniguruma | 6.9.9 | BSD-style |
| glslang | 14.2.0 | BSD-style and included notices |
| SPIRV-Cross | 13.1.1 | Apache-2.0 |
| Sentry Native | 0.7.8 | MIT |
| Breakpad | Ghostty-pinned revision | BSD-3-Clause |
| MPack | Sentry-vendored revision | MIT |
| simdutf | 5.2.8 | MIT |
| Highway | 1.2.0 | Apache-2.0 and BSD-3-Clause |
| utf8cpp | Ghostty-pinned revision | Boost Software License 1.0 |
| Dear ImGui | 1.92.5 docking | MIT |
| Dear Bindings | 0.17 | MIT |
| Wuffs | Ghostty-pinned revision | Apache-2.0 or MIT |
| Nerd Fonts Symbols Only | 3.4.0 | MIT |
| libxev | Ghostty-pinned revision | MIT |
| zig-objc | Ghostty-pinned revision | MIT |
| uucode | 0.2.0 | MIT, with included Unicode notices |
| z2d | 0.10.0 | MPL-2.0 |

The source for the MPL-2.0 component is available from the
[z2d v0.10.0 source tree](https://github.com/vancluever/z2d/tree/v0.10.0).
Ribbit does not modify z2d. The reproducible Ghostty bootstrap script records
the exact upstream archive, checksum, and dependency versions used by Ribbit.

Apple system frameworks and Swift runtime libraries shown by `otool` are
provided by macOS and are not redistributed as third-party source packages by
Ribbit.
