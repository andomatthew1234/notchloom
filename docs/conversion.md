# Convert in Notchloom

Drag one or more files onto **Convert** in the File Shelf. Notchloom checks the actual file contents, offers compatible outputs, then saves a new file beside the original. The first conversion from a folder may ask you to allow write access to that folder. You can select a different output folder in the converter's settings. Sources are never overwritten; name collisions get a number or date suffix.

The picker is based on what this Mac can encode. An output may be absent if its system encoder or optional tool is unavailable, or if a particular source cannot be safely converted. Mixed drops are handled in groups; files with no common output are presented one at a time.

## Implemented engines

| Engine | Inputs | Outputs | Status |
| --- | --- | --- | --- |
| macOS ImageIO | Single-frame images it can decode, including PNG, JPEG, TIFF, HEIC and supported RAW files | PNG, JPEG, TIFF, GIF, HEIC, BMP, WebP, AVIF when the system encoder passes a live preflight | PNG to JPEG/TIFF/BMP and the Notchloom logo to TIFF/GIF/HEIC/BMP/AVIF were encoded and decoded in automated tests. Output availability varies by macOS. |
| AVFoundation | Media with decodable audio/video tracks | MOV, MP4, or M4A when the asset export session supports them | WAV to M4A and MOV to MP4 were generated and probed in automated tests. The system chooses the media codec for native exports. |
| macOS `textutil` | TXT, RTF, HTML, DOC, DOCX, ODT when `textutil -info` recognizes the file | Other formats in that set | TXT to DOCX to RTF was tested; the text was recovered from the final output. Complex layout can change. |
| macOS `ditto` | Folders | ZIP | Folder to ZIP was tested, integrity checked, extracted, and compared with the original content. ZIP extraction is not exposed. |
| FFmpeg and FFprobe (optional) | Media FFprobe recognizes | MP4/H.264, MP4/HEVC, MKV/H.264, WebM/VP9, MP3, FLAC, WAV, Opus, M4A/AAC when the installed build reports the required encoder and muxer | Dynamically detected, but not conversion-tested on the development Mac because FFmpeg is not installed. |

FFmpeg is optional. To enable its additional media formats, install an official FFmpeg build that includes `ffprobe` at `/opt/homebrew/bin` or `/usr/local/bin`, then restart Notchloom. Notchloom does not run package-manager installers or download conversion binaries. The native engines work without FFmpeg.

## Safety and current limits

- ImageIO rejects animated and multipage images rather than dropping frames. JPEG is hidden for transparent sources. GIF has only 256 colors, and soft transparency can change.
- Quality presets change compression where the engine supports it. A lossless output cannot restore quality already lost in its input.
- Document formatting, fonts, embedded objects, formulas, and macros may change or be lost. PDF to editable document, office spreadsheets/slides, ebooks, font conversion, SVG rasterization, and archive extraction are not implemented in this release.
- The converter uses a temporary output in the destination folder and moves it into place after decode/integrity checks. Cancellation and failure remove the incomplete temporary output.
- External tools are launched with fixed executable paths and argument arrays. File names are never interpolated into shell commands.

Run `zsh tests/run-conversion-checks.sh` to execute the conversion smoke tests. These tests use disposable files and verify output contents, not just process exit codes.
