<#
.SYNOPSIS
    Hyper-V VLAN and ACL Management Script - Isolated Network Version (Ports & Protocols)
.DESCRIPTION
    Uses Hyper-V "Extended ACLs" to allow priority management (-Weight)
    and Port/Protocol filtering (TCP/UDP).
#>

function Show-Header {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "    ADVANCED HYPER-V NETWORK MANAGER      " -ForegroundColor Cyan
    Write-Host "    (VLANs & EXTENDED ACL ISOLATION)      " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
}

while ($true) {
    Show-Header
    
    # ---------------------------------------------------------
    # STEP 1: VM Selection
    # ---------------------------------------------------------
    $VMName = Read-Host "Enter the VM name (e.g., CLT_WIN10)"

    try {
        $vmCheck = Get-VM -Name $VMName -ErrorAction Stop
    } catch {
        Write-Host "Error: VM '$VMName' not found." -ForegroundColor Red
        Pause
        continue
    }

    # ---------------------------------------------------------
    # STEP 2: Network Adapters Listing and Selection
    # ---------------------------------------------------------
    Write-Host "`n--- Network Adapters found on $VMName ---" -ForegroundColor Yellow
    
    $adapters = @(Get-VMNetworkAdapter -VMName $VMName)
    
    if ($adapters.Count -gt 0) {
        $adapters | Select-Object Name, MacAddress, SwitchName | Format-Table -AutoSize
    } else {
        Write-Host "No network adapter found on this VM." -ForegroundColor Red
        Pause
        continue
    }

    $AdapterName = Read-Host "Name of the adapter to configure (Leave EMPTY for all [*])"
    
    if ([string]::IsNullOrWhiteSpace($AdapterName)) {
        $AdapterName = "*"
        Write-Host "   -> Selection: ALL adapters (*)" -ForegroundColor Gray
    } else {
        if ($AdapterName -ne "*" -and -not ($adapters.Name -contains $AdapterName)) {
            Write-Host "Warning: Adapter '$AdapterName' does not appear in the list above." -ForegroundColor DarkYellow
        } else {
            Write-Host "   -> Selection: $AdapterName" -ForegroundColor Gray
        }
    }

    # ---------------------------------------------------------
    # STEP 3: Actions Menu
    # ---------------------------------------------------------
    $stayInMenu = $true
    
    while ($stayInMenu) {
        Write-Host "`n------------------------------------------" -ForegroundColor Yellow
        Write-Host "TARGET: VM='$VMName' | Adapter='$AdapterName'" -ForegroundColor Yellow
        Write-Host "------------------------------------------" -ForegroundColor Yellow
        Write-Host "--- VLAN MANAGEMENT ---" -ForegroundColor Green
        Write-Host "1) View VLAN configuration"
        Write-Host "2) TRUNK Mode (Allowed: 1-4094, Native: 0)"
        Write-Host "3) UNTAGGED Mode (Reset to default)"
        Write-Host "4) ACCESS Mode (Specific VLAN - e.g., 40)"
        Write-Host "--- EXTENDED ACL MANAGEMENT (ISOLATION) ---" -ForegroundColor Green
        Write-Host "5) View active ACL rules"
        Write-Host "6) Add an ACL rule (Priority & Ports)"
        Write-Host "7) Remove an ACL rule (by line number)"
        Write-Host "--- NAVIGATION ---" -ForegroundColor Green
        Write-Host "8) <-- Change VM or Adapter"
        Write-Host "Q) Quit script"
        Write-Host ""
        
        $choice = Read-Host "Your choice"
        Write-Host ""

        switch ($choice) {
            "1" {
                Write-Host "Reading VLAN configuration..." -ForegroundColor Green
                try { Get-VMNetworkAdapterVlan -VMName $VMName -VMNetworkAdapterName $AdapterName | Format-Table -AutoSize } 
                catch { Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red }
            }
            "2" {
                Write-Host "Applying TRUNK Mode..." -ForegroundColor Green
                try {
                    Set-VMNetworkAdapterVlan -VMName $VMName -VMNetworkAdapterName $AdapterName -Trunk -AllowedVlanIdList "1-4094" -NativeVlanId 0 -ErrorAction Stop
                    Write-Host "Success: Trunk Mode enabled." -ForegroundColor Cyan
                } catch { Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red }
            }
            "3" {
                Write-Host "Applying UNTAGGED Mode..." -ForegroundColor Green
                try {
                    Set-VMNetworkAdapterVlan -VMName $VMName -VMNetworkAdapterName $AdapterName -Untagged -ErrorAction Stop
                    Write-Host "Success: Untagged Mode (default) enabled." -ForegroundColor Cyan
                } catch { Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red }
            }
            "4" {
                $VlanID = Read-Host "Enter VLAN ID (e.g., 40)"
                if ([string]::IsNullOrWhiteSpace($VlanID)) { Write-Host "Cancelled." -ForegroundColor Red } 
                else {
                    Write-Host "Applying ACCESS Mode for VLAN $VlanID..." -ForegroundColor Green
                    try {
                        Set-VMNetworkAdapterVlan -VMName $VMName -VMNetworkAdapterName $AdapterName -Access -VlanId $VlanID -ErrorAction Stop
                        Write-Host "Success: Access Mode for VLAN $VlanID enabled." -ForegroundColor Cyan
                    } catch { Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red }
                }
            }
            "5" {
                Write-Host "Reading Extended ACL rules..." -ForegroundColor Green
                try {
                    $acls = @(Get-VMNetworkAdapterExtendedAcl -VMName $VMName -VMNetworkAdapterName $AdapterName -ErrorAction Stop)
                    if ($acls.Count -gt 0) {
                        # Displaying Protocol and Ports
                        $acls | Select-Object Direction, Action, Weight, Protocol, LocalPort, RemotePort, RemoteIPAddress | Format-Table -AutoSize
                    } else { Write-Host "No extended ACL rule is configured." -ForegroundColor DarkYellow }
                } catch { Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red }
            }
            "6" {
                Write-Host "--- Adding an Extended ACL rule ---" -ForegroundColor Yellow
                $RemoteIP = Read-Host "Remote IP/Subnet (e.g., 192.168.1.50, 192.168.1.0/24, ANY)"
                if ([string]::IsNullOrWhiteSpace($RemoteIP)) { continue }

                $DirInput = Read-Host "Direction (1: Both, 2: Inbound, 3: Outbound) [Default: 1]"
                $Directions = switch($DirInput) { 
                    "2" { @("Inbound") }
                    "3" { @("Outbound") }
                    default { @("Inbound", "Outbound") }
                }

                $ActInput = Read-Host "Action (1: Allow, 2: Deny) [Default: 1]"
                $Action = switch($ActInput) { "2" {"Deny"}; default {"Allow"} }

                $WeightInput = Read-Host "Priority/Weight [Higher is more prioritized, leave empty for 0]"
                if ([string]::IsNullOrWhiteSpace($WeightInput)) { $WeightInput = 0 }

                # --- PORT AND PROTOCOL MANAGEMENT ---
                $ProtoInput = Read-Host "Protocol (1: ANY, 2: TCP, 3: UDP) [Default: 1]"
                $Protocol = switch($ProtoInput) { "2" {"TCP"}; "3" {"UDP"}; default {"ANY"} }

                $LocalPort = ""
                $RemotePort = ""
                if ($Protocol -ne "ANY") {
                    $LocalPort = Read-Host "Local VM Port (e.g., 80, 443, Leave empty for ALL)"
                    $RemotePort = Read-Host "Remote Target Port (e.g., 80, 443, Leave empty for ALL)"
                }

                try {
                    foreach ($dir in $Directions) {
                        Write-Host "Applying $dir rule..." -ForegroundColor DarkGray
                        
                        # Dynamic parameter construction (Splatting)
                        $aclParams = @{
                            VMName = $VMName
                            VMNetworkAdapterName = $AdapterName
                            RemoteIPAddress = $RemoteIP
                            Direction = $dir
                            Action = $Action
                            Weight = [int]$WeightInput
                            ErrorAction = 'Stop'
                        }

                        # Only add port parameters if they are provided
                        if ($Protocol -ne "ANY") {
                            $aclParams.Add('Protocol', $Protocol)
                            if (-not [string]::IsNullOrWhiteSpace($LocalPort)) { $aclParams.Add('LocalPort', $LocalPort) }
                            if (-not [string]::IsNullOrWhiteSpace($RemotePort)) { $aclParams.Add('RemotePort', $RemotePort) }
                        }

                        # Execute the command with the parameter table
                        Add-VMNetworkAdapterExtendedAcl @aclParams
                    }
                    Write-Host "Success: Rule(s) added." -ForegroundColor Cyan
                } catch { Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red }
            }
            "7" {
                Write-Host "--- Removing an Extended ACL rule ---" -ForegroundColor Yellow
                try {
                    $acls = @(Get-VMNetworkAdapterExtendedAcl -VMName $VMName -VMNetworkAdapterName $AdapterName -ErrorAction Stop)
                    
                    if ($acls.Count -eq 0) {
                        Write-Host "No extended ACL rule to remove." -ForegroundColor DarkYellow
                        continue
                    }

                    # Detailed display for removal
                    for ($i = 0; $i -lt $acls.Count; $i++) {
                        $acl = $acls[$i]
                        $portInfo = if ($acl.Protocol -ne "ANY") { "| Proto: $($acl.Protocol) | LPort: $($acl.LocalPort) | RPort: $($acl.RemotePort)" } else { "" }
                        Write-Host "[$($i + 1)] Action: $($acl.Action) | Dir: $($acl.Direction) | Weight: $($acl.Weight) | IP: $($acl.RemoteIPAddress) $portInfo"
                    }

                    Write-Host ""
                    $numToDelete = Read-Host "Number to remove (Leave empty to cancel, or type 'T' to remove ALL)"

                    if ([string]::IsNullOrWhiteSpace($numToDelete)) {
                        Write-Host "Cancelled." -ForegroundColor Gray
                    } elseif ($numToDelete -eq 'T' -or $numToDelete -eq 't') {
                        Write-Host "WARNING: Removing ALL rules..." -ForegroundColor DarkYellow
                        $acls | Remove-VMNetworkAdapterExtendedAcl -ErrorAction Stop
                        Write-Host "Success: All rules have been removed." -ForegroundColor Cyan
                    } else {
                        if ([int]::TryParse($numToDelete, [ref]$null)) {
                            $index = [int]$numToDelete
                            if ($index -ge 1 -and $index -le $acls.Count) {
                                $aclToDelete = $acls[$index - 1]
                                Write-Host "Removing rule [$index]..." -ForegroundColor Green
                                
                                $aclToDelete | Remove-VMNetworkAdapterExtendedAcl -ErrorAction Stop
                                Write-Host "Success: The rule has been removed." -ForegroundColor Cyan
                            } else {
                                Write-Host "Error: The number must be between 1 and $($acls.Count)." -ForegroundColor Red
                            }
                        } else {
                            Write-Host "Error: Invalid input." -ForegroundColor Red
                        }
                    }
                } catch {
                    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            "8" { $stayInMenu = $false }
            "Q" { Write-Host "Goodbye!" -ForegroundColor Cyan ; Exit }
            default { Write-Host "Invalid choice." -ForegroundColor Red }
        }
    }
}