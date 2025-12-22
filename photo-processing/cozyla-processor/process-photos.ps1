<#
.SYNOPSIS
    Process photos for Cozyla digital frame - strips motion photo video, resizes, and tracks uploads.

    Full Tutorial: https://metrowestsmarthome.com/2025/12/21/fixing-black-images-on-your-cozyla-digital-frame/

.DESCRIPTION
    - Validates file formats against Cozyla supported types
    - Strips embedded video from Google Pixel motion photos (.MP.jpg)
    - Resizes images to max 1920px on longest side (optimized for 1280x800 frame)
    - Renames files (removes .MP from extension)
    - Checks for duplicates against previously uploaded files
    - Moves processed files to 2-converted/ folder
    - Creates batch folders (batch-1, batch-2, etc.) if more than 50 files
    - Moves unsupported files to 4-skipped/ folder

.PARAMETER ConfirmUpload
    After manually uploading, run with this flag to mark batch as uploaded.
    Moves files from 2-converted/ to 3-uploaded/ and updates tracking file.

.PARAMETER NoResize
    Skip resizing step (not recommended - may cause black images on Cozyla)

.EXAMPLE
    .\process-photos.ps1
    # Process new photos in 1-source/

.EXAMPLE
    .\process-photos.ps1 -ConfirmUpload
    # Mark current batch as uploaded after manual upload to Cozyla
#>

param(
    [switch]$ConfirmUpload,
    [switch]$NoResize
)

# ============================================
# COZYLA SUPPORTED FORMATS & SETTINGS
# ============================================
# NOTE: This pipeline is for IMAGES ONLY. Videos are skipped.
$SupportedPhotoExtensions = @('.jpg', '.jpeg', '.png', '.bmp', '.webp')
$VideoExtensions = @('.mp4', '.mov', '.avi', '.mkv')
$UnsupportedExtensions = @('.gif', '.tiff', '.tif', '.raw', '.heic', '.heif', '.svg', '.psd')

# Cozyla 10.1" frame: 1280x800 native resolution
# Resize to 1920px max (1.5x frame resolution for quality headroom)
$MaxImageDimension = 1920
$JpegQuality = 90

# Cozyla web interface batch limit
$BatchSize = 50

# ============================================
# PATHS - UPDATE THESE FOR YOUR SYSTEM
# ============================================
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptRoot
$SourceDir = Join-Path $ProjectRoot "1-source"
$ConvertedDir = Join-Path $ProjectRoot "2-converted"
$UploadedDir = Join-Path $ProjectRoot "3-uploaded"
$SkippedDir = Join-Path $ProjectRoot "4-skipped"
$TrackingFile = Join-Path $ProjectRoot "tracking\uploaded-files.txt"

# UPDATE THIS PATH to your ExifTool installation
$ExifTool = "YOUR_EXIFTOOL_PATH\exiftool.exe"

# Ensure directories exist
@($ConvertedDir, $UploadedDir, $SkippedDir) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
}

# Verify ExifTool exists
if (-not (Test-Path $ExifTool)) {
    Write-Error "ExifTool not found at: $ExifTool"
    Write-Host "Please install ExifTool or update the path in this script."
    Write-Host "Install via: winget install exiftool --accept-package-agreements --accept-source-agreements"
    exit 1
}

# Load System.Drawing for image resizing
Add-Type -AssemblyName System.Drawing

# Load previously uploaded files
$UploadedFiles = @()
if (Test-Path $TrackingFile) {
    $UploadedFiles = Get-Content $TrackingFile | Where-Object { $_ -and $_ -notmatch '^#' }
}

function Get-CleanFilename {
    param([string]$Filename)
    return $Filename -replace '\.MP\.jpg$', '.jpg' -replace '\.MP\.jpeg$', '.jpeg'
}

function Get-SkipReason {
    param([string]$Extension, [switch]$IsVideo)
    $ext = $Extension.ToLower()

    if ($IsVideo) {
        return "VIDEO - This pipeline is for images only. Upload videos manually via Cozyla app."
    }

    switch ($ext) {
        '.gif'  { return "GIF - Cozyla does not support animated GIFs" }
        '.heic' { return "HEIC - Apple format not natively supported (convert to JPEG first)" }
        '.heif' { return "HEIF - Apple format not natively supported (convert to JPEG first)" }
        '.tiff' { return "TIFF - Not supported by digital frames" }
        '.tif'  { return "TIFF - Not supported by digital frames" }
        '.raw'  { return "RAW - Camera raw format not supported (convert to JPEG first)" }
        '.svg'  { return "SVG - Vector format not supported" }
        '.psd'  { return "PSD - Photoshop format not supported" }
        default { return "Unknown/unsupported format" }
    }
}

function Resize-ImageFile {
    param(
        [string]$SourcePath,
        [string]$DestPath,
        [int]$MaxDimension,
        [int]$Quality = 90
    )

    try {
        # Load the image
        $image = [System.Drawing.Image]::FromFile($SourcePath)
        $originalWidth = $image.Width
        $originalHeight = $image.Height

        # Check if resizing is needed
        if ($originalWidth -le $MaxDimension -and $originalHeight -le $MaxDimension) {
            $image.Dispose()
            return @{ Resized = $false; OriginalSize = "$originalWidth x $originalHeight" }
        }

        # Calculate new dimensions maintaining aspect ratio
        if ($originalWidth -gt $originalHeight) {
            $newWidth = $MaxDimension
            $newHeight = [int]($originalHeight * ($MaxDimension / $originalWidth))
        } else {
            $newHeight = $MaxDimension
            $newWidth = [int]($originalWidth * ($MaxDimension / $originalHeight))
        }

        # Create new bitmap with new dimensions
        $newImage = New-Object System.Drawing.Bitmap($newWidth, $newHeight)
        $graphics = [System.Drawing.Graphics]::FromImage($newImage)

        # Set high quality rendering
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

        # Draw the resized image
        $graphics.DrawImage($image, 0, 0, $newWidth, $newHeight)

        # Set up JPEG encoder with quality setting
        $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
        $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, $Quality)

        # Save the resized image
        $newImage.Save($DestPath, $jpegCodec, $encoderParams)

        # Clean up
        $graphics.Dispose()
        $newImage.Dispose()
        $image.Dispose()

        # Copy EXIF metadata from original to resized image using ExifTool
        # This preserves date taken, camera info, GPS, etc.
        $exifCopyResult = & $ExifTool -overwrite_original -TagsFromFile $SourcePath "-all:all>all:all" $DestPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    Warning: Could not copy EXIF data" -ForegroundColor Yellow
        }

        return @{
            Resized = $true
            OriginalSize = "$originalWidth x $originalHeight"
            NewSize = "$newWidth x $newHeight"
        }
    }
    catch {
        if ($image) { $image.Dispose() }
        throw $_
    }
}

function Organize-IntoBatches {
    param([string]$Directory)

    $Files = Get-ChildItem -Path $Directory -File -ErrorAction SilentlyContinue
    if (-not $Files -or $Files.Count -eq 0) { return }

    if ($Files.Count -le $BatchSize) {
        Write-Host "`n$($Files.Count) files ready for upload (no batching needed)" -ForegroundColor Green
        return
    }

    $BatchCount = [math]::Ceiling($Files.Count / $BatchSize)
    Write-Host "`nOrganizing $($Files.Count) files into $BatchCount batches of up to $BatchSize..." -ForegroundColor Cyan

    $FileIndex = 0
    for ($i = 1; $i -le $BatchCount; $i++) {
        $BatchDir = Join-Path $Directory "batch-$i"
        if (-not (Test-Path $BatchDir)) {
            New-Item -ItemType Directory -Path $BatchDir -Force | Out-Null
        }

        $BatchFiles = $Files | Select-Object -Skip $FileIndex -First $BatchSize
        foreach ($File in $BatchFiles) {
            $Dest = Join-Path $BatchDir $File.Name
            Move-Item -Path $File.FullName -Destination $Dest -Force
        }

        Write-Host "  batch-${i}: $($BatchFiles.Count) files" -ForegroundColor Green
        $FileIndex += $BatchSize
    }

    Write-Host "`nUpload each batch folder separately via Cozyla web interface (50 file limit per upload)" -ForegroundColor Yellow
}

# ============================================
# CONFIRM UPLOAD MODE
# ============================================
if ($ConfirmUpload) {
    $DirectFiles = Get-ChildItem -Path $ConvertedDir -File -ErrorAction SilentlyContinue
    $BatchDirs = Get-ChildItem -Path $ConvertedDir -Directory -Filter "batch-*" -ErrorAction SilentlyContinue
    $BatchFiles = @()
    if ($BatchDirs) {
        $BatchFiles = $BatchDirs | ForEach-Object { Get-ChildItem -Path $_.FullName -File -ErrorAction SilentlyContinue }
    }

    $AllFiles = @($DirectFiles) + @($BatchFiles) | Where-Object { $_ }

    if (-not $AllFiles -or $AllFiles.Count -eq 0) {
        Write-Host "No files in 2-converted/ to confirm." -ForegroundColor Yellow
        exit 0
    }

    Write-Host "`n=== CONFIRMING UPLOAD ===" -ForegroundColor Cyan
    Write-Host "Files to mark as uploaded: $($AllFiles.Count)"

    foreach ($File in $AllFiles) {
        $Dest = Join-Path $UploadedDir $File.Name
        Move-Item -Path $File.FullName -Destination $Dest -Force
        Add-Content -Path $TrackingFile -Value $File.Name
        Write-Host "  Archived: $($File.Name)" -ForegroundColor Green
    }

    if ($BatchDirs) {
        foreach ($BatchDir in $BatchDirs) {
            if ((Get-ChildItem -Path $BatchDir.FullName -ErrorAction SilentlyContinue).Count -eq 0) {
                Remove-Item -Path $BatchDir.FullName -Force
            }
        }
    }

    Write-Host "`nBatch marked as uploaded!" -ForegroundColor Green
    Write-Host "Files moved to: 3-uploaded/"
    Write-Host "Tracking file updated: tracking/uploaded-files.txt"
    exit 0
}

# ============================================
# PROCESS MODE
# ============================================
Write-Host "`n=== PROCESSING PHOTOS FOR COZYLA ===" -ForegroundColor Cyan
if (-not $NoResize) {
    Write-Host "Resizing enabled: Max ${MaxImageDimension}px (optimized for 1280x800 frame)" -ForegroundColor Gray
}

$SourceFiles = Get-ChildItem -Path $SourceDir -File -Recurse -ErrorAction SilentlyContinue

if (-not $SourceFiles -or $SourceFiles.Count -eq 0) {
    Write-Host "No files found in 1-source/" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($SourceFiles.Count) file(s) to process`n"

$Processed = 0
$Skipped = 0
$SkippedUnsupported = 0
$Duplicates = @()
$MotionPhotosStripped = 0
$ImagesResized = 0
$RegularPhotos = 0
$SkippedFiles = @()

foreach ($File in $SourceFiles) {
    $OriginalName = $File.Name
    $Extension = $File.Extension.ToLower()
    $CleanName = Get-CleanFilename $OriginalName

    Write-Host "Processing: $OriginalName" -ForegroundColor White

    # Check if it's a video - skip videos (images only pipeline)
    if ($Extension -in $VideoExtensions) {
        $Reason = Get-SkipReason -Extension $Extension -IsVideo
        Write-Host "  SKIPPED: $Reason" -ForegroundColor Yellow

        $SkipDest = Join-Path $SkippedDir $OriginalName
        Move-Item -Path $File.FullName -Destination $SkipDest -Force

        $SkippedFiles += [PSCustomObject]@{
            Filename = $OriginalName
            Reason = $Reason
        }
        $SkippedUnsupported++
        continue
    }

    # Check if format is supported
    if ($Extension -in $UnsupportedExtensions -or
        ($Extension -notin $SupportedPhotoExtensions)) {

        $Reason = Get-SkipReason -Extension $Extension
        Write-Host "  SKIPPED: $Reason" -ForegroundColor Red

        $SkipDest = Join-Path $SkippedDir $OriginalName
        Move-Item -Path $File.FullName -Destination $SkipDest -Force

        $SkippedFiles += [PSCustomObject]@{
            Filename = $OriginalName
            Reason = $Reason
        }
        $SkippedUnsupported++
        continue
    }

    # Check for duplicates
    if ($UploadedFiles -contains $CleanName) {
        Write-Host "  DUPLICATE: Already uploaded previously" -ForegroundColor Yellow
        $Duplicates += $OriginalName
        $Skipped++
        continue
    }

    # Check if it's a motion photo (.MP.jpg)
    $IsMotionPhoto = $OriginalName -match '\.MP\.(jpg|jpeg)$'

    # Destination file
    $DestFile = Join-Path $ConvertedDir $CleanName

    if ($IsMotionPhoto) {
        Write-Host "  Motion photo detected - stripping video..." -ForegroundColor Yellow

        # First copy, then strip, then resize
        Copy-Item -Path $File.FullName -Destination $DestFile -Force
        $ExifResult = & $ExifTool -overwrite_original -trailer:all= $DestFile 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Video stripped successfully" -ForegroundColor Green
            $MotionPhotosStripped++
        } else {
            Write-Host "  Warning: ExifTool returned non-zero exit code" -ForegroundColor Yellow
        }

        # Now resize the stripped image
        if (-not $NoResize) {
            try {
                $TempFile = $DestFile + ".tmp"
                $resizeResult = Resize-ImageFile -SourcePath $DestFile -DestPath $TempFile -MaxDimension $MaxImageDimension -Quality $JpegQuality

                if ($resizeResult.Resized) {
                    Remove-Item $DestFile -Force
                    Move-Item $TempFile $DestFile -Force
                    Write-Host "  Resized: $($resizeResult.OriginalSize) -> $($resizeResult.NewSize)" -ForegroundColor Cyan
                    $ImagesResized++
                } else {
                    Remove-Item $TempFile -Force -ErrorAction SilentlyContinue
                    Write-Host "  Size OK: $($resizeResult.OriginalSize) (no resize needed)" -ForegroundColor Gray
                }
            }
            catch {
                Write-Host "  Warning: Resize failed - keeping original size" -ForegroundColor Yellow
            }
        }
    }
    else {
        # Regular image - resize if needed
        if (-not $NoResize) {
            try {
                $resizeResult = Resize-ImageFile -SourcePath $File.FullName -DestPath $DestFile -MaxDimension $MaxImageDimension -Quality $JpegQuality

                if ($resizeResult.Resized) {
                    Write-Host "  Resized: $($resizeResult.OriginalSize) -> $($resizeResult.NewSize)" -ForegroundColor Cyan
                    $ImagesResized++
                } else {
                    # No resize needed, just copy
                    Copy-Item -Path $File.FullName -Destination $DestFile -Force
                    Write-Host "  Size OK: $($resizeResult.OriginalSize) (no resize needed)" -ForegroundColor Gray
                }
                $RegularPhotos++
            }
            catch {
                Write-Host "  Warning: Resize failed - copying original" -ForegroundColor Yellow
                Copy-Item -Path $File.FullName -Destination $DestFile -Force
                $RegularPhotos++
            }
        } else {
            Copy-Item -Path $File.FullName -Destination $DestFile -Force
            Write-Host "  Regular photo - no conversion needed" -ForegroundColor Gray
            $RegularPhotos++
        }
    }

    # Remove original from source
    Remove-Item -Path $File.FullName -Force

    Write-Host "  -> $CleanName (ready for upload)" -ForegroundColor Green
    $Processed++
}

# ============================================
# ORGANIZE INTO BATCHES IF NEEDED
# ============================================
if ($Processed -gt 0) {
    Organize-IntoBatches -Directory $ConvertedDir
}

# ============================================
# SUMMARY
# ============================================
Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Processed: $Processed file(s)"
Write-Host "  - Motion photos stripped: $MotionPhotosStripped"
Write-Host "  - Images resized: $ImagesResized"
Write-Host "  - Regular photos: $RegularPhotos"
Write-Host "Skipped (duplicates): $Skipped"
Write-Host "Skipped (unsupported): $SkippedUnsupported"

if ($SkippedFiles.Count -gt 0) {
    Write-Host "`n=== UNSUPPORTED FILES (moved to 4-skipped/) ===" -ForegroundColor Red
    foreach ($Skip in $SkippedFiles) {
        Write-Host "  - $($Skip.Filename)" -ForegroundColor Yellow
        Write-Host "    Reason: $($Skip.Reason)" -ForegroundColor Gray
    }
}

if ($Duplicates.Count -gt 0) {
    Write-Host "`n=== DUPLICATES (left in 1-source/) ===" -ForegroundColor Yellow
    foreach ($Dup in $Duplicates) {
        Write-Host "  - $Dup"
    }
    Write-Host "These files were already uploaded previously. Delete them manually if not needed."
}

if ($Processed -gt 0) {
    Write-Host "`n=== NEXT STEPS ===" -ForegroundColor Cyan
    Write-Host "1. Upload photos from 2-converted/ to Cozyla frame"
    if ($Processed -gt $BatchSize) {
        Write-Host "   (Upload each batch-N folder separately - 50 file limit per upload)"
    }
    Write-Host "2. Run: .\process-photos.ps1 -ConfirmUpload"
}

Write-Host "`n=== COZYLA OPTIMIZATION ===" -ForegroundColor DarkGray
Write-Host "Images resized to max ${MaxImageDimension}px (frame is 1280x800)" -ForegroundColor DarkGray
Write-Host "JPEG quality: ${JpegQuality}%" -ForegroundColor DarkGray
