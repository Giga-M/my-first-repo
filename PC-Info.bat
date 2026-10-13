@echo off
:: ============================================================================
::  PC-Info.bat  -  Interactive PC information tool for Windows 10 / 11
::
::  Shows hardware (CPU, RAM, GPU, motherboard, disks, battery ...) and
::  system details, and creates a full report (HTML + TXT) on the Desktop.
::
::  The menu is plain CMD. The data is collected by the PowerShell code that
::  is stored at the end of this same file, so this one file is all you need.
::  The tool only READS information - it never changes any settings.
:: ============================================================================
setlocal EnableExtensions DisableDelayedExpansion
title PC Info Tool
set "SELF=%~f0"
set "FW_TYPE=%firmware_type%"

where powershell >nul 2>&1
if errorlevel 1 (
    echo.
    echo  ERROR: Windows PowerShell was not found. This tool needs Windows 10 or 11.
    echo.
    pause
    exit /b 1
)

net session >nul 2>&1
if errorlevel 1 (set "ADMIN=No") else (set "ADMIN=Yes")

:menu
cls
echo.
echo  ======================================================================
echo                            PC INFO TOOL  v1.0
echo  ======================================================================
setlocal EnableDelayedExpansion
echo    Computer: !COMPUTERNAME!     User: !USERNAME!     Administrator: !ADMIN!
endlocal
echo  ----------------------------------------------------------------------
echo    HARDWARE                              SYSTEM
echo    [1] Processor (CPU)                   [7] System overview
echo    [2] Memory (RAM)                      [8] Network
echo    [3] Graphics (GPU) and monitors       [9] Security status
echo    [4] Motherboard and BIOS              [A] Performance, top processes
echo    [5] Storage (disks and drives)        [B] Installed programs, startup
echo    [6] Battery                           [C] Devices and drivers
echo  ----------------------------------------------------------------------
echo    [R] Create full report (HTML + TXT, you choose the file name)
if "%ADMIN%"=="No" echo    [U] Restart as administrator ^(shows TPM, BitLocker, disk health^)
echo    [0] Exit
echo  ======================================================================
echo.
choice /c 123456789ABCRU0 /n /m "  Choose an option: "
set "OPT=%errorlevel%"
if %OPT% LSS 1 goto :menu
if %OPT% GTR 15 goto :menu
for /f "tokens=%OPT%" %%S in ("CPU RAM GPU BOARD STORAGE BATTERY SYSTEM NETWORK SECURITY PERFORMANCE SOFTWARE DEVICES REPORT ADMIN EXIT") do set "ACTION=%%S"

if "%ACTION%"=="EXIT" goto :end
if "%ACTION%"=="ADMIN" goto :elevate
cls
call :ps %ACTION%
echo.
pause
goto :menu

:elevate
if "%ADMIN%"=="Yes" goto :menu
echo   Requesting administrator rights...
powershell -NoProfile -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
if errorlevel 1 (
    echo   Administrator rights were not granted.
    pause
    goto :menu
)
goto :end

:end
endlocal
exit /b 0

:ps
:: Loads the PowerShell code below and runs one section of it.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:SELF); iex $t.Substring($t.LastIndexOf('#PS-CODE#')); Invoke-Section '%~1'"
exit /b

#PS-CODE#
# =============================================================================
#  PowerShell part. CMD never runs these lines (it always exits before them).
#  Every Get-*Info function returns "blocks": a title plus rows of data,
#  shown as a list or a table. The same blocks feed the screen and the report.
# =============================================================================
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$ToolVersion = '1.0'
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$MemoryTypes = @{
    18 = 'DDR'; 19 = 'DDR2'; 20 = 'DDR2 FB-DIMM'; 24 = 'DDR3'; 26 = 'DDR4'
    27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5'
}
$MonitorMakers = @{
    ACR = 'Acer'; AOC = 'AOC'; AUO = 'AU Optronics'; AUS = 'ASUS'; BNQ = 'BenQ'; BOE = 'BOE'
    CMN = 'Innolux'; DEL = 'Dell'; GBT = 'Gigabyte'; GSM = 'LG'; HKC = 'HKC'; HPN = 'HP'; HWP = 'HP'
    IVM = 'Iiyama'; LEN = 'Lenovo'; LGD = 'LG Display'; MSI = 'MSI'; PHL = 'Philips'; SAM = 'Samsung'
    SDC = 'Samsung Display'; SHP = 'Sharp'; SNY = 'Sony'; VSC = 'ViewSonic'; XMI = 'Xiaomi'
}
$DeviceErrors = @{
    1 = 'Not configured correctly'; 3 = 'Driver may be corrupted'; 10 = 'Device cannot start'
    12 = 'Not enough free resources'; 14 = 'Restart required'; 18 = 'Drivers need to be reinstalled'
    19 = 'Registry problem'; 21 = 'Device is being removed'; 22 = 'Device is disabled'
    24 = 'Not present or not working'; 28 = 'Drivers are not installed'; 31 = 'Not working properly'
    37 = 'Driver failed to start'; 39 = 'Driver is corrupted or missing'; 43 = 'Device reported a problem'
    52 = 'Driver signature problem'
}

# ----------------------------------------------------------------- helpers ---
function Get-Cim([string]$Class, [string]$Namespace = 'root\cimv2', [string]$Filter) {
    $params = @{ ClassName = $Class; Namespace = $Namespace; ErrorAction = 'SilentlyContinue' }
    if ($Filter) { $params.Filter = $Filter }
    try { Get-CimInstance @params } catch { }
}

function Invoke-Safely([scriptblock]$Script) {
    try { & $Script } catch { }
}

# Returns the first non-empty argument as trimmed text, or 'N/A'.
function Pick {
    foreach ($a in $args) {
        if ($null -ne $a -and "$a".Trim() -ne '') { return "$a".Trim() }
    }
    'N/A'
}

function Format-Size($Bytes) {
    if ($null -eq $Bytes -or "$Bytes" -eq '') { return 'N/A' }
    $b = [double]$Bytes
    if ($b -ge 1TB) { return '{0:N2} TB' -f ($b / 1TB) }
    if ($b -ge 1GB) { return '{0:N1} GB' -f ($b / 1GB) }
    if ($b -ge 1MB) { return '{0:N0} MB' -f ($b / 1MB) }
    '{0:N0} KB' -f ($b / 1KB)
}

function Format-Date($Date, [switch]$DateOnly) {
    if (-not $Date) { return 'N/A' }
    $format = if ($DateOnly) { 'yyyy-MM-dd' } else { 'yyyy-MM-dd HH:mm' }
    ([datetime]$Date).ToString($format)
}

function Format-Duration([timespan]$Span) {
    '{0} d {1} h {2} min' -f $Span.Days, $Span.Hours, $Span.Minutes
}

function Format-Cache($KB) {
    if (-not $KB) { return 'N/A' }
    if ($KB -ge 1024) { return '{0:N1} MB' -f ($KB / 1024) }
    "$KB KB"
}

function Format-InstallDate($Value) {
    if ("$Value" -match '^(\d{4})(\d{2})(\d{2})$') { return '{0}-{1}-{2}' -f $Matches[1], $Matches[2], $Matches[3] }
    'N/A'
}

function Convert-WmiString($Codes) {
    Pick (-join ($Codes | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }))
}

function New-Block([string]$Title, $Data, [switch]$Table) {
    [pscustomobject]@{ Title = $Title; Data = @($Data | Where-Object { $null -ne $_ }); Table = [bool]$Table }
}

# One row of the security checklist. Status is OK, WARN or INFO.
function New-Check([string]$Check, $Value, [string]$Status) {
    [pscustomobject]@{ Check = $Check; Value = (Pick $Value); Status = $Status }
}

function Get-FirmwareInfo {
    $state = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue
    $type = $env:FW_TYPE
    if (-not $type) { $type = if ($null -ne $state.UEFISecureBootEnabled) { 'UEFI' } else { 'Unknown' } }
    $secure = switch ($state.UEFISecureBootEnabled) { 1 { 'On' } 0 { 'Off' } default { 'Not supported' } }
    [pscustomobject]@{ Type = $type; SecureBoot = $secure }
}

function Get-MemoryTypeName($Module) {
    $code = [int]$Module.SMBIOSMemoryType
    if ($MemoryTypes.ContainsKey($code)) { return $MemoryTypes[$code] }
    'Unknown'
}

# Win32_VideoController.AdapterRAM stops at 4 GB, so read the real size from the driver's registry key.
function Get-GpuMemory([string]$Name) {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    foreach ($key in Get-ChildItem -Path $base -ErrorAction SilentlyContinue) {
        $p = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
        if ($p.DriverDesc -ne $Name) { continue }
        $qw = $p.'HardwareInformation.qwMemorySize'
        if ($qw) { return [double]$qw }
        $size = $p.'HardwareInformation.MemorySize'
        if ($size -is [byte[]]) { return [double][BitConverter]::ToUInt32($size, 0) }
        if ($size) { return [double]$size }
    }
    $null
}

function Get-TpmState {
    $tpm = Get-Cim Win32_Tpm 'root\cimv2\Security\MicrosoftTpm'
    if ($tpm) {
        $version = ("$($tpm.SpecVersion)" -split ',')[0].Trim()
        $enabled = if ($tpm.IsEnabled_InitialValue) { 'enabled' } else { 'disabled' }
        return "Present, version $version, $enabled"
    }
    $device = Get-Cim Win32_PnPEntity -Filter "PNPClass='SecurityDevices'" |
        Where-Object { $_.Name -match 'Trusted Platform Module' } | Select-Object -First 1
    if ($device) {
        if ($device.Name -match '([\d.]+)\s*$') { return "Present, version $($Matches[1])" }
        return 'Present'
    }
    if ($IsAdmin) { return 'Not found' }
    'Not detected (run as administrator to check)'
}

function Get-BitLockerState {
    $drive = $env:SystemDrive
    $volume = Get-Cim Win32_EncryptableVolume 'root\cimv2\Security\MicrosoftVolumeEncryption' -Filter "DriveLetter='$drive'"
    if ($volume) {
        switch ([int]$volume.ProtectionStatus) { 1 { return 'On' } 0 { return 'Off' } default { return 'Unknown' } }
    }
    # Works without administrator rights.
    $value = Invoke-Safely { (New-Object -ComObject Shell.Application).NameSpace("$drive\").Self.ExtendedProperty('System.Volume.BitLockerProtection') }
    switch ([int]$value) {
        1 { 'On' } 2 { 'Off' } 3 { 'Encrypting' } 4 { 'Decrypting' } 5 { 'Suspended' } 6 { 'On (locked)' }
        default { 'Not available on this edition' }
    }
}

# Win32_QuickFixEngineering dates are always written as M/d/yyyy.
function Get-LastUpdate {
    $last = $null
    foreach ($fix in Get-Cim Win32_QuickFixEngineering) {
        $date = $null
        try { $date = [datetime]::ParseExact("$($fix.InstalledOn)", 'M/d/yyyy', [Globalization.CultureInfo]::InvariantCulture) } catch { }
        if ($date -and (-not $last -or $date -gt $last.Date)) { $last = [pscustomobject]@{ Id = $fix.HotFixID; Date = $date } }
    }
    $last
}

# ---------------------------------------------------------------- sections ---
function Get-SystemInfo {
    $os = Get-Cim Win32_OperatingSystem
    $cs = Get-Cim Win32_ComputerSystem
    $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $fw = Get-FirmwareInfo
    $license = Get-Cim SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" |
        Select-Object -First 1
    $activation = switch ($license.LicenseStatus) {
        1 { 'Activated' } 0 { 'Not activated' } 2 { 'Grace period' } 3 { 'Grace period' } 4 { 'Non-genuine grace period' }
        5 { 'Notification mode (not activated)' } 6 { 'Extended grace period' } default { 'Unknown' }
    }
    $deviceType = switch ([int]$cs.PCSystemType) {
        1 { 'Desktop' } 2 { 'Laptop / mobile' } 3 { 'Workstation' } 4 { 'Server' } 5 { 'Server' } 8 { 'Tablet' } default { 'Unknown' }
    }
    $build = if ($cv.CurrentBuild) { '{0}.{1}' -f $cv.CurrentBuild, $cv.UBR } else { $os.BuildNumber }
    $uptime = if ($os.LastBootUpTime) { Format-Duration ((Get-Date) - $os.LastBootUpTime) } else { 'N/A' }
    $membership = if ($cs.PartOfDomain) { "Domain: $($cs.Domain)" } else { "Workgroup: $($cs.Workgroup)" }

    New-Block '' ([pscustomobject]@{
        'Computer name'      = $env:COMPUTERNAME
        'Current user'       = '{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME
        'Operating system'   = Pick $os.Caption
        'Version'            = Pick $cv.DisplayVersion $cv.ReleaseId
        'Build'              = Pick $build
        'Architecture'       = Pick $os.OSArchitecture
        'Windows activation' = $activation
        'Installed on'       = Format-Date $os.InstallDate
        'Last boot'          = Format-Date $os.LastBootUpTime
        'Uptime'             = $uptime
        'Manufacturer'       = Pick $cs.Manufacturer
        'Model'              = Pick $cs.Model
        'Device type'        = $deviceType
        'Network membership' = $membership
        'Firmware'           = $fw.Type
        'Secure Boot'        = $fw.SecureBoot
        'Time zone'          = [TimeZoneInfo]::Local.DisplayName
        'Windows folder'     = $env:SystemRoot
    })
}

function Get-CpuInfo {
    $cs = Get-Cim Win32_ComputerSystem
    foreach ($c in Get-Cim Win32_Processor) {
        $virtualization = if ($cs.HypervisorPresent) { 'Enabled (a hypervisor is running)' }
            elseif ($null -eq $c.VirtualizationFirmwareEnabled) { 'Unknown' }
            elseif ($c.VirtualizationFirmwareEnabled) { 'Enabled' }
            else { 'Disabled in BIOS / UEFI' }
        New-Block '' ([pscustomobject]@{
            'Processor'                    = Pick $c.Name
            'Manufacturer'                 = Pick $c.Manufacturer
            'Cores'                        = Pick $c.NumberOfCores
            'Logical processors (threads)' = Pick $c.NumberOfLogicalProcessors
            'Base clock'                   = $(if ($c.MaxClockSpeed) { '{0:N2} GHz' -f ($c.MaxClockSpeed / 1000) } else { 'N/A' })
            'Socket'                       = Pick $c.SocketDesignation
            'L2 cache'                     = Format-Cache $c.L2CacheSize
            'L3 cache'                     = Format-Cache $c.L3CacheSize
            'Architecture'                 = $(switch ([int]$c.Architecture) { 0 { 'x86' } 5 { 'ARM' } 9 { 'x64' } 12 { 'ARM64' } default { 'Other' } })
            'Current load'                 = $(if ($null -ne $c.LoadPercentage) { "$($c.LoadPercentage) %" } else { 'N/A' })
            'Virtualization'               = $virtualization
            'Processor ID'                 = Pick $c.ProcessorId
        })
    }
}

function Get-RamInfo {
    $os = Get-Cim Win32_OperatingSystem
    $modules = @(Get-Cim Win32_PhysicalMemory)
    $arrays = @(Get-Cim Win32_PhysicalMemoryArray | Where-Object { $_.Use -eq 3 })
    $installed = ($modules | Measure-Object -Property Capacity -Sum).Sum
    $total = [double]$os.TotalVisibleMemorySize * 1KB
    $free = [double]$os.FreePhysicalMemory * 1KB
    $slots = ($arrays | Measure-Object -Property MemoryDevices -Sum).Sum
    $maxKB = ($arrays | Measure-Object -Property MaxCapacityEx -Sum).Sum
    if (-not $maxKB) { $maxKB = ($arrays | Measure-Object -Property MaxCapacity -Sum).Sum }
    $usage = if ($total) { '{0} of {1} ({2:N0} %)' -f (Format-Size ($total - $free)), (Format-Size $total), (100 * ($total - $free) / $total) } else { 'N/A' }

    New-Block 'Summary' ([pscustomobject]@{
        'Installed memory'   = Format-Size $installed
        'Usable by Windows'  = Format-Size $total
        'In use'             = $usage
        'Available'          = Format-Size $free
        'Memory type'        = Pick (($modules | ForEach-Object { Get-MemoryTypeName $_ } | Sort-Object -Unique) -join ', ')
        'Slots used'         = $(if ($slots) { '{0} of {1}' -f $modules.Count, $slots } else { $modules.Count })
        'Maximum supported'  = $(if ($maxKB) { Format-Size ($maxKB * 1KB) } else { 'N/A' })
    })

    New-Block 'Installed modules' @(foreach ($m in $modules) {
        [pscustomobject]@{
            'Slot'         = Pick $m.DeviceLocator
            'Size'         = Format-Size $m.Capacity
            'Type'         = Get-MemoryTypeName $m
            'Speed (MT/s)' = $(if ($m.ConfiguredClockSpeed -and $m.Speed -and $m.ConfiguredClockSpeed -ne $m.Speed) { '{0} (max {1})' -f $m.ConfiguredClockSpeed, $m.Speed } else { Pick $m.ConfiguredClockSpeed $m.Speed })
            'Manufacturer' = Pick $m.Manufacturer
            'Part number'  = Pick $m.PartNumber
            'Form factor'  = $(switch ([int]$m.FormFactor) { 8 { 'DIMM' } 12 { 'SO-DIMM' } default { 'Other' } })
        }
    }) -Table
}

function Get-GpuInfo {
    $adapters = foreach ($g in Get-Cim Win32_VideoController) {
        $memory = Get-GpuMemory $g.Name
        if (-not $memory -and $g.AdapterRAM -gt 0) { $memory = [double]$g.AdapterRAM }
        $mode = if ($g.CurrentHorizontalResolution) {
            '{0} x {1}, {2} Hz' -f $g.CurrentHorizontalResolution, $g.CurrentVerticalResolution, $g.CurrentRefreshRate
        } else { 'Not active' }
        [pscustomobject]@{
            'Graphics card'       = Pick $g.Name
            'Manufacturer'        = Pick $g.AdapterCompatibility
            'Video memory (VRAM)' = Format-Size $memory
            'Driver version'      = Pick $g.DriverVersion
            'Driver date'         = Format-Date $g.DriverDate -DateOnly
            'Current mode'        = $mode
            'Status'              = Pick $g.Status
        }
    }
    New-Block 'Graphics adapters' $adapters

    $displayParams = @{}
    foreach ($p in Get-Cim WmiMonitorBasicDisplayParams 'root\wmi') { $displayParams[$p.InstanceName] = $p }
    $monitors = foreach ($m in Get-Cim WmiMonitorID 'root\wmi') {
        $maker = Convert-WmiString $m.ManufacturerName
        $p = $displayParams[$m.InstanceName]
        $size = if ($p -and $p.MaxHorizontalImageSize) {
            '{0:N1} inch' -f ([math]::Sqrt([math]::Pow($p.MaxHorizontalImageSize, 2) + [math]::Pow($p.MaxVerticalImageSize, 2)) / 2.54)
        } else { 'N/A' }
        [pscustomobject]@{
            'Monitor'      = Convert-WmiString $m.UserFriendlyName
            'Manufacturer' = $(if ($MonitorMakers.ContainsKey($maker)) { $MonitorMakers[$maker] } else { $maker })
            'Size'         = $size
            'Year made'    = Pick $m.YearOfManufacture
            'Serial'       = Convert-WmiString $m.SerialNumberID
        }
    }
    New-Block 'Monitors' $monitors -Table
}

function Get-BoardInfo {
    $board = Get-Cim Win32_BaseBoard | Select-Object -First 1
    $bios = Get-Cim Win32_BIOS | Select-Object -First 1
    $fw = Get-FirmwareInfo
    New-Block 'Motherboard' ([pscustomobject]@{
        'Manufacturer'  = Pick $board.Manufacturer
        'Model'         = Pick $board.Product
        'Version'       = Pick $board.Version
        'Serial number' = Pick $board.SerialNumber
    })
    New-Block 'BIOS / UEFI' ([pscustomobject]@{
        'Vendor'               = Pick $bios.Manufacturer
        'Version'              = Pick $bios.SMBIOSBIOSVersion
        'Release date'         = Format-Date $bios.ReleaseDate -DateOnly
        'SMBIOS version'       = $(if ($bios.SMBIOSMajorVersion) { '{0}.{1}' -f $bios.SMBIOSMajorVersion, $bios.SMBIOSMinorVersion } else { 'N/A' })
        'Firmware type'        = $fw.Type
        'Secure Boot'          = $fw.SecureBoot
        'System serial number' = Pick $bios.SerialNumber
    })
}

function Get-StorageInfo {
    $physical = @(Invoke-Safely { Get-PhysicalDisk -ErrorAction SilentlyContinue })
    $disks = if ($physical.Count) {
        foreach ($d in $physical | Sort-Object { [int]$_.DeviceId }) {
            $counter = if ($IsAdmin) { Invoke-Safely { $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue } }
            [pscustomobject]@{
                'Disk'        = $d.DeviceId
                'Model'       = Pick $d.FriendlyName
                'Type'        = Pick "$($d.MediaType)"
                'Connection'  = Pick "$($d.BusType)"
                'Size'        = Format-Size $d.Size
                'Temperature' = $(if ($counter.Temperature) { "$($counter.Temperature) C" } elseif ($IsAdmin) { 'N/A' } else { 'Admin only' })
                'Wear'        = $(if ($null -ne $counter.Wear) { "$($counter.Wear) %" } elseif ($IsAdmin) { 'N/A' } else { 'Admin only' })
                'Health'      = Pick "$($d.HealthStatus)"
            }
        }
    } else {
        foreach ($d in Get-Cim Win32_DiskDrive) {
            [pscustomobject]@{
                'Disk'       = $d.Index
                'Model'      = Pick $d.Model
                'Connection' = Pick $d.InterfaceType
                'Size'       = Format-Size $d.Size
                'Health'     = Pick $d.Status
            }
        }
    }
    New-Block 'Physical disks' $disks -Table

    $volumes = foreach ($v in Get-Cim Win32_LogicalDisk -Filter 'DriveType=2 OR DriveType=3') {
        if (-not $v.Size) { continue }
        $freePercent = 100 * $v.FreeSpace / $v.Size
        [pscustomobject]@{
            'Drive'       = $v.DeviceID
            'Label'       = Pick $v.VolumeName '-'
            'File system' = Pick $v.FileSystem
            'Size'        = Format-Size $v.Size
            'Free'        = Format-Size $v.FreeSpace
            'Free %'      = $(if ($freePercent -lt 10) { '{0:N0} % - low space' -f $freePercent } else { '{0:N0} %' -f $freePercent })
            'Status'      = $(if ($freePercent -lt 10) { 'WARN' } else { 'OK' })
        }
    }
    New-Block 'Drives (volumes)' $volumes -Table
}

function Get-BatteryInfo {
    $batteries = @(Get-Cim Win32_Battery)
    if (-not $batteries.Count) {
        return New-Block '' ([pscustomobject]@{ 'Battery' = 'No battery found (desktop PC, or the battery is not reported)' })
    }
    $design = (Get-Cim BatteryStaticData 'root\wmi' | Measure-Object -Property DesignedCapacity -Sum).Sum
    $full = (Get-Cim BatteryFullChargedCapacity 'root\wmi' | Measure-Object -Property FullChargedCapacity -Sum).Sum
    $capacityNote = if ($IsAdmin) { 'N/A' } else { 'Run as administrator to see' }
    foreach ($b in $batteries) {
        $minutes = [int64]$b.EstimatedRunTime
        $runtime = if ($minutes -gt 0 -and $minutes -lt 71582788) { '{0} h {1} min' -f [math]::Floor($minutes / 60), ($minutes % 60) } else { 'N/A (plugged in)' }
        New-Block '' ([pscustomobject]@{
            'Battery'              = Pick $b.Name
            'Charge level'         = $(if ($null -ne $b.EstimatedChargeRemaining) { "$($b.EstimatedChargeRemaining) %" } else { 'N/A' })
            'Status'               = $(switch ([int]$b.BatteryStatus) {
                1 { 'Discharging' } 2 { 'Plugged in' } 3 { 'Fully charged' } 4 { 'Low' } 5 { 'Critical' }
                { $_ -ge 6 -and $_ -le 9 } { 'Charging' } 11 { 'Partially charged' } default { 'Unknown' } })
            'Estimated runtime'    = $runtime
            'Design capacity'      = $(if ($design) { '{0:N0} mWh' -f $design } else { $capacityNote })
            'Full charge capacity' = $(if ($full) { '{0:N0} mWh' -f $full } else { $capacityNote })
            'Battery health'       = $(if ($design -and $full) { '{0:N0} % of the original capacity' -f (100 * $full / $design) } else { $capacityNote })
        })
    }
    New-Block 'Tip' ([pscustomobject]@{ 'Detailed battery history' = 'Run in CMD:  powercfg /batteryreport' })
}

function Get-NetworkInfo {
    $configs = Invoke-Safely { Get-NetIPConfiguration -ErrorAction SilentlyContinue } | Where-Object { "$($_.NetAdapter.Status)" -eq 'Up' }
    $adapters = foreach ($c in $configs) {
        [pscustomobject]@{
            'Adapter'         = Pick $c.InterfaceAlias
            'Description'     = Pick $c.InterfaceDescription
            'MAC address'     = Pick $c.NetAdapter.MacAddress
            'Link speed'      = Pick $c.NetAdapter.LinkSpeed
            'IPv4 address'    = Pick ($c.IPv4Address.IPAddress -join ', ')
            'Default gateway' = Pick ($c.IPv4DefaultGateway.NextHop -join ', ')
            'DNS servers'     = Pick (($c.DNSServer | Where-Object { $_.AddressFamily -eq 2 }).ServerAddresses -join ', ')
        }
    }
    New-Block 'Connected network adapters' $adapters

    $ssid = netsh wlan show interfaces 2>$null | Select-String -Pattern '^\s*SSID\s*:\s*(.+)$' | Select-Object -First 1
    $online = Test-Connection -ComputerName 1.1.1.1 -Count 1 -Quiet
    New-Block 'Connection' ([pscustomobject]@{
        'Wi-Fi network (SSID)' = $(if ($ssid) { $ssid.Matches[0].Groups[1].Value.Trim() } else { 'Not connected / not available' })
        'Internet'             = $(if ($online) { 'Connected' } else { 'No reply (offline or ping blocked)' })
    })
}

function Get-SecurityInfo {
    $fw = Get-FirmwareInfo
    $checks = New-Object System.Collections.Generic.List[object]

    $av = @(Get-Cim AntiVirusProduct 'root\SecurityCenter2')
    $avOn = @($av | Where-Object { ($_.productState -band 0x1000) -ne 0 })
    $avText = ($av | ForEach-Object { '{0} ({1})' -f $_.displayName, $(if (($_.productState -band 0x1000) -ne 0) { 'on' } else { 'off' }) }) -join ', '
    $checks.Add((New-Check 'Antivirus' $avText $(if ($avOn.Count) { 'OK' } elseif ($av.Count) { 'WARN' } else { 'INFO' })))

    $mp = Invoke-Safely { Get-MpComputerStatus -ErrorAction SilentlyContinue }
    if ($mp) {
        $otherAv = @($avOn | Where-Object { $_.displayName -notmatch 'Defender' }).Count
        $realtime = [bool]$mp.RealTimeProtectionEnabled
        $checks.Add((New-Check 'Defender real-time protection' $(if ($realtime) { 'On' } else { 'Off' }) $(if ($realtime) { 'OK' } elseif ($otherAv) { 'INFO' } else { 'WARN' })))
        if ($realtime -and $mp.AntivirusSignatureLastUpdated) {
            $age = ((Get-Date) - $mp.AntivirusSignatureLastUpdated).Days
            $checks.Add((New-Check 'Defender virus definitions' ('{0} ({1} days old)' -f (Format-Date $mp.AntivirusSignatureLastUpdated -DateOnly), $age) $(if ($age -le 7) { 'OK' } else { 'WARN' })))
        }
    }

    foreach ($p in Invoke-Safely { Get-NetFirewallProfile -ErrorAction SilentlyContinue }) {
        $on = "$($p.Enabled)" -eq 'True'
        $checks.Add((New-Check "Firewall ($($p.Name) network)" $(if ($on) { 'On' } else { 'Off' }) $(if ($on) { 'OK' } else { 'WARN' })))
    }

    $policy = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $uac = $policy.EnableLUA -ne 0
    $checks.Add((New-Check 'User Account Control (UAC)' $(if ($uac) { 'On' } else { 'Off' }) $(if ($uac) { 'OK' } else { 'WARN' })))

    $checks.Add((New-Check 'Secure Boot' $fw.SecureBoot $(switch ($fw.SecureBoot) { 'On' { 'OK' } 'Off' { 'WARN' } default { 'INFO' } })))

    $tpm = Get-TpmState
    $checks.Add((New-Check 'TPM security chip' $tpm $(if ($tpm -like 'Present*') { 'OK' } elseif ($IsAdmin) { 'WARN' } else { 'INFO' })))

    $bitlocker = Get-BitLockerState
    $checks.Add((New-Check "BitLocker encryption ($env:SystemDrive)" $bitlocker $(if ($bitlocker -like 'On*') { 'OK' } else { 'INFO' })))

    $update = Get-LastUpdate
    if ($update) {
        $days = ((Get-Date) - $update.Date).Days
        $checks.Add((New-Check 'Last Windows update' ('{0} on {1} ({2} days ago)' -f $update.Id, (Format-Date $update.Date -DateOnly), $days) $(if ($days -le 45) { 'OK' } else { 'WARN' })))
    } else {
        $checks.Add((New-Check 'Last Windows update' 'Unknown' 'INFO'))
    }

    $smb1 = Get-Cim Win32_OptionalFeature -Filter "Name='SMB1Protocol'"
    if ($smb1) {
        $smbOn = $smb1.InstallState -eq 1
        $checks.Add((New-Check 'SMBv1 (old, unsafe file sharing)' $(if ($smbOn) { 'Enabled - should be turned off' } else { 'Disabled' }) $(if ($smbOn) { 'WARN' } else { 'OK' })))
    }

    $rdp = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server').fDenyTSConnections -eq 0
    $checks.Add((New-Check 'Remote Desktop' $(if ($rdp) { 'Enabled - turn it off if you do not use it' } else { 'Disabled' }) $(if ($rdp) { 'INFO' } else { 'OK' })))

    $guest = Invoke-Safely { Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -like '*-501' } }
    if ($guest) {
        $checks.Add((New-Check 'Guest account' $(if ($guest.Enabled) { 'Enabled' } else { 'Disabled' }) $(if ($guest.Enabled) { 'WARN' } else { 'OK' })))
    }

    $admins = Invoke-Safely { Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction SilentlyContinue }
    if ($admins) {
        $checks.Add((New-Check 'Administrator accounts' (($admins | ForEach-Object { $_.Name }) -join ', ') 'INFO'))
    }

    $checks.Add((New-Check 'This tool runs as administrator' $(if ($IsAdmin) { 'Yes' } else { 'No - some checks are limited' }) 'INFO'))

    New-Block 'Security checklist' $checks -Table
}

function Get-PerformanceInfo {
    $os = Get-Cim Win32_OperatingSystem
    $load = (Get-Cim Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    $total = [double]$os.TotalVisibleMemorySize * 1KB
    $free = [double]$os.FreePhysicalMemory * 1KB
    $processes = @(Get-Process)
    New-Block 'Right now' ([pscustomobject]@{
        'CPU load'          = $(if ($null -ne $load) { '{0:N0} %' -f $load } else { 'N/A' })
        'Memory in use'     = $(if ($total) { '{0} of {1} ({2:N0} %)' -f (Format-Size ($total - $free)), (Format-Size $total), (100 * ($total - $free) / $total) } else { 'N/A' })
        'Running processes' = $processes.Count
        'Uptime'            = $(if ($os.LastBootUpTime) { Format-Duration ((Get-Date) - $os.LastBootUpTime) } else { 'N/A' })
    })
    $top = $processes | Sort-Object -Property WorkingSet64 -Descending | Select-Object -First 10 | ForEach-Object {
        [pscustomobject]@{
            'Process'      = $_.ProcessName
            'PID'          = $_.Id
            'Memory'       = Format-Size $_.WorkingSet64
            'CPU time (s)' = $(if ($null -ne $_.CPU) { '{0:N1}' -f $_.CPU } else { 'N/A' })
        }
    }
    New-Block 'Top 10 processes by memory use' $top -Table
}

function Get-SoftwareInfo {
    $paths = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
             'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
             'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $apps = @(Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 -and -not $_.ParentKeyName } |
        ForEach-Object {
            [pscustomobject]@{
                'Program'   = "$($_.DisplayName)".Trim()
                'Version'   = Pick $_.DisplayVersion
                'Publisher' = Pick $_.Publisher
                'Installed' = Format-InstallDate $_.InstallDate
            }
        } | Sort-Object -Property Program, Version -Unique)
    New-Block ('Installed programs ({0})' -f $apps.Count) $apps -Table

    $startup = foreach ($s in Get-Cim Win32_StartupCommand) {
        [pscustomobject]@{
            'Name'    = Pick $s.Name
            'Command' = Pick $s.Command
            'Source'  = Pick $s.Location
        }
    }
    New-Block 'Programs that start with Windows' $startup -Table
}

function Get-DeviceInfo {
    $problems = foreach ($d in Get-Cim Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0') {
        $code = [int]$d.ConfigManagerErrorCode
        if ($code -eq 45) { continue }   # 45 = device is simply not plugged in
        $text = if ($DeviceErrors.ContainsKey($code)) { $DeviceErrors[$code] } else { 'Problem' }
        [pscustomobject]@{
            'Device'  = Pick $d.Name $d.DeviceID
            'Class'   = Pick $d.PNPClass
            'Problem' = 'Code {0}: {1}' -f $code, $text
            'Status'  = $(if ($code -eq 22) { 'INFO' } else { 'WARN' })
        }
    }
    if (-not $problems) {
        $problems = [pscustomobject]@{ 'Device' = 'All devices are working properly'; 'Class' = '-'; 'Problem' = '-'; 'Status' = 'OK' }
    }
    New-Block 'Devices with problems (Device Manager)' $problems -Table

    $audio = foreach ($a in Get-Cim Win32_SoundDevice) {
        [pscustomobject]@{ 'Audio device' = Pick $a.Name; 'Manufacturer' = Pick $a.Manufacturer; 'Status' = Pick $a.Status }
    }
    New-Block 'Audio devices' $audio -Table

    $cameras = foreach ($c in Get-Cim Win32_PnPEntity -Filter "PNPClass='Camera' OR PNPClass='Image'") {
        [pscustomobject]@{ 'Camera' = Pick $c.Name; 'Manufacturer' = Pick $c.Manufacturer; 'Status' = Pick $c.Status }
    }
    New-Block 'Cameras' $cameras -Table
}

function Get-QuickSummary {
    $os = Get-Cim Win32_OperatingSystem
    $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $modules = @(Get-Cim Win32_PhysicalMemory)
    $board = Get-Cim Win32_BaseBoard | Select-Object -First 1
    $disks = @(Invoke-Safely { Get-PhysicalDisk -ErrorAction SilentlyContinue })
    $diskText = if ($disks.Count) {
        ($disks | ForEach-Object { '{0} ({1}, {2})' -f "$($_.FriendlyName)".Trim(), $_.MediaType, (Format-Size $_.Size) }) -join '; '
    } else {
        (Get-Cim Win32_DiskDrive | ForEach-Object { '{0} ({1})' -f $_.Model, (Format-Size $_.Size) }) -join '; '
    }
    [pscustomobject]@{
        'Computer'         = $env:COMPUTERNAME
        'Operating system' = Pick (('{0} {1} ({2})' -f $os.Caption, $cv.DisplayVersion, $os.OSArchitecture) -replace '\s+', ' ')
        'Processor'        = Pick (Get-Cim Win32_Processor | Select-Object -First 1).Name
        'Memory'           = '{0} {1}' -f (Format-Size ($modules | Measure-Object -Property Capacity -Sum).Sum), (($modules | ForEach-Object { Get-MemoryTypeName $_ } | Sort-Object -Unique) -join '/')
        'Graphics'         = Pick ((Get-Cim Win32_VideoController | ForEach-Object { $_.Name }) -join '; ')
        'Motherboard'      = Pick ('{0} {1}' -f $board.Manufacturer, $board.Product)
        'Storage'          = Pick $diskText
    }
}

$Sections = [ordered]@{
    SYSTEM      = @{ Name = 'System overview';                Get = { Get-SystemInfo } }
    CPU         = @{ Name = 'Processor (CPU)';                Get = { Get-CpuInfo } }
    RAM         = @{ Name = 'Memory (RAM)';                   Get = { Get-RamInfo } }
    GPU         = @{ Name = 'Graphics (GPU) and monitors';    Get = { Get-GpuInfo } }
    BOARD       = @{ Name = 'Motherboard and BIOS';           Get = { Get-BoardInfo } }
    STORAGE     = @{ Name = 'Storage';                        Get = { Get-StorageInfo } }
    BATTERY     = @{ Name = 'Battery';                        Get = { Get-BatteryInfo } }
    NETWORK     = @{ Name = 'Network';                        Get = { Get-NetworkInfo } }
    SECURITY    = @{ Name = 'Security status';                Get = { Get-SecurityInfo } }
    PERFORMANCE = @{ Name = 'Performance';                    Get = { Get-PerformanceInfo } }
    SOFTWARE    = @{ Name = 'Installed programs and startup'; Get = { Get-SoftwareInfo } }
    DEVICES     = @{ Name = 'Devices and drivers';            Get = { Get-DeviceInfo } }
}

function Get-SectionBlocks([string]$Key) {
    try { @(& $Sections[$Key].Get) }
    catch { @(New-Block 'Error' ([pscustomobject]@{ 'Error' = $_.Exception.Message })) }
}

# ------------------------------------------------------------------ output ---
function Format-BlockText($Block, [int]$Width) {
    $rows = @($Block.Data)
    if (-not $rows.Count) { return '(nothing found)' }
    $text = if ($Block.Table) { $rows | Format-Table -AutoSize -Wrap | Out-String -Width $Width } else { $rows | Format-List | Out-String -Width $Width }
    $text.Trim([char[]]"`r`n")
}

function Write-Block($Block) {
    if ($Block.Title) {
        Write-Host ''
        Write-Host ('  -- {0} --' -f $Block.Title) -ForegroundColor Yellow
    }
    $width = 120
    try { $width = [Math]::Max(80, $Host.UI.RawUI.BufferSize.Width - 3) } catch { }
    foreach ($line in (Format-BlockText $Block $width) -split "`r?`n") {
        $color = @{}
        if ($line -match '\sWARN\s*$') { $color.ForegroundColor = 'Red' }
        elseif ($line -match '\sOK\s*$') { $color.ForegroundColor = 'Green' }
        Write-Host "  $line" @color
    }
}

function Invoke-Section([string]$Key) {
    if ($Key -eq 'REPORT') { New-Report; return }
    $section = $Sections[$Key]
    if (-not $section) { Write-Host "Unknown section: $Key" -ForegroundColor Red; return }
    Write-Host ''
    Write-Host ('  ===== {0} =====' -f $section.Name.ToUpper()) -ForegroundColor Cyan
    Write-Host '  Collecting information, please wait...' -ForegroundColor DarkGray
    foreach ($block in Get-SectionBlocks $Key) { Write-Block $block }
}

# ------------------------------------------------------------------ report ---
function ConvertTo-HtmlText($Value) { [System.Net.WebUtility]::HtmlEncode([string]$Value) }

function Get-StatusClass([string]$Value) {
    switch -Regex ($Value) {
        '^(OK|Healthy)$' { return 'ok' }
        '^(WARN|Warning|Unhealthy|Degraded|Error)$' { return 'warn' }
        '^INFO$' { return 'info' }
    }
    ''
}

function Format-HtmlCell([string]$Name, $Value) {
    $text = ConvertTo-HtmlText $Value
    $class = if ($Name -match '^(Status|Health)$') { Get-StatusClass "$Value" } else { '' }
    if ($class) { return "<td><span class=""pill $class"">$text</span></td>" }
    "<td>$text</td>"
}

function ConvertTo-HtmlBlock($Block) {
    $html = New-Object System.Text.StringBuilder
    if ($Block.Title) { [void]$html.Append('<h3>' + (ConvertTo-HtmlText $Block.Title) + '</h3>') }
    $rows = @($Block.Data)
    if (-not $rows.Count) { return $html.Append('<p class="muted">Nothing found.</p>').ToString() }
    if ($Block.Table) {
        $columns = @($rows[0].PSObject.Properties | ForEach-Object { $_.Name })
        [void]$html.Append('<div class="scroll"><table class="grid"><thead><tr>')
        foreach ($c in $columns) { [void]$html.Append('<th>' + (ConvertTo-HtmlText $c) + '</th>') }
        [void]$html.Append('</tr></thead><tbody>')
        foreach ($r in $rows) {
            [void]$html.Append('<tr>')
            foreach ($c in $columns) { [void]$html.Append((Format-HtmlCell $c $r.$c)) }
            [void]$html.Append('</tr>')
        }
        [void]$html.Append('</tbody></table></div>')
    } else {
        foreach ($r in $rows) {
            [void]$html.Append('<table class="kv">')
            foreach ($p in $r.PSObject.Properties) {
                [void]$html.Append('<tr><th>' + (ConvertTo-HtmlText $p.Name) + '</th>' + (Format-HtmlCell $p.Name $p.Value) + '</tr>')
            }
            [void]$html.Append('</table>')
        }
    }
    $html.ToString()
}

# Report fields that identify this PC or its owner. Hidden when the user asks for it.
$PrivateFields = 'Computer', 'Computer name', 'Current user', 'Serial number', 'System serial number', 'Serial',
    'Processor ID', 'MAC address', 'IPv4 address', 'Default gateway', 'DNS servers', 'Wi-Fi network (SSID)'
$PrivateChecks = 'Administrator accounts'

function Hide-PrivateData($Rows) {
    $names = @($env:USERNAME, $env:USERDOMAIN, $env:COMPUTERNAME) | Where-Object { $_ -and $_.Length -ge 3 } |
        Sort-Object -Unique | ForEach-Object { [regex]::Escape($_) }
    foreach ($row in $Rows) {
        foreach ($p in $row.PSObject.Properties) {
            if ($PrivateFields -contains $p.Name -or ($p.Name -eq 'Value' -and $PrivateChecks -contains $row.Check)) {
                $p.Value = '[hidden]'
            } elseif ($p.Value -is [string]) {
                # e.g. C:\Users\<name>\... inside startup commands
                foreach ($n in $names) { $p.Value = $p.Value -replace $n, '[hidden]' }
            }
        }
    }
}

# Turns whatever the user typed into a safe file name: no folders, no
# characters Windows forbids, no reserved device names, limited length.
function Get-SafeFileName([string]$Name) {
    $clean = ("$Name".Trim() -replace '\.(html?|txt)$', '') -replace '[\\/:*?"<>|\x00-\x1F]', '_'
    $clean = $clean.Trim([char[]]' .')
    if ($clean.Length -gt 100) { $clean = $clean.Substring(0, 100).Trim([char[]]' .') }
    if ($clean -match '^(CON|PRN|AUX|NUL|COM\d|LPT\d)(\..*)?$') { $clean = '_' + $clean }
    $clean
}

# Asks for the report name and returns the full path without extension.
function Read-ReportPath([string]$Folder, [string]$DefaultName) {
    while ($true) {
        Write-Host ''
        Write-Host '  Type a name for the report file, or just press Enter to use:'
        Write-Host "    $DefaultName" -ForegroundColor DarkGray
        $typed = "$(Read-Host '  File name')".Trim()
        if (-not $typed) {
            $name = $DefaultName
        } else {
            $name = Get-SafeFileName $typed
            if (-not $name) {
                Write-Host '  This name cannot be used. Please type another one.' -ForegroundColor Red
                continue
            }
            if ($name -ne ($typed -replace '\.(html?|txt)$', '')) {
                Write-Host "  Some characters are not allowed in file names. The name will be: $name" -ForegroundColor Yellow
            }
        }
        $path = Join-Path $Folder $name
        if ([IO.File]::Exists("$path.html") -or [IO.File]::Exists("$path.txt")) {
            $answer = Read-Host "  A report named '$name' already exists. Replace it? (Y/N)"
            if ($answer -notmatch '^[yY]') { continue }
        }
        return $path
    }
}

function New-Report {
    Write-Host ''
    Write-Host '  ===== CREATING FULL REPORT =====' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  The report can contain private details: user and computer name, serial'
    Write-Host '  numbers, IP and MAC addresses, Wi-Fi name. Hide them if you plan to share it.'
    $hidePrivate = (Read-Host '  Hide private details? (Y/N)') -match '^[yY]'

    $folder = [Environment]::GetFolderPath('Desktop')
    if (-not $folder -or -not [IO.Directory]::Exists($folder)) { $folder = $env:USERPROFILE }
    $folder = Join-Path $folder 'PC-Reports'
    try {
        [void][IO.Directory]::CreateDirectory($folder)
    } catch {
        Write-Host "  Could not create the folder $folder" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    $created = Get-Date
    $defaultName = if ($hidePrivate) { 'PC-Report_' + $created.ToString('yyyy-MM-dd_HH-mm') }
        else { Get-SafeFileName ('PC-Report_{0}_{1}' -f $env:COMPUTERNAME, $created.ToString('yyyy-MM-dd_HH-mm')) }
    $base = Read-ReportPath $folder $defaultName

    Write-Host ''
    Write-Host '  Collecting information, please wait...' -ForegroundColor DarkGray
    Write-Host '  [ 0] Quick summary...'
    $summary = Get-QuickSummary
    $results = New-Object System.Collections.Generic.List[object]
    $n = 0
    foreach ($key in $Sections.Keys) {
        $n++
        Write-Host ('  [{0,2}/{1}] {2}...' -f $n, $Sections.Count, $Sections[$key].Name)
        $results.Add([pscustomobject]@{ Key = $key; Name = $Sections[$key].Name; Blocks = (Get-SectionBlocks $key) })
    }
    if ($hidePrivate) {
        Hide-PrivateData $summary
        foreach ($r in $results) { foreach ($b in $r.Blocks) { Hide-PrivateData $b.Data } }
    }

    # Every row marked WARN (or a disk that is not healthy) is listed at the top.
    $warnings = @(foreach ($r in $results) {
        foreach ($row in ($r.Blocks | ForEach-Object { $_.Data })) {
            if ($row.Status -eq 'WARN' -or "$($row.Health)" -match '^(Warning|Unhealthy)$') {
                $values = @($row.PSObject.Properties | Where-Object { $_.Name -ne 'Status' } | ForEach-Object { $_.Value })
                '{0}: {1} - {2}' -f $r.Name, $values[0], $values[-1]
            }
        }
    })
    $adminText = if ($IsAdmin) { 'Yes' } else { 'No' }
    $userText = if ($hidePrivate) { '[hidden]' } else { $env:USERDOMAIN + '\' + $env:USERNAME }
    $privacyNote = if ($hidePrivate) { 'Private details are hidden in this report.' }
        else { 'This report contains private details about this PC. Share it only with people you trust.' }

    # ---- TXT report
    $txt = New-Object System.Text.StringBuilder
    $line = '=' * 78
    [void]$txt.AppendLine($line)
    [void]$txt.AppendLine(' PC INFORMATION REPORT')
    [void]$txt.AppendLine(' Created       : ' + $created.ToString('yyyy-MM-dd HH:mm'))
    [void]$txt.AppendLine(' User          : ' + $userText)
    [void]$txt.AppendLine(' Administrator : ' + $adminText)
    [void]$txt.AppendLine(' Tool          : PC Info Tool v' + $ToolVersion)
    [void]$txt.AppendLine(' Note          : ' + $privacyNote)
    [void]$txt.AppendLine($line)
    [void]$txt.AppendLine('')
    [void]$txt.AppendLine('##### QUICK SUMMARY #####')
    [void]$txt.AppendLine((Format-BlockText (New-Block '' $summary) 200))
    [void]$txt.AppendLine('')
    [void]$txt.AppendLine(('##### NEEDS ATTENTION ({0}) #####' -f $warnings.Count))
    if ($warnings.Count) { foreach ($w in $warnings) { [void]$txt.AppendLine(' ! ' + $w) } } else { [void]$txt.AppendLine(' Nothing - no problems found.') }
    $n = 0
    foreach ($r in $results) {
        $n++
        [void]$txt.AppendLine('')
        [void]$txt.AppendLine(('##### {0}. {1} #####' -f $n, $r.Name.ToUpper()))
        foreach ($b in $r.Blocks) {
            if ($b.Title) { [void]$txt.AppendLine(''); [void]$txt.AppendLine('-- ' + $b.Title + ' --') }
            [void]$txt.AppendLine((Format-BlockText $b 220))
        }
    }

    # ---- HTML report
    $nav = ($results | ForEach-Object { '<a href="#{0}">{1}</a>' -f $_.Key, (ConvertTo-HtmlText $_.Name) }) -join ''
    $sectionsHtml = ($results | ForEach-Object {
        '<section id="{0}"><h2>{1}</h2>{2}</section>' -f $_.Key, (ConvertTo-HtmlText $_.Name), (($_.Blocks | ForEach-Object { ConvertTo-HtmlBlock $_ }) -join '')
    }) -join "`r`n"
    $attention = if ($warnings.Count) {
        '<ul class="warnlist">' + (($warnings | ForEach-Object { '<li>' + (ConvertTo-HtmlText $_) + '</li>' }) -join '') + '</ul>'
    } else { '<p class="good">No problems found.</p>' }
    $title = if ($hidePrivate) { 'PC Report' } else { 'PC Report - ' + $env:COMPUTERNAME }

    $css = @'
:root { --bg:#f4f6fa; --card:#ffffff; --text:#1d2433; --muted:#6b7385; --line:#e3e7ef; --head:#f0f3f8;
        --accent:#2563eb; --ok:#15803d; --okbg:#dcfce7; --warn:#b91c1c; --warnbg:#fee2e2; --info:#1e40af; --infobg:#dbeafe; }
@media (prefers-color-scheme: dark) {
  :root { --bg:#0f141c; --card:#171e29; --text:#e6e9ef; --muted:#9aa3b2; --line:#2a3342; --head:#1d2533;
          --accent:#60a5fa; --ok:#4ade80; --okbg:#14321f; --warn:#f87171; --warnbg:#3b1717; --info:#93c5fd; --infobg:#172a46; }
}
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--text); font:14px/1.5 "Segoe UI", system-ui, sans-serif; }
header { background:var(--accent); color:#fff; padding:24px 16px; }
header h1 { margin:0 0 4px; font-size:24px; }
header p { margin:0; opacity:.9; }
nav { position:sticky; top:0; z-index:1; background:var(--card); border-bottom:1px solid var(--line); padding:8px 16px; overflow-x:auto; white-space:nowrap; }
nav a { color:var(--accent); text-decoration:none; margin-right:16px; font-weight:600; }
main { max-width:1100px; margin:0 auto; padding:16px; }
section { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:4px 20px 16px; margin:16px 0; scroll-margin-top:56px; }
h2 { font-size:19px; border-bottom:2px solid var(--accent); padding-bottom:6px; }
h3 { font-size:15px; color:var(--muted); margin:18px 0 8px; }
table { border-collapse:collapse; width:100%; margin-bottom:10px; }
th, td { text-align:left; padding:6px 10px; border-bottom:1px solid var(--line); vertical-align:top; word-break:break-word; }
table.kv th { width:34%; color:var(--muted); font-weight:600; }
table.grid th { background:var(--head); white-space:nowrap; }
.scroll { overflow-x:auto; }
.pill { display:inline-block; padding:1px 10px; border-radius:999px; font-weight:700; font-size:12px; }
.pill.ok { color:var(--ok); background:var(--okbg); }
.pill.warn { color:var(--warn); background:var(--warnbg); }
.pill.info { color:var(--info); background:var(--infobg); }
.warnlist li { color:var(--warn); margin:4px 0; }
.good { color:var(--ok); font-weight:600; }
.muted { color:var(--muted); }
footer { text-align:center; color:var(--muted); padding:24px 16px; }
@media print { nav { display:none; } section { break-inside:avoid; border:none; } }
'@

    # The page has no scripts and loads nothing from outside; the policy below enforces that.
    $html = '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">' +
        "<meta http-equiv=""Content-Security-Policy"" content=""default-src 'none'; style-src 'unsafe-inline'"">" +
        '<meta name="viewport" content="width=device-width, initial-scale=1">' +
        '<title>' + (ConvertTo-HtmlText $title) + '</title><style>' + $css + '</style></head><body>' +
        '<header><h1>' + (ConvertTo-HtmlText $title) + '</h1><p>Created ' + $created.ToString('yyyy-MM-dd HH:mm') +
        ' &middot; User ' + (ConvertTo-HtmlText $userText) + ' &middot; Administrator: ' + $adminText + '</p></header>' +
        '<nav><a href="#summary">Summary</a>' + $nav + '</nav><main>' +
        '<section id="summary"><h2>Quick summary</h2>' + (ConvertTo-HtmlBlock (New-Block '' $summary)) +
        '<h3>Needs attention (' + $warnings.Count + ')</h3>' + $attention + '</section>' +
        $sectionsHtml +
        '</main><footer>PC Info Tool v' + $ToolVersion + ' &middot; read-only report, no settings were changed<br>' + (ConvertTo-HtmlText $privacyNote) + '</footer></body></html>'

    try {
        $utf8 = New-Object System.Text.UTF8Encoding($true)
        [IO.File]::WriteAllText("$base.html", $html, $utf8)
        [IO.File]::WriteAllText("$base.txt", $txt.ToString(), $utf8)
    } catch {
        Write-Host ''
        Write-Host '  The report could not be saved:' -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host ''
    Write-Host '  Report saved:' -ForegroundColor Green
    Write-Host "    $base.html"
    Write-Host "    $base.txt"
    if ($warnings.Count) { Write-Host ('  Items that need attention: {0}' -f $warnings.Count) -ForegroundColor Red }
    Write-Host ''
    $answer = Read-Host '  Open it now? [H] HTML report  [T] text report  [F] folder  [N] no'
    switch -Regex ($answer) {
        '^[hH]' { Start-Process -FilePath "$base.html" }
        '^[tT]' { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}.txt"' -f $base) }
        '^[fF]' { Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"{0}.html"' -f $base) }
    }
}
