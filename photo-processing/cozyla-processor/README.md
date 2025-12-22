# Cozyla Photo Processor

Process photos for Cozyla digital picture frames - resizes images and strips motion photo video to prevent black image issues.

**Full Tutorial:** [Fixing Black Images on Your Cozyla Digital Frame](https://metrowestsmarthome.com/2025/12/21/fixing-black-images-on-your-cozyla-digital-frame/)

## The Problem

Cozyla frames (and many other digital frames) can display black images when:
- Photos are too high resolution (12MP+ from modern phones)
- Motion photos contain embedded video data (.MP.jpg files)
- Bulk uploads overwhelm the processing pipeline

## The Solution

This PowerShell script:
- Resizes images to 1920px max (optimized for 1280x800 frame)
- Strips embedded video from Google Pixel motion photos
- Preserves EXIF metadata (date taken, camera info, GPS)
- Organizes into 50-file batches (Cozyla's upload limit)
- Tracks uploads to prevent duplicates

## Requirements

- Windows with PowerShell 5.1+
- [ExifTool](https://exiftool.org/) for metadata handling

## Quick Start

1. **Create folder structure:**
```powershell
$BaseDir = "C:\Photos\cozyla-processor"  # Change to your location

@("scripts", "1-source", "2-converted", "3-uploaded", "4-skipped", "tracking") |
    ForEach-Object { New-Item -ItemType Directory -Path "$BaseDir\$_" -Force }

"# Uploaded files tracking" | Out-File "$BaseDir\tracking\uploaded-files.txt"
```

2. **Install ExifTool:**
```powershell
winget install exiftool --accept-package-agreements --accept-source-agreements
```

3. **Download the script** to `scripts\process-photos.ps1`

4. **Update the ExifTool path** in the script (line with `$ExifTool = ...`)

5. **Process photos:**
```powershell
# Drop photos into 1-source/, then:
.\scripts\process-photos.ps1

# After uploading to Cozyla:
.\scripts\process-photos.ps1 -ConfirmUpload
```

## Configuration

Edit these variables in the script:

| Variable | Default | Description |
|----------|---------|-------------|
| `$ExifTool` | (edit required) | Path to exiftool.exe |
| `$MaxImageDimension` | 1920 | Max pixels on longest side |
| `$JpegQuality` | 90 | JPEG compression quality (1-100) |
| `$BatchSize` | 50 | Files per batch folder |

## Folder Structure

```
cozyla-processor/
├── scripts/
│   └── process-photos.ps1
├── 1-source/          # Drop photos here
├── 2-converted/       # Ready for upload
├── 3-uploaded/        # Archived after upload
├── 4-skipped/         # Unsupported formats
└── tracking/
    └── uploaded-files.txt
```

## License

MIT License
