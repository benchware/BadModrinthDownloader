# --------------------------
# Config
# --------------------------
$modpacksFile = ".\modpacks.txt"
$modsFile = ".\mods.txt"
$modpacksOutput = "Modpacks"
$modsOutput = "StandaloneMods"

New-Item -ItemType Directory -Path $modpacksOutput -ErrorAction SilentlyContinue | Out-Null
New-Item -ItemType Directory -Path $modsOutput -ErrorAction SilentlyContinue | Out-Null

# --------------------------
# Download Modpacks
# --------------------------
$modpackList = Get-Content $modpacksFile
foreach ($entry in $modpackList) {
    if ($entry -match "modrinth.com/modpack/([^/]+)") {
        $slug = $matches[1]
    } else {
        $slug = $entry.Trim()
    }

    $projectUrl = "https://api.modrinth.com/v2/project/$slug"
    try {
        $projectInfo = Invoke-RestMethod -Uri $projectUrl -Method Get
    } catch {
        Write-Host "ERROR: Could not fetch project info for '$slug'"
        continue
    }

    if ($projectInfo.project_type -ne "modpack") {
        Write-Host "WARNING: '$slug' is not a modpack. Skipping."
        continue
    }

    $outputFolder = Join-Path $modpacksOutput $slug
    $mrpackFile = "$outputFolder.mrpack"
    $modsFolder = Join-Path $outputFolder "mods"

    Write-Host "n--- Downloading Modpack: $slug ---"

    # Get latest release version info
    $versionListUrl = "https://api.modrinth.com/v2/project/$slug/version"
    $versions = Invoke-RestMethod -Uri $versionListUrl -Method Get
    $latest = $versions | Where-Object { $_.version_type -eq "release" } | Select-Object -First 1

    if (-not $latest) {
        Write-Host "ERROR: No release version found for $slug"
        continue
    }

    $mrpackUrl = $latest.files[0].url

    # Create output folder if not exists
    New-Item -ItemType Directory -Path $outputFolder -ErrorAction SilentlyContinue | Out-Null

    # Download .mrpack
    Invoke-WebRequest -Uri $mrpackUrl -OutFile $mrpackFile

    # Rename .mrpack to .zip so Expand-Archive can extract it
    $zipFile = "$outputFolder.zip"
    $zipFileName = [IO.Path]::GetFileName($zipFile)
    Rename-Item -Path $mrpackFile -NewName $zipFileName -Force

    # Create temp extraction folder
    $tempExtractPath = Join-Path $outputFolder "temp_extract"
    if (Test-Path $tempExtractPath) { Remove-Item -Recurse -Force $tempExtractPath }
    New-Item -ItemType Directory -Path $tempExtractPath | Out-Null

    # Extract the .zip (renamed mrpack)
    Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force

    # Remove the renamed zip after extraction
    Remove-Item $zipFile

    # Read manifest (modrinth.index.json) from temp extract folder
    $indexJson = Join-Path $tempExtractPath "modrinth.index.json"
    if (!(Test-Path $indexJson)) {
        Write-Host "WARNING: modrinth.index.json not found. Skipping mod downloads for $slug"
        continue
    }

    $index = Get-Content $indexJson | ConvertFrom-Json

    # Ensure mods folder exists
    New-Item -ItemType Directory -Path $modsFolder -ErrorAction SilentlyContinue | Out-Null

    # Download each mod listed in manifest
    foreach ($file in $index.files) {
        $url = $file.downloads[0]
        $filename = $file.path

        # Remove leading 'mods/' from filename if present to avoid nested mods/mods
        if ($filename.StartsWith("mods/")) {
            $filename = $filename.Substring(5)
        }

        $outPath = Join-Path $modsFolder $filename

        # Create directory structure if needed
        $outDir = Split-Path $outPath -Parent
        if (!(Test-Path $outDir)) {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }

        Write-Host "Downloading mod file: $filename ..."
        Invoke-WebRequest -Uri $url -OutFile $outPath
    }

    # Copy overrides folder if exists
    $overridesPath = Join-Path $tempExtractPath "overrides"
    if (Test-Path $overridesPath) {
        robocopy $overridesPath $outputFolder /E > $null
    }

    # Remove temp extraction folder after done
    Remove-Item -Recurse -Force $tempExtractPath

    Write-Host "Modpack '$slug' downloaded successfully."
}

# --------------------------
# Download Individual Mods
# --------------------------
$modsList = Get-Content $modsFile
foreach ($entry in $modsList) {
    if ($entry -match "modrinth.com/mod/([^/]+)") {
        $slug = $matches[1]
    } else {
        $slug = $entry.Trim()
    }

    Write-Host "n--- Downloading Mod: $slug ---"

    $projectUrl = "https://api.modrinth.com/v2/project/$slug"
    try {
        $project = Invoke-RestMethod -Uri $projectUrl -Method Get
    } catch {
        Write-Host "ERROR: Could not fetch mod info for '$slug'"
        continue
    }

    if ($project.project_type -ne "mod") {
        Write-Host "WARNING: '$slug' is not a mod. Skipping."
        continue
    }

    $versionUrl = "https://api.modrinth.com/v2/project/$slug/version"
    $versions = Invoke-RestMethod -Uri $versionUrl -Method Get
    $latest = $versions | Where-Object { $_.version_type -eq "release" } | Select-Object -First 1

    if (-not $latest) {
        Write-Host "ERROR: No release version found for mod '$slug'"
        continue
    }

    $modFile = $latest.files | Where-Object { $_.primary -eq $true }
    if (-not $modFile) {
        $modFile = $latest.files[0]
    }

    $url = $modFile.url
    $filename = $modFile.filename
    $outPath = Join-Path $modsOutput $filename

    Invoke-WebRequest -Uri $url -OutFile $outPath
    Write-Host "Mod '$slug' downloaded as '$filename'"
}