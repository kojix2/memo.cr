# PowerShell script for building Windows installer

$ErrorActionPreference = "Stop"

# Load configuration from .env
Get-Content .env | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]*)=(.*)$') {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim('"')
        Set-Variable -Name $name -Value $value -Scope Global
    }
}

# Override with environment variable if set
if ($env:INNO_SETUP_PATH) {
    $INNO_SETUP_PATH = $env:INNO_SETUP_PATH
}

# ARCH detection: env > .env (already loaded) > MSYSTEM hint > default
if (-not (Get-Variable -Name ARCH -ErrorAction SilentlyContinue)) { $ARCH = $null }
if ($env:ARCH) { $ARCH = $env:ARCH }
elseif ($env:MSYSTEM -match 'UCRT64') { $ARCH = 'ucrt64' }
elseif ($env:MSYSTEM -match 'MINGW64') { $ARCH = 'mingw64' }
if (-not $ARCH) { $ARCH = 'mingw64' }

$EXECUTABLE_PATH = "bin/$APP_NAME.exe"
$DIST_DIR = "dist"
$INSTALLER_BASE = "${APP_NAME}_${VERSION}_${ARCH}_setup"
$INSTALLER_NAME = "$INSTALLER_BASE.exe"
$ISS_FILE = "$APP_NAME.iss"
$OUTPUT_DIR = "Output"

# Use Inno Setup compiler from configuration
$ISCC = $INNO_SETUP_PATH
if (-not $ISCC -or -not (Test-Path $ISCC)) {
    Write-Error "Error: Inno Setup not found at '$ISCC'. Please set INNO_SETUP_PATH in .env file or environment variable."
    Write-Host "Example: INNO_SETUP_PATH=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
    exit 1
}

# Check if executable exists (should be built by MSYS2)
if (-not (Test-Path $EXECUTABLE_PATH)) {
    Write-Error "Error: Executable not found at '$EXECUTABLE_PATH'. Please build first with 'shards build --release'"
    exit 1
}

Write-Host "Creating installer for $APP_NAME v$VERSION..."

if (Test-Path $DIST_DIR) { Remove-Item $DIST_DIR -Recurse -Force }
if (Test-Path $OUTPUT_DIR) { Remove-Item $OUTPUT_DIR -Recurse -Force }
New-Item -ItemType Directory -Path $DIST_DIR | Out-Null
New-Item -ItemType Directory -Path $OUTPUT_DIR | Out-Null

# Generate .ico from .png
if (Test-Path "resources\app_icon.png") {
    Write-Host "Generating app_icon.ico from app_icon.png..."
    
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    
    try {
        # Load the PNG image
        $pngPath = (Resolve-Path "resources\app_icon.png").Path
        $icoPath = (Join-Path $PWD "resources\app_icon.ico")
        
        # Load the original image
        $originalImage = [System.Drawing.Image]::FromFile($pngPath)
        
        # Create a bitmap with 32x32 size (standard for ICO)
        $bitmap = New-Object System.Drawing.Bitmap(32, 32)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.DrawImage($originalImage, 0, 0, 32, 32)
        $graphics.Dispose()
        
        # Create icon from bitmap
        $iconHandle = $bitmap.GetHicon()
        $icon = [System.Drawing.Icon]::FromHandle($iconHandle)
        
        # Save the icon to file
        $fileStream = [System.IO.FileStream]::new($icoPath, [System.IO.FileMode]::Create)
        $icon.Save($fileStream)
        $fileStream.Close()
        
        # Clean up resources
        $icon.Dispose()
        $bitmap.Dispose()
        $originalImage.Dispose()
        
        # Verify the file was created
        if (Test-Path $icoPath) {
            Write-Host "Successfully generated resources\app_icon.ico"
        }
        else {
            throw "ICO file was not created"
        }
    }
    catch {
        Write-Error "Failed to generate ICO from PNG: $_"
        Write-Host "Build cannot continue without icon file."
        exit 1
    }
}
else {
    Write-Error "PNG icon file not found at resources\app_icon.png"
    exit 1
}

# Create Inno Setup script using here-string
$issContent = @"
[Setup]
AppName=$APP_NAME_CAPITALIZED
AppVersion=$VERSION
DefaultDirName={userpf}\$APP_NAME_CAPITALIZED
DefaultGroupName=$APP_NAME_CAPITALIZED
OutputDir=$OUTPUT_DIR
OutputBaseFilename=$INSTALLER_BASE
Compression=lzma
SolidCompression=yes
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\app_icon.ico

[Files]
Source: "$EXECUTABLE_PATH"; DestDir: "{app}"; Flags: ignoreversion
Source: "README.md"; DestDir: "{app}"; Flags: isreadme ignoreversion
Source: "resources\app_icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\$APP_NAME_CAPITALIZED"; Filename: "{app}\$APP_NAME.exe"; IconFilename: "{app}\app_icon.ico"
Name: "{group}\Uninstall $APP_NAME_CAPITALIZED"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\$APP_NAME.exe"; Description: "Launch $APP_NAME_CAPITALIZED"; Flags: nowait postinstall skipifsilent
"@

$issContent | Out-File -FilePath $ISS_FILE -Encoding UTF8

& $ISCC $ISS_FILE

# Copy versioned standalone exe
$exeOut = Join-Path $DIST_DIR ("${APP_NAME}_${VERSION}_${ARCH}.exe")
Copy-Item $EXECUTABLE_PATH $exeOut -Force | Out-Null
# Move versioned installer
if (Test-Path (Join-Path $OUTPUT_DIR $INSTALLER_NAME)) {
    Move-Item (Join-Path $OUTPUT_DIR $INSTALLER_NAME) $DIST_DIR -Force
}

Remove-Item $OUTPUT_DIR -Recurse -Force
Remove-Item $ISS_FILE

Write-Host "Created: dist\${APP_NAME}_${VERSION}_${ARCH}.exe"
Write-Host "Created: dist\$INSTALLER_NAME"
