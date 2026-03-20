# Define the path where Hyper-V stores your virtual hard disks
$VHDPath = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks"

# --- 1. Retrieve ALL VHD/VHDX/AVHDX files currently in use by REGISTERED VMs ---

# 1a. Retrieve paths of disks attached to main virtual machines
$VMDisks = Get-VM * | Get-VMHardDiskDrive -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path

# 1b. Correction: Retrieve paths of disks attached to checkpoints (snapshots).
# Use Get-VM * | Get-VMSnapshot to pass VM objects to the cmdlet.
$SnapshotDisks = Get-VM * | Get-VMSnapshot -ErrorAction SilentlyContinue | Get-VMHardDiskDrive -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path

# Combine both lists, filter out null values, convert to lowercase, and get unique paths
$ConfiguredVHDs_Lower = @($VMDisks + $SnapshotDisks) | Where-Object { $_ -ne $null } | ForEach-Object { $_.ToLower() } | Select-Object -Unique

# --- 2. Retrieve the list of ALL actual VHD/VHDX/AVHDX files on the disk ---
$AllVHD_Files = Get-ChildItem -Path $VHDPath -Filter *.vh*x -Recurse -ErrorAction Stop | Select-Object -ExpandProperty FullName

# --- 3. Identify unconfigured VHD/VHDX/AVHDX files ---
Write-Host "Checking Hyper-V disks in '$VHDPath'..."
Write-Host "A disk is considered 'In Use' if it is attached to a REGISTERED VM or a registered CHECKPOINT."
Write-Host "---------------------------------------------------------------------------------------"

$UnusedVHDs = @()
foreach ($File in $AllVHD_Files) {
    $FileLower = $File.ToLower()

    # If the file path is NOT found in the configured disks list
    if ($ConfiguredVHDs_Lower -notcontains $FileLower) {
        $UnusedVHDs += $File
        Write-Host "POTENTIALLY UNUSED: $File" -ForegroundColor Yellow
    }
}

# --- 4. Display the final result ---
Write-Host "---------------------------------------------------------------------------------------"
if ($UnusedVHDs.Count -eq 0) {
    Write-Host "No potentially unused VHD/VHDX/AVHDX files found in the specified path." -ForegroundColor Green
} else {
    Write-Host "$($UnusedVHDs.Count) VHD/VHDX/AVHDX files have been identified as potentially unused." -ForegroundColor Red
    Write-Host "Complete list of POTENTIALLY UNUSED files (please verify manually):"
    
    # Display results in a GridView window for easy sorting and review
    $UnusedVHDs | Out-GridView -Title "Potentially Unused VHD/VHDX/AVHDX Disks"
}