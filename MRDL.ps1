# --------------------------
# Cross-platform Modrinth Downloader
# Windows + Linux compatible PowerShell script
# --------------------------

$ErrorActionPreference = "Stop"

# --------------------------
# Script Root
# --------------------------
if ($PSScriptRoot -and $PSScriptRoot.Trim() -ne "") {
    $ScriptDir = $PSScriptRoot
} else {
    $ScriptDir = (Get-Location).Path
}

# --------------------------
# Default Config
# --------------------------
$configPath = Join-Path $ScriptDir "config.json"

$defaultConfig = [ordered]@{
    preferredGameVersion = ""
    preferredLoaders = @("fabric")

    modpacksFile = "modpacks.txt"
    modsFile = "mods.txt"

    modpacksOutput = "Modpacks"
    modsOutput = "StandaloneMods"

    downloadModpacks = $true
    downloadStandaloneMods = $true

    keepMrpackFile = $true
    copyOverrides = $true

    userAgent = "ModrinthDownloader/1.0"
}

# --------------------------
# Path Helper
# --------------------------
function Resolve-AppPath {
    param(
        [string]$PathValue
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }

    return Join-Path $ScriptDir $PathValue
}

# --------------------------
# Config Helpers
# --------------------------
function Save-Config {
    param(
        [string]$Path,
        [object]$Config
    )

    $json = $Config | ConvertTo-Json -Depth 20
    Set-Content -Path $Path -Value $json -Encoding UTF8
}

function Merge-ConfigWithDefaults {
    param(
        [object]$Config,
        [hashtable]$Defaults
    )

    foreach ($key in $Defaults.Keys) {
        if (-not $Config.PSObject.Properties.Name.Contains($key)) {
            $Config | Add-Member -MemberType NoteProperty -Name $key -Value $Defaults[$key]
            continue
        }

        if ($null -eq $Config.$key) {
            $Config.$key = $Defaults[$key]
        }
    }

    return $Config
}

function Ensure-TextFile {
    param(
        [string]$Path,
        [string[]]$Lines
    )

    if (!(Test-Path $Path)) {
        $parent = Split-Path $Path -Parent

        if ($parent -and !(Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        Set-Content -Path $Path -Value $Lines -Encoding UTF8
        Write-Host "Created $Path"
    }
}

# --------------------------
# Load / Create Config
# --------------------------
$configCreatedOrFixed = $false

if (!(Test-Path $configPath)) {
    Write-Host "config.json not found. Creating default config..."
    Save-Config -Path $configPath -Config $defaultConfig
    $configCreatedOrFixed = $true
}

try {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
} catch {
    Write-Host "WARNING: config.json is invalid. Recreating default config..."
    Save-Config -Path $configPath -Config $defaultConfig
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $configCreatedOrFixed = $true
}

$config = Merge-ConfigWithDefaults -Config $config -Defaults $defaultConfig

# Save again so missing fields are written into config.json
Save-Config -Path $configPath -Config $config

if ($configCreatedOrFixed) {
    Write-Host "Default config.json is ready."
    Write-Host "Edit config.json if you want another loader or Minecraft version."
}

# --------------------------
# Read Config Values
# --------------------------
$PreferredGameVersion = [string]$config.preferredGameVersion
$PreferredLoaders = @($config.preferredLoaders)

$modpacksFile = Resolve-AppPath ([string]$config.modpacksFile)
$modsFile = Resolve-AppPath ([string]$config.modsFile)

$modpacksOutput = Resolve-AppPath ([string]$config.modpacksOutput)
$modsOutput = Resolve-AppPath ([string]$config.modsOutput)

$downloadModpacks = [bool]$config.downloadModpacks
$downloadStandaloneMods = [bool]$config.downloadStandaloneMods

$keepMrpackFile = [bool]$config.keepMrpackFile
$copyOverrides = [bool]$config.copyOverrides

$userAgent = [string]$config.userAgent

if ([string]::IsNullOrWhiteSpace($userAgent)) {
    $userAgent = "ModrinthDownloader/1.0"
}

$Headers = @{
    "User-Agent" = $userAgent
}

# --------------------------
# Auto-create list files
# --------------------------
Ensure-TextFile -Path $modpacksFile -Lines @(
    "# Put Modrinth modpack URLs or slugs here",
    "# Examples:",
    "# adrenaline",
    "# https://modrinth.com/modpack/adrenaline"
)

Ensure-TextFile -Path $modsFile -Lines @(
    "# Put Modrinth mod URLs or slugs here",
    "# Examples:",
    "# sodium",
    "# lithium",
    "# https://modrinth.com/mod/ferrite-core"
)

# --------------------------
# Create output folders
# --------------------------
New-Item -ItemType Directory -Path $modpacksOutput -ErrorAction SilentlyContinue -Force | Out-Null
New-Item -ItemType Directory -Path $modsOutput -ErrorAction SilentlyContinue -Force | Out-Null

# --------------------------
# General Helpers
# --------------------------
function Get-ModrinthSlug {
    param(
        [string]$Entry,
        [string]$Type
    )

    $clean = $Entry.Trim()

    if ([string]::IsNullOrWhiteSpace($clean)) {
        return $null
    }

    if ($clean.StartsWith("#")) {
        return $null
    }

    if ($clean -match "modrinth\.com/$Type/([^/?#]+)") {
        return $matches[1]
    }

    return $clean
}

function Select-BestVersion {
    param(
        [array]$Versions,
        [string[]]$Loaders,
        [string]$GameVersion
    )

    $candidates = $Versions | Where-Object {
        $_.version_type -eq "release"
    }

    if ($GameVersion -and $GameVersion.Trim() -ne "") {
        $candidates = $candidates | Where-Object {
            $_.game_versions -contains $GameVersion
        }
    }

    if ($Loaders -and $Loaders.Count -gt 0) {
        $candidates = $candidates | Where-Object {
            $versionLoaders = @($_.loaders)

            foreach ($loader in $Loaders) {
                if ($versionLoaders -contains $loader) {
                    return $true
                }
            }

            return $false
        }
    }

    return $candidates | Select-Object -First 1
}

function Select-ModpackFile {
    param(
        $Version
    )

    $file = $Version.files | Where-Object {
        $_.primary -eq $true -and $_.filename -like "*.mrpack"
    } | Select-Object -First 1

    if (-not $file) {
        $file = $Version.files | Where-Object {
            $_.filename -like "*.mrpack"
        } | Select-Object -First 1
    }

    return $file
}

function Select-ModFile {
    param(
        $Version
    )

    $file = $Version.files | Where-Object {
        $_.primary -eq $true -and $_.filename -like "*.jar"
    } | Select-Object -First 1

    if (-not $file) {
        $file = $Version.files | Where-Object {
            $_.filename -like "*.jar"
        } | Select-Object -First 1
    }

    return $file
}

function Download-FileSafe {
    param(
        [string]$Url,
        [string]$OutFile
    )

    $outDir = Split-Path $OutFile -Parent

    if ($outDir -and !(Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    Invoke-WebRequest -Uri $Url -OutFile $OutFile -Headers $Headers
}

function Copy-FolderContents {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (!(Test-Path $Source)) {
        return
    }

    if (!(Test-Path $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    Get-ChildItem -Path $Source -Force | ForEach-Object {
        $target = Join-Path $Destination $_.Name
        Copy-Item -Path $_.FullName -Destination $target -Recurse -Force
    }
}

function Show-SelectedVersion {
    param(
        $Version
    )

    Write-Host "Selected version: $($Version.version_number)"
    Write-Host "Loaders: $($Version.loaders -join ', ')"
    Write-Host "Minecraft: $($Version.game_versions -join ', ')"
}

function Show-ActiveConfig {
    Write-Host ""
    Write-Host "Active config:"
    Write-Host "Script folder: $ScriptDir"
    Write-Host "Loader filter: $($PreferredLoaders -join ', ')"

    if ($PreferredGameVersion -and $PreferredGameVersion.Trim() -ne "") {
        Write-Host "Minecraft version filter: $PreferredGameVersion"
    } else {
        Write-Host "Minecraft version filter: Any"
    }

    Write-Host "Modpacks file: $modpacksFile"
    Write-Host "Mods file: $modsFile"
    Write-Host "Modpacks output: $modpacksOutput"
    Write-Host "Mods output: $modsOutput"
    Write-Host ""
}

Show-ActiveConfig

# --------------------------
# Download Modpacks
# --------------------------
if ($downloadModpacks) {
    if (!(Test-Path $modpacksFile)) {
        Write-Host "WARNING: $modpacksFile not found. Skipping modpacks."
    } else {
        $modpackList = Get-Content $modpacksFile

        foreach ($entry in $modpackList) {
            $slug = Get-ModrinthSlug -Entry $entry -Type "modpack"

            if (-not $slug) {
                continue
            }

            Write-Host ""
            Write-Host "--- Downloading Modpack: $slug ---"

            $projectUrl = "https://api.modrinth.com/v2/project/$slug"

            try {
                $projectInfo = Invoke-RestMethod -Uri $projectUrl -Method Get -Headers $Headers
            } catch {
                Write-Host "ERROR: Could not fetch project info for '$slug'"
                continue
            }

            if ($projectInfo.project_type -ne "modpack") {
                Write-Host "WARNING: '$slug' is not a modpack. Skipping."
                continue
            }

            $versionListUrl = "https://api.modrinth.com/v2/project/$slug/version"

            try {
                $versions = Invoke-RestMethod -Uri $versionListUrl -Method Get -Headers $Headers
            } catch {
                Write-Host "ERROR: Could not fetch versions for '$slug'"
                continue
            }

            $latest = Select-BestVersion `
                -Versions $versions `
                -Loaders $PreferredLoaders `
                -GameVersion $PreferredGameVersion

            if (-not $latest) {
                Write-Host "ERROR: No matching release found for '$slug'."
                Write-Host "Loader filter: $($PreferredLoaders -join ', ')"

                if ($PreferredGameVersion -and $PreferredGameVersion.Trim() -ne "") {
                    Write-Host "Game version: $PreferredGameVersion"
                } else {
                    Write-Host "Game version: Any"
                }

                continue
            }

            $mrpack = Select-ModpackFile -Version $latest

            if (-not $mrpack) {
                Write-Host "ERROR: No .mrpack file found for '$slug' version '$($latest.version_number)'"
                continue
            }

            Show-SelectedVersion -Version $latest

            $outputFolder = Join-Path $modpacksOutput $slug
            $mrpackFile = Join-Path $modpacksOutput "$slug.mrpack"
            $zipFile = Join-Path $modpacksOutput "$slug.zip"

            New-Item -ItemType Directory -Path $outputFolder -ErrorAction SilentlyContinue -Force | Out-Null

            Write-Host "Downloading .mrpack: $($mrpack.filename)"

            try {
                Download-FileSafe -Url $mrpack.url -OutFile $mrpackFile
            } catch {
                Write-Host "ERROR: Failed to download .mrpack for '$slug'"
                continue
            }

            if (Test-Path $zipFile) {
                Remove-Item $zipFile -Force
            }

            Copy-Item $mrpackFile $zipFile -Force

            $tempExtractPath = Join-Path $outputFolder "temp_extract"

            if (Test-Path $tempExtractPath) {
                Remove-Item -Recurse -Force $tempExtractPath
            }

            New-Item -ItemType Directory -Path $tempExtractPath -Force | Out-Null

            try {
                Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force
            } catch {
                Write-Host "ERROR: Could not extract '$mrpackFile'"
                Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
                continue
            }

            Remove-Item $zipFile -Force -ErrorAction SilentlyContinue

            $indexJson = Join-Path $tempExtractPath "modrinth.index.json"

            if (!(Test-Path $indexJson)) {
                Write-Host "WARNING: modrinth.index.json not found. Skipping mod downloads for '$slug'"
                Remove-Item -Recurse -Force $tempExtractPath -ErrorAction SilentlyContinue
                continue
            }

            try {
                $index = Get-Content $indexJson -Raw | ConvertFrom-Json
            } catch {
                Write-Host "ERROR: Could not read modrinth.index.json for '$slug'"
                Remove-Item -Recurse -Force $tempExtractPath -ErrorAction SilentlyContinue
                continue
            }

            foreach ($file in $index.files) {
                if (-not $file.downloads -or $file.downloads.Count -eq 0) {
                    Write-Host "WARNING: No download URL for $($file.path). Skipping."
                    continue
                }

                $url = $file.downloads[0]
                $relativePath = $file.path
                $outPath = Join-Path $outputFolder $relativePath

                Write-Host "Downloading pack file: $relativePath"

                try {
                    Download-FileSafe -Url $url -OutFile $outPath
                } catch {
                    Write-Host "WARNING: Failed to download '$relativePath'"
                }
            }

            if ($copyOverrides) {
                $overridesPath = Join-Path $tempExtractPath "overrides"

                if (Test-Path $overridesPath) {
                    Copy-FolderContents -Source $overridesPath -Destination $outputFolder
                }

                $clientOverridesPath = Join-Path $tempExtractPath "client-overrides"

                if (Test-Path $clientOverridesPath) {
                    Copy-FolderContents -Source $clientOverridesPath -Destination $outputFolder
                }
            }

            Remove-Item -Recurse -Force $tempExtractPath -ErrorAction SilentlyContinue

            if (-not $keepMrpackFile) {
                Remove-Item $mrpackFile -Force -ErrorAction SilentlyContinue
            }

            Write-Host "Modpack '$slug' downloaded successfully."
        }
    }
} else {
    Write-Host "Skipping modpacks because downloadModpacks is false."
}

# --------------------------
# Download Individual Mods
# --------------------------
if ($downloadStandaloneMods) {
    if (!(Test-Path $modsFile)) {
        Write-Host "WARNING: $modsFile not found. Skipping standalone mods."
    } else {
        $modsList = Get-Content $modsFile

        foreach ($entry in $modsList) {
            $slug = Get-ModrinthSlug -Entry $entry -Type "mod"

            if (-not $slug) {
                continue
            }

            Write-Host ""
            Write-Host "--- Downloading Mod: $slug ---"

            $projectUrl = "https://api.modrinth.com/v2/project/$slug"

            try {
                $project = Invoke-RestMethod -Uri $projectUrl -Method Get -Headers $Headers
            } catch {
                Write-Host "ERROR: Could not fetch mod info for '$slug'"
                continue
            }

            if ($project.project_type -ne "mod") {
                Write-Host "WARNING: '$slug' is not a mod. Skipping."
                continue
            }

            $versionUrl = "https://api.modrinth.com/v2/project/$slug/version"

            try {
                $versions = Invoke-RestMethod -Uri $versionUrl -Method Get -Headers $Headers
            } catch {
                Write-Host "ERROR: Could not fetch versions for mod '$slug'"
                continue
            }

            $latest = Select-BestVersion `
                -Versions $versions `
                -Loaders $PreferredLoaders `
                -GameVersion $PreferredGameVersion

            if (-not $latest) {
                Write-Host "ERROR: No matching release found for mod '$slug'."
                Write-Host "Loader filter: $($PreferredLoaders -join ', ')"

                if ($PreferredGameVersion -and $PreferredGameVersion.Trim() -ne "") {
                    Write-Host "Game version: $PreferredGameVersion"
                } else {
                    Write-Host "Game version: Any"
                }

                continue
            }

            $modFile = Select-ModFile -Version $latest

            if (-not $modFile) {
                Write-Host "ERROR: No .jar file found for mod '$slug' version '$($latest.version_number)'"
                continue
            }

            Show-SelectedVersion -Version $latest

            $outPath = Join-Path $modsOutput $modFile.filename

            try {
                Download-FileSafe -Url $modFile.url -OutFile $outPath
                Write-Host "Mod '$slug' downloaded as '$($modFile.filename)'"
            } catch {
                Write-Host "ERROR: Failed to download mod '$slug'"
            }
        }
    }
} else {
    Write-Host "Skipping standalone mods because downloadStandaloneMods is false."
}

Write-Host ""
Write-Host "Done."
