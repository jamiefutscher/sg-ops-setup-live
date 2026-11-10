#Requires -RunAsAdministrator
<#
  Spirited Gifts - Shipping Station Setup
  Run once per PC via SG-Setup.cmd (right-click > Run as administrator).

  What it does, in order:
    1. Logs everything to C:\SGSetup\ and to results\<PCNAME>.txt next to this script
    2. Removes Windows/OEM bloat apps (Xbox, Bing, games, Teams, Clipchamp, OEM antivirus trials)
    3. Stops Microsoft Edge running in the background / at startup
    4. Installs Google Chrome (enterprise) and enrolls it in Chrome Enterprise Core
       for the Warehouse Devices OU; locks it down (no incognito, no dev tools, Chrome = default)
    5. Installs Google Credential Provider for Windows (GCPW) with the org token,
       allows thinkliquor.com + spiritedgifts.com sign-in
    6. Installs Webroot silently with the keycode below
    7. Windows Update: downloads automatically, installs ~3 AM, never auto-restarts while
       someone is signed in, active hours 6 AM - midnight
    8. Sets desktop wallpaper from wallpaper.jpg (if present next to this script)
    9. Never sleeps; screen off after 30 min
   10. Restarts in 30 seconds -> sign in at the Google prompt with hello@thinkliquor.com
#>

# ============================ EDIT THESE ONCE ============================
$WebrootKey   = ""   # filled from secrets.txt (on the drive) or C:\SGSetup\secrets.txt - never stored in the public build
$AutoRestart  = $true   # $false = finish without restarting
# =========================================================================

# Fixed org values (from the Google Admin Console, Nov 4 2026)
$GcpwDomains          = "thinkliquor.com,spiritedgifts.com"
$GcpwToken            = ""   # from secrets.txt
$ChromeEnrollToken    = ""   # from secrets.txt
$GcpwUrl              = ""   # built after secrets.txt is read
$ChromeUrl            = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
$WebrootUrl           = "https://anywhere.webrootcloudav.com/zerol/wsainstall.exe"
$DropboxUrl           = "https://www.dropbox.com/download?full=1&plat=win"   # Dropbox offline installer
$MainTypeUrl          = "https://www.high-logic.com/MainTypeSetup-x64.exe"       # High-Logic MainType font manager (Printing/Engraving/Admin)
$CrdHostUrl           = "https://dl.google.com/edgedl/chrome-remote-desktop/chromeremotedesktophost.msi"   # Chrome Remote Desktop host
$CrdExtId             = "inomeogfingihgjfjlpeplalcfajhgai"   # Chrome Remote Desktop extension
$CardExtId            = "bgipbldjjgjidoafaoblmaagmchjfkfj"   # Spirited Gifts Card Printer extension (ext\sg-card-printer.crx on the drive)
$SsConnectUrl         = ""   # ShipStation Connect installer (link comes from ShipStation > Settings > Printing); blank = skip
$IpevoUrl             = "https://ipevo-software.s3.us-east-1.amazonaws.com/Visualizer/Windows/VisualizerDesktop_4.2.20.0.msi"   # IPEVO V4K document camera app
$WallpaperUrl         = "https://d8j0ntlcm91z4.cloudfront.net/user_32Ei7uBErmuDgqT1W4lrMb4psVl/hf_20261104_183656_f4a031bd-4edb-4585-9427-3ad783a4dee7.png"   # used when no wallpaper.jpg is next to the script

$ErrorActionPreference = "Continue"
$ProgressPreference    = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptVersion = "v56"
$Work      = "C:\SGSetup"
$Stamp     = Get-Date -Format "yyyyMMdd-HHmm"
New-Item -ItemType Directory -Path $Work -Force | Out-Null
$ResultsDir = Join-Path $ScriptDir "results"
try { New-Item -ItemType Directory -Path $ResultsDir -Force -ErrorAction Stop | Out-Null } catch { $ResultsDir = $Work }
$ResultFile = Join-Path $ResultsDir "$env:COMPUTERNAME.txt"
$Summary    = New-Object System.Collections.Generic.List[string]

# Silent mode: set by the self-updater (SG-Update task). No prompts, keep the PC name, no restart.
$Silent = ($env:SG_SILENT -eq "1")
if ($Silent) { $AutoRestart = $false }
# Live update channel: a public Dropbox folder link (live-url.txt next to the script, or the one saved on this PC)
# Live channel = the public GitHub repo (no login needed to read it). The self-updater pulls every file listed in manifest.txt.
$LiveUrl = "https://raw.githubusercontent.com/jamiefutscher/sg-ops-setup-live/main/"
# Secrets: secrets.txt next to the script (on the thumb drive) wins; otherwise the copy already on this PC. Format: KEY=value per line.
$secretsFile = @((Join-Path $ScriptDir "secrets.txt"), (Join-Path $Work "secrets.txt")) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($secretsFile) {
    foreach ($ln in Get-Content $secretsFile) { if ($ln -match '^\s*([A-Za-z]+)\s*=\s*(.+?)\s*$') { Set-Variable -Name $Matches[1] -Value $Matches[2] -Scope Script } }
    if ($secretsFile -ne (Join-Path $Work "secrets.txt")) { Copy-Item $secretsFile (Join-Path $Work "secrets.txt") -Force }
    try { icacls (Join-Path $Work "secrets.txt") /inheritance:r /grant:r "SYSTEM:F" "Administrators:F" | Out-Null } catch {}
} else { Write-Host "secrets.txt not found (drive or C:\SGSetup) - Webroot/Google enrollment will be skipped this run" -ForegroundColor Yellow }
$GcpwUrl = "https://dl.google.com/tag/s/appguid=%7B32987697-A14E-4B89-84D6-630D5431E831%7D&needsadmin=true&appname=GCPW&etoken=$GcpwToken/credentialprovider/gcpwstandaloneenterprise64.exe"
if ($Silent) { $ResultsDir = Join-Path $Work "results"; New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null; $ResultFile = Join-Path $ResultsDir "$env:COMPUTERNAME.txt" }

Write-Host ""
if (-not $Silent) { Write-Host "Station name for this PC: Pack1 Pack2 Pack3 Pack4 Production1 Production2 Engraving1 Engraving2 Printing1 Printing2 Admin  (current: $env:COMPUTERNAME). Enter = keep current:" -ForegroundColor Yellow
$NewName = (Read-Host "Station name").Trim() -replace '\s','' } else { $NewName = "" }
if ($NewName -and $NewName -notmatch '^[A-Za-z0-9-]{1,15}$') { Write-Host "Only letters, numbers, dashes, max 15 - keeping current name." -ForegroundColor Red; $NewName = "" }
if ($NewName -ieq $env:COMPUTERNAME) { $NewName = "" }
# Station names by serial number (names.txt: SERIAL | Name). Lets a PC take its proper name on its own, including on the nightly update.
$RenamedByMap = $false; $RenameOk = $false
$nmFile = Join-Path $ScriptDir "names.txt"
if ((-not $NewName) -and (Test-Path $nmFile)) {
    $serial = "$((Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber)".Trim()
    foreach ($ln in Get-Content $nmFile) {
        $parts = (($ln -split '#')[0]) -split '\|'
        if ($parts.Count -ge 2 -and $serial -and ($parts[0].Trim() -ieq $serial)) {
            $mapped = $parts[1].Trim()
            if ($mapped -match '^[A-Za-z0-9-]{1,15}$' -and $mapped -ine $env:COMPUTERNAME) { $NewName = $mapped; $RenamedByMap = $true }
        }
    }
}
$Station = if ($NewName) { $NewName } else { $env:COMPUTERNAME }
$AdminStation = ($Station -like "Admin*") -or ($Station -match '^(Groundhog|Jefa|Jack|Hamster)$')   # Admin1, Admin2, Jamie's laptop...: looser rules (Chrome unlocked)
$NeedsDropbox = $Station -match '^(Printing|Engraving|Admin|Groundhog|Jefa|Jack|Hamster)'   # design/engraving/admin stations use the Dropbox desktop app

if (-not $WebrootKey) {
    Write-Host ""
    Write-Host "Webroot keycode for THIS PC (xxxx-xxxx-xxxx-xxxx-xxxx). Press Enter to skip Webroot:" -ForegroundColor Yellow
    $WebrootKey = (Read-Host "Keycode").Trim()
}

# Old Active Directory domain (spiritedgifts.local) -> leave it so Google can own sign-in
$csPre = Get-CimInstance Win32_ComputerSystem
$LeaveDomain = $csPre.PartOfDomain -and $csPre.Domain -notmatch "WORKGROUP"
if ($Silent -and $LeaveDomain) { $LeaveDomain = $false }   # domain leave needs a typed password - only on a manual run
$LocalAdminName = "SGAdmin"
$LocalAdminPw = $null
if ($LeaveDomain) {
    Write-Host ""
    Write-Host "This PC is joined to the old domain '$($csPre.Domain)'. It will be removed from it." -ForegroundColor Yellow
    Write-Host "Choose a password for the backup local admin account '$LocalAdminName' (same on every PC is fine):" -ForegroundColor Yellow
    $LocalAdminPw = Read-Host "SGAdmin password" -AsSecureString
    if ($LocalAdminPw.Length -lt 8) { Write-Host "Password must be at least 8 characters - try again:" -ForegroundColor Yellow; $LocalAdminPw = Read-Host "SGAdmin password" -AsSecureString }
    if ($LocalAdminPw.Length -lt 8) { Write-Host "No usable password entered - this PC will STAY on the domain this run." -ForegroundColor Red; $LeaveDomain = $false }
}

Start-Transcript -Path (Join-Path $Work "setup-$Stamp.log") -Force | Out-Null
# any crash: save what we have plus the error, show it on screen, and copy it next to SG-Run (the USB) so it can be read on another computer
trap {
    $err = "CRASH: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
    $Summary.Add($err)
    New-Item -ItemType Directory -Path (Join-Path $Work "results") -Force | Out-Null
    $Summary | Set-Content -Path (Join-Path $Work "results\$env:COMPUTERNAME.txt") -Encoding UTF8
    if ($env:SG_RUNDIR) { try { New-Item -ItemType Directory -Path (Join-Path $env:SG_RUNDIR "results") -Force | Out-Null; $Summary | Set-Content (Join-Path $env:SG_RUNDIR "results\$env:COMPUTERNAME.txt") -Encoding UTF8 } catch {} }
    Write-Host "`n$err" -ForegroundColor Red
    Write-Host "Take a photo of this screen." -ForegroundColor Red
    continue
}

function Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)    { Write-Host "    OK  $msg" -ForegroundColor Green;  $Summary.Add("OK    $msg") }
function Warn($msg)  { Write-Host "    !!  $msg" -ForegroundColor Yellow; $Summary.Add("CHECK $msg") }
function Fail($msg)  { Write-Host "    XX  $msg" -ForegroundColor Red;    $Summary.Add("FAIL  $msg") }
function Set-Reg($Path, $Name, $Value, $Type = "DWord") {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}
function Get-File($Url, $Dest) {
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
        if ((Get-Item $Dest).Length -lt 100KB) { throw "download too small" }
        return $true
    } catch { Fail "Download failed: $Url ($($_.Exception.Message))"; return $false }
}

# ---------------------------------------------------------------- 1. SYSTEM INFO
Step "System"
$os   = Get-CimInstance Win32_OperatingSystem
$cs   = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$edition = $os.Caption
Ok "PC: $env:COMPUTERNAME | $($cs.Manufacturer) $($cs.Model) | Serial $($bios.SerialNumber)"
Ok "OS: $edition build $($os.BuildNumber)"
if ($edition -match "Home") {
    Warn "Windows HOME edition: the hello@ work-account sign-in (GCPW) needs Pro - double-click 'Upgrade to Windows Pro' on the desktop ($99), then re-run"
    "[InternetShortcut]`r`nURL=ms-windows-store://pdp/?productid=BF712690PL0G`r`n" | Set-Content "C:\Users\Public\Desktop\Upgrade to Windows Pro.url" -Encoding ASCII
} else { Get-ChildItem "C:\Users\Public\Desktop\Upgrade to Windows Pro.url","C:\Users\*\Desktop\Upgrade to Windows Pro.url","C:\Users\*\OneDrive*\Desktop\Upgrade to Windows Pro.url" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
# hardware inventory + keep/retire verdict
$cpu  = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
$ram  = [math]::Round($cs.TotalPhysicalMemory / 1GB)
$sysDisk = Get-PhysicalDisk -ErrorAction SilentlyContinue | Sort-Object Size -Descending | Select-Object -First 1
$diskType = if ($sysDisk) { "$($sysDisk.MediaType) $([math]::Round($sysDisk.Size/1GB))GB" } else { "unknown" }
$tpm = try { (Get-Tpm -ErrorAction Stop).TpmPresent } catch { $false }
Ok "Hardware: $cpu | $ram GB RAM | $diskType | TPM: $tpm"
$retire = @()
if ($os.Caption -match "Windows 10")         { $retire += "Windows 10 (out of support since Oct 2025)" }
if ($edition -match "Home")                  { $retire += "Home edition (not manageable)" }
if ($ram -lt 8)                              { $retire += "only $ram GB RAM" }
if ($diskType -match "HDD")                  { $retire += "spinning hard drive" }
if (-not $tpm)                               { $retire += "no TPM (can't run Windows 11)" }
if ($retire.Count -ge 2 -or ($retire -match "Windows 10|TPM")) { Fail "VERDICT: RETIRE this PC - $($retire -join '; ')" }
elseif ($retire.Count -eq 1) { Warn "VERDICT: KEEP for now, weak spot: $($retire[0])" }
else { Ok "VERDICT: KEEP - good station PC" }
try { Invoke-WebRequest -Uri "https://dl.google.com" -Method Head -UseBasicParsing -TimeoutSec 15 | Out-Null; Ok "Internet OK" }
catch { Fail "No internet - downloads will fail. Connect this PC and re-run." }

# ---------------------------------------------------------------- 1b. LEAVE OLD DOMAIN
if ($LeaveDomain) {
    Step "Leaving domain $($cs.Domain)"
    try {
        $existing = Get-LocalUser -Name $LocalAdminName -ErrorAction SilentlyContinue
        if ($existing) { Set-LocalUser -Name $LocalAdminName -Password $LocalAdminPw -PasswordNeverExpires $true }
        else { New-LocalUser -Name $LocalAdminName -Password $LocalAdminPw -PasswordNeverExpires -AccountNeverExpires -Description "Spirited Gifts local admin (backup)" | Out-Null }
        if (-not (Get-LocalGroupMember -Group Administrators -Member $LocalAdminName -ErrorAction SilentlyContinue)) {
            Add-LocalGroupMember -Group Administrators -Member $LocalAdminName
        }
        Ok "Local admin account '$LocalAdminName' ready"
    } catch { Fail "Could not create local admin '$LocalAdminName': $($_.Exception.Message) - NOT leaving the domain on this PC"; $LeaveDomain = $false }

    if ($LeaveDomain) {
        $left = $false
        try {
            # 0 = leave domain, keep the computer account in AD (old server may be off; no domain credentials needed)
            $r = Invoke-CimMethod -InputObject $cs -MethodName UnjoinDomainOrWorkgroup -Arguments @{ FUnjoinOptions = [uint32]0 }
            if ($r.ReturnValue -eq 0) { $left = $true } else { throw "UnjoinDomainOrWorkgroup returned $($r.ReturnValue)" }
        } catch {
            try { Remove-Computer -WorkgroupName "WORKGROUP" -Force -ErrorAction Stop; $left = $true } catch { Fail "Could not leave domain: $($_.Exception.Message)" }
        }
        if ($left) {
            try { Invoke-CimMethod -InputObject $cs -MethodName JoinDomainOrWorkgroup -Arguments @{ Name = "WORKGROUP"; FJoinOptions = [uint32]0 } | Out-Null } catch {}
            Ok "Left domain $($cs.Domain) (takes effect at restart). Old profile files stay in C:\Users\"
        }
    }
} else { Ok "Not domain-joined - nothing to leave" }

if ($NewName) {
    try { Rename-Computer -NewName $NewName -Force -ErrorAction Stop; $RenameOk = $true; Ok "PC will be named $NewName after restart" ; $ResultFile = Join-Path $ResultsDir "$NewName.txt" }
    catch { Fail "Rename to $NewName failed: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------- 2. DEBLOAT
Step "Removing bloat apps"
$RemoveApps = @(
  "Microsoft.BingNews","Microsoft.BingWeather","Microsoft.BingSearch","Microsoft.BingFinance","Microsoft.BingSports",
  "Microsoft.MicrosoftSolitaireCollection",   # Xbox apps intentionally KEPT: Xbox controllers print gift messages
  "Microsoft.ZuneMusic","Microsoft.ZuneVideo","Microsoft.People","Microsoft.Todos","Microsoft.MicrosoftOfficeHub",
  "Microsoft.Getstarted","Microsoft.WindowsFeedbackHub","Microsoft.YourPhone","Microsoft.SkypeApp",
  "Microsoft.Microsoft3DViewer","Microsoft.MixedReality.Portal","Clipchamp.Clipchamp","MicrosoftTeams","MSTeams",
  "Microsoft.PowerAutomateDesktop","Microsoft.OutlookForWindows","Microsoft.549981C3F5F10","Microsoft.WindowsMaps",
  "Microsoft.Copilot","Microsoft.Windows.DevHome","Microsoft.MicrosoftJournal","Microsoft.Wallet",
  "Microsoft.OneConnect","Microsoft.Messaging","Microsoft.Print3D",
  # Jamie Nov 4: nothing on Start that we don't use
  "microsoft.windowscommunicationsapps",   # Mail & Calendar
  "Microsoft.Paint","Microsoft.MSPaint","Microsoft.Office.OneNote","Microsoft.MicrosoftStickyNotes",
  "Microsoft.GetHelp","MicrosoftCorporationII.QuickAssist","Microsoft.WindowsAlarms","Microsoft.WindowsSoundRecorder",
  "Microsoft.Edge.GameAssist","MicrosoftWindows.CrossDevice","Microsoft.StartExperiencesApp","Microsoft.Whiteboard",
  "Microsoft.BingTranslator","Microsoft.NetworkSpeedTest","Microsoft.News","Microsoft.Office.Sway","Microsoft.OfficeLens",
  "Microsoft.MicrosoftPowerBIForWindows","Microsoft.RemoteDesktop"
)
$RemovePatterns = @("*king.com*","*Disney*","*Spotify*","*TikTok*","*Facebook*","*Instagram*","*LinkedIn*",
  "*Netflix*","*Twitter*","*Amazon*","*Hulu*","*CandyCrush*","*Duolingo*","*Hidden City*","*Roblox*","*Prime*",
 "*McAfee*","*Norton*","*ExpressVPN*","*Booking*","*Adobe*Express*","*Luminar*","*WildTangent*")

$removed = 0
$allPkgs  = Get-AppxPackage -AllUsers
$provPkgs = Get-AppxProvisionedPackage -Online
foreach ($name in $RemoveApps) {
    $allPkgs  | Where-Object Name -eq $name | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue; $removed++ }
    $provPkgs | Where-Object DisplayName -eq $name | ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }
}
foreach ($pat in $RemovePatterns) {
    $allPkgs  | Where-Object Name -like $pat | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue; $removed++ }
    $provPkgs | Where-Object DisplayName -like $pat | ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }
}
Ok "Store apps removed: $removed"

# OEM antivirus trials and other classic installers (McAfee, Norton, etc.)
$oemJunk = @("McAfee*","Norton*","*LiveSafe*","*WebAdvisor*","ExpressVPN*","*Booking.com*","WildTangent*",
  # browser hijackers / adware that change the search engine and nag to "open at login" (Nov 5: Production2 got Yahoo + spam)
  "OneLaunch*","Wave Browser*","WaveBrowser*","Shift Browser*","*Web Companion*","*Search Protect*","*Yahoo*","PC App Store*",
  "*ByteFence*","*Driver Support*","*PC Accelerate*","*Search Baron*","*SearchEncrypt*","*Chromium*","*CleanMyPC*","*Advanced SystemCare*",
  # laptop OEM junk (Pack5 = ASUS ROG laptop): gaming centers, OEM updaters, cloud storage trials, extra Office languages
  "ASUS GIFTBOX*","ASUS Live Update*","ASUS Splendid*","ASUS USB Charger*","ASUS Virtual Camera*","ASUS Smart Gesture*","ROG Gaming Center*","*WebStorage*",
  "NVIDIA GeForce Experience*","*SHIELD Streaming*","*ShadowPlay*","*HP Smart*","*HP Support Assistant*","*HP Wolf*","*Dell SupportAssist*","*Lenovo Vantage*",
  "Microsoft 365*- es-es","Microsoft 365*- fr-fr","Office 16 Click-to-Run Localization Component - es-es","Office 16 Click-to-Run Localization Component - fr-fr")
$uninstKeys = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
foreach ($k in Get-ItemProperty $uninstKeys -ErrorAction SilentlyContinue) {
    $dn = $k.DisplayName; if (-not $dn) { continue }
    if ($dn -like "*Webroot*" -or $dn -like "*Google*" -or $dn -like "*ShipStation*" -or $dn -like "*Finale*") { continue }
    foreach ($pat in $oemJunk) {
        if ($dn -like $pat) {
            $cmd = $k.QuietUninstallString; if (-not $cmd) { $cmd = $k.UninstallString }
            if ($cmd) {
                Write-Host "    removing $dn"
                try {
                    $guid = [regex]::Match($cmd,'\{[0-9A-Fa-f-]{36}\}').Value
                    if ($cmd -like "*OfficeClickToRun*") {
                        $proc = Start-Process cmd.exe -ArgumentList "/c `"$cmd`" DisplayLevel=False" -PassThru -WindowStyle Hidden   # Office silent switch
                    } elseif ($guid) {
                        $proc = Start-Process msiexec.exe -ArgumentList "/x $guid /qn /norestart" -PassThru
                    } else {
                        $proc = Start-Process cmd.exe -ArgumentList "/c `"$cmd`" /quiet /silent /S" -PassThru -WindowStyle Hidden
                    }
                    # never let a GUI uninstaller hang the whole run: 3 minute cap
                    if (-not $proc.WaitForExit(180000)) { $proc.Kill(); throw "timed out (needs a click)" }
                    Ok "Uninstalled: $dn"
                } catch { Warn "Could not auto-remove '$dn' ($($_.Exception.Message)) - remove by hand from Settings > Apps" }
            } else { Warn "Found '$dn' but no uninstaller string - remove by hand" }
            break
        }
    }
}
# Hijacker leftovers: startup entries and scheduled tasks
$junkNames = 'OneLaunch|WaveBrowser|Wave Browser|Shift ?Browser|WebCompanion|SearchProtect|PCAppStore|ByteFence|SearchBaron|Yahoo|Chromium'
foreach ($run in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")) {
    if (Test-Path $run) { (Get-Item $run).Property | Where-Object { $_ -match $junkNames -or (Get-ItemPropertyValue $run $_ -ErrorAction SilentlyContinue) -match $junkNames } | ForEach-Object { Remove-ItemProperty $run $_ -ErrorAction SilentlyContinue; Ok "Removed startup entry: $_" } }
}
Get-ChildItem "Registry::HKEY_USERS" -ErrorAction SilentlyContinue | ForEach-Object {
    $ur = "Registry::$($_.Name)\Software\Microsoft\Windows\CurrentVersion\Run"
    if (Test-Path $ur) { (Get-Item $ur).Property | Where-Object { $_ -match $junkNames -or (Get-ItemPropertyValue $ur $_ -ErrorAction SilentlyContinue) -match $junkNames } | ForEach-Object { Remove-ItemProperty $ur $_ -ErrorAction SilentlyContinue; Ok "Removed user startup entry: $_" } }
}
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match $junkNames -or (($_.Actions | ForEach-Object { $_.Execute }) -join ' ') -match $junkNames } | ForEach-Object { Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction SilentlyContinue; Ok "Removed scheduled task: $($_.TaskName)" }
# per-user leftovers (these installers live in AppData, not Program Files)
Get-ChildItem "C:\Users\*\AppData\Local\OneLaunch","C:\Users\*\AppData\Local\WaveBrowser","C:\Users\*\AppData\Local\Shift","C:\Users\*\AppData\Local\PCAppStore","C:\Users\*\AppData\Local\Chromium" -Directory -ErrorAction SilentlyContinue | ForEach-Object { $adDir = $_.FullName; Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$adDir*" } | Stop-Process -Force -ErrorAction SilentlyContinue; Remove-Item $adDir -Recurse -Force -ErrorAction SilentlyContinue; Ok "Removed adware folder: $adDir" }
Get-ChildItem "C:\Users\*\Desktop\*.lnk","C:\Users\Public\Desktop\*.lnk" -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -match $junkNames } | Remove-Item -Force -ErrorAction SilentlyContinue

# Consumer "suggested apps" / tips / ads
$cdm = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
Set-Reg $cdm "DisableWindowsConsumerFeatures" 1
Set-Reg $cdm "DisableSoftLanding" 1
Set-Reg $cdm "DisableCloudOptimizedContent" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" 1   # OneDrive off everywhere (Jamie: not used anywhere)
Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$odFolders = Get-ChildItem "C:\Users\*\OneDrive*" -Directory -ErrorAction SilentlyContinue | Where-Object { (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1) }
if ($odFolders) { Warn "OneDrive sync stopped but NOT uninstalled: $($odFolders.Count) profile(s) still keep files in a OneDrive folder ($(($odFolders | Select-Object -First 2 -ExpandProperty FullName) -join '; ')) - move them out, then it can go" }
else { foreach ($od in @("$env:SystemRoot\SysWOW64\OneDriveSetup.exe","$env:SystemRoot\System32\OneDriveSetup.exe","$env:ProgramFiles\Microsoft OneDrive\OneDriveSetup.exe")) { if (Test-Path $od) { Start-Process $od "/uninstall" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue; break } } }
# Windows AI features off (Copilot, Recall, Click to Do), widgets/news off, Bing out of Start search
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 1          # Recall
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "AllowRecallEnablement" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableClickToDo" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "TurnOffSavingSnapshots" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" 0                       # widgets
# the weather/widgets taskbar button lives in this package - remove it outright (policy alone leaves it on newer builds)
Get-AppxPackage -AllUsers -Name "MicrosoftWindows.Client.WebExperience" -ErrorAction SilentlyContinue | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }
Get-AppxPackage -AllUsers -Name "Microsoft.Edge.GameAssist" -ErrorAction SilentlyContinue | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "DisableWebSearch" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "EnableDynamicContentInWSB" 0        # no "search highlights" picture button
Remove-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -ErrorAction SilentlyContinue   # this one blanks the search panel on 24H2+ - replaced by per-user BingSearchEnabled=0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "HideRecommendedSection" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "ConnectedSearchUseWeb" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "AllowCrossDeviceClipboard" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableConsumerAccountStateContent" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0
Ok "Consumer features, Cortana, Copilot, Recall, Click to Do, widgets, Bing search, OneDrive sync disabled"

# Extra programs listed in remove-apps.txt next to the script
$removeFile = Join-Path $ScriptDir "remove-apps.txt"
$keepAlways = @("*Chrome*","*Google*","*Webroot*","*ShipStation*","*Finale*","*Epilog*","*Corel*","*Adobe*","*Xbox*","*Canon*","*Zebra*","*Rollo*","*DYMO*","*Brother*","*Xerox*","*Printer*","*Driver*","*Microsoft Visual C++*","*Microsoft Edge*","*.NET*","*IPEVO*","*Visualizer*","*MainType*","*High-Logic*","*LightBurn*","*Dropbox*","*AntiMicro*","*CCleaner*","*TP-Link*","*Intel*","*Realtek*","*NVIDIA*","*AMD*")
$wanted = @()
if (Test-Path $removeFile) { $wanted = Get-Content $removeFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") } }
$inventory = @()
foreach ($k in Get-ItemProperty $uninstKeys -ErrorAction SilentlyContinue) {
    $dn = $k.DisplayName; if (-not $dn -or $k.SystemComponent -eq 1) { continue }
    $inventory += $dn
    foreach ($w in $wanted) {
        if ($dn -like "*$w*") {
            if (($keepAlways | Where-Object { $dn -like $_ }) -and ($dn -notlike "AnyDesk*")) { Warn "remove-apps.txt asked for '$dn' but it is on the protected list - skipped"; break }
            $cmd = $k.QuietUninstallString; if (-not $cmd) { $cmd = $k.UninstallString }
            if (-not $cmd) { Warn "No uninstaller for '$dn' - remove by hand"; break }
            try {
                $guid = [regex]::Match($cmd,'\{[0-9A-Fa-f-]{36}\}').Value
                if ($guid) { $proc = Start-Process msiexec.exe -ArgumentList "/x $guid /qn /norestart" -PassThru }
                else { $proc = Start-Process cmd.exe -ArgumentList "/c `"$cmd`" /quiet /silent /S" -PassThru -WindowStyle Hidden }
                if (-not $proc.WaitForExit(180000)) { $proc.Kill(); throw "timed out (needs a click)" }
                Ok "Uninstalled (remove-apps.txt): $dn"
            } catch { Warn "Could not auto-remove '$dn' ($($_.Exception.Message)) - remove by hand" }
            break
        }
    }
}
$inventory = $inventory | Sort-Object -Unique
$storeApps = (Get-AppxPackage -AllUsers | Where-Object { -not $_.IsFramework -and $_.SignatureKind -ne "System" } | Select-Object -ExpandProperty Name | Sort-Object -Unique)
Ok "Installed programs listed at the bottom of the results file ($($inventory.Count) programs, $($storeApps.Count) Store apps)"

# ---------------------------------------------------------------- 3. EDGE
Step "Stopping Edge background activity"
$edge = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
Set-Reg $edge "StartupBoostEnabled" 0
Set-Reg $edge "BackgroundModeEnabled" 0
Set-Reg $edge "HideFirstRunExperience" 1
Set-Reg $edge "DefaultBrowserSettingEnabled" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate" "UpdateDefault" 1   # keep security updates, no auto-launch
foreach ($run in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")) {
    if (Test-Path $run) { Get-Item $run | Select-Object -ExpandProperty Property | Where-Object { $_ -like "*Edge*" } | ForEach-Object { Remove-ItemProperty -Path $run -Name $_ -ErrorAction SilentlyContinue } }
}
# Edge the BROWSER is blocked on purpose (owner rule: staff use Chrome only). Only msedge.exe gets the block. The web view
# (msedgewebview2.exe) and the updater must still start, or app sign-in windows break (CorelDRAW sign-in, ShipStation Connect).
# Sign-in links open in Chrome because Chrome is the default browser (set below).
foreach ($exe in "MicrosoftEdge.exe","MicrosoftEdgeUpdate.exe","msedgewebview2.exe") {
    $ifeo = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$exe"
    if ((Get-ItemProperty $ifeo -Name Debugger -ErrorAction SilentlyContinue).Debugger) { Remove-ItemProperty -Path $ifeo -Name Debugger -Force -ErrorAction SilentlyContinue; Ok "Removed launch block on $exe" }
}
# Warehouse stations only (packing, basket, production). Design, engraving, printing and admin PCs keep Edge so CorelDRAW/Adobe sign-in is never affected.
if ($Station -notmatch '^(Printing|Engraving|Design|Admin|Groundhog|Jefa|Jack|Hamster)') {
    # Anything that still tries to open Edge (a sign-in link on a PC where Edge is the default browser, a PDF) is handed to Chrome instead of doing nothing.
    $edgeVbs = "C:\SGSetup\edge-to-chrome.vbs"
    if (-not (Test-Path "C:\SGSetup")) { New-Item -ItemType Directory -Path "C:\SGSetup" -Force | Out-Null }
    @(
        'Set sh = CreateObject("WScript.Shell")'
        'Set fso = CreateObject("Scripting.FileSystemObject")'
        'c = sh.ExpandEnvironmentStrings("%ProgramFiles%") & "\Google\Chrome\Application\chrome.exe"'
        'If Not fso.FileExists(c) Then c = sh.ExpandEnvironmentStrings("%ProgramFiles(x86)%") & "\Google\Chrome\Application\chrome.exe"'
        't = ""'
        'For i = 1 To WScript.Arguments.Count - 1'
        '  a = WScript.Arguments(i)'
        '  If LCase(Left(a, 15)) = "microsoft-edge:" Then a = Mid(a, 16)'
        '  l = LCase(a)'
        '  If Left(l, 4) = "http" Or Left(l, 5) = "file:" Or Right(l, 4) = ".pdf" Or Right(l, 4) = ".htm" Or Right(l, 5) = ".html" Then t = a'
        'Next'
        'If t <> "" And fso.FileExists(c) Then sh.Run Chr(34) & c & Chr(34) & " " & Chr(34) & t & Chr(34), 1, False'
    ) | Set-Content -Path $edgeVbs -Encoding ASCII -Force
    Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\msedge.exe" "Debugger" "`"$env:SystemRoot\System32\wscript.exe`" //B //Nologo `"$edgeVbs`"" "String"
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Ok "Edge browser blocked - links and PDFs that ask for Edge open in Chrome (web view and sign-in windows still work)"
} elseif ((Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\msedge.exe" -Name Debugger -ErrorAction SilentlyContinue).Debugger) {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\msedge.exe" -Name Debugger -Force -ErrorAction SilentlyContinue; Ok "Edge left unblocked on this design/admin station"
}
# Same problem, second mechanism: Software Restriction "Disallowed" rules on Edge ("This program is blocked by group policy", 0x4EC).
# They also block the WebView2 runtime (same folder prefix), and stopped ShipStation Connect's "Log in with browser". Remove every Disallowed rule that targets Edge.
$srp = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers\0"
if (Test-Path $srp) {
    Get-ChildItem $srp -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $ip = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ("$($ip.ItemData) $($ip.Description)" -match 'Edge|Browser_Broker') { Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue; Ok "Removed program block: $($ip.Description)" }
    }
}
# Chrome is the default browser for every user (links from CorelDRAW, ShipStation Connect, Slack etc. open in Chrome, not Edge)
$assoc = @'
<?xml version="1.0" encoding="UTF-8"?>
<DefaultAssociations>
  <Association Identifier=".htm" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier=".html" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier="http" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier="https" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
</DefaultAssociations>
'@
Set-Content -Path (Join-Path $Work "default-apps.xml") -Value $assoc -Encoding UTF8
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "DefaultAssociationsConfiguration" "C:\SGSetup\default-apps.xml" "String"
Ok "Edge: no startup boost, no background mode, not pushed as default"

# ---------------------------------------------------------------- 4. CHROME
Step "Google Chrome"
$chromeExe = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chromeExe)) {
    $msi = Join-Path $Work "chrome.msi"
    if (Get-File $ChromeUrl $msi) {
        $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
        if (Test-Path $chromeExe) { Ok "Chrome installed" } else { Fail "Chrome install failed (msiexec exit $($p.ExitCode))" }
    }
} else { Ok "Chrome already installed" }

$cp = "HKLM:\SOFTWARE\Policies\Google\Chrome"
Set-Reg $cp "CloudManagementEnrollmentToken"     $ChromeEnrollToken "String"
Set-Reg $cp "CloudManagementEnrollmentMandatory" 1
Set-Reg $cp "DefaultBrowserSettingEnabled"       1
Set-Reg $cp "BrowserSignin"                      1      # allow sign-in (hello@)
Set-Reg $cp "MetricsReportingEnabled"            0
Set-Reg $cp "BackgroundModeEnabled"              0
Set-Reg $cp "PasswordManagerEnabled"             1
# anti-hijack: search engine locked to Google, site notification/popup spam off, Safe Browsing on, dangerous downloads blocked
Set-Reg $cp "DefaultSearchProviderEnabled"       1
Set-Reg $cp "DefaultSearchProviderName"          "Google" "String"
Set-Reg $cp "DefaultSearchProviderKeyword"       "google.com" "String"
Set-Reg $cp "DefaultSearchProviderSearchURL"     "{google:baseURL}search?q={searchTerms}&{google:RLZ}{google:originalQueryForSuggestion}{google:assistedQueryStats}{google:searchFieldtrialParameter}{google:searchClient}{google:sourceId}ie={inputEncoding}" "String"
Set-Reg $cp "DefaultSearchProviderSuggestURL"    "{google:baseURL}complete/search?output=chrome&q={searchTerms}" "String"
Set-Reg $cp "DefaultSearchProviderIconURL"       "https://www.google.com/favicon.ico" "String"
Set-Reg $cp "DefaultNotificationsSetting"        2      # no website can send notifications (the usual spam-popup source)
Set-Reg $cp "DefaultPopupsSetting"               2
Set-Reg $cp "SafeBrowsingProtectionLevel"        1
Set-Reg $cp "DownloadRestrictions"               1      # block downloads Safe Browsing flags as dangerous
Set-Reg $cp "PromptForDownloadLocation"          0
Set-Reg $cp "BrowserAddPersonEnabled"            0
Set-Reg $cp "BrowserGuestModeEnabled"            0
# no sign-in questions: no "turn on sync?", no "continue as / keep your browsing data?" managed-profile dialog
Set-Reg $cp "SigninInterceptionEnabled"          0
Set-Reg $cp "ProfileSeparationSettings"          2      # 2 = disabled (never asks to make a separate managed profile)
# Chrome sync ON for bookmarks, saved passwords, history and autofill (staff rely on them from the hello@ account). Extensions sync too, but only the ones on the allow list (extensions-allow.txt) can run; everything else stays blocked.
Set-Reg $cp "SyncDisabled" 0
Remove-Item "$cp\SyncTypesListDisabled" -Recurse -ErrorAction SilentlyContinue
$i = 1; foreach ($t in "apps","themes","preferences","tabs","readingList","savedTabGroups","wifiConfigurations") { Set-Reg "$cp\SyncTypesListDisabled" "$i" $t "String"; $i++ }
Set-Reg $cp "BookmarkBarEnabled" 1
# never show "Who's using Chrome?" - it swallows links other apps open (ShipStation Connect's "Log in with browser" landed on the start page instead of the login)
Set-Reg $cp "ProfilePickerOnStartupAvailability" 1
# sites staff need may open pop-up windows (ShipStation label/print windows, ShipStation Connect sign-in)
Set-Reg "$cp\PopupsAllowedForUrls" "1" "[*.]shipstation.com" "String"
Set-Reg "$cp\PopupsAllowedForUrls" "2" "[*.]finaleinventory.com" "String"
Set-Reg "$cp\PopupsAllowedForUrls" "3" "[*.]spiritedgifts.com" "String"
Set-Reg "$cp\PopupsAllowedForUrls" "4" "[*.]orderdesk.me" "String"
Set-Reg $cp "BrowserThemeColor"                  "#FFFFFF" "String"
# anything an adware installer wrote into Chrome policy that we don't manage gets cleared
Remove-Item "HKCU:\SOFTWARE\Policies\Google\Chrome" -Recurse -ErrorAction SilentlyContinue
Set-Reg "$cp\ExtensionInstallForcelist" "1" "$CrdExtId;https://clients2.google.com/service/update2/crx" "String"   # Chrome Remote Desktop on every PC
# Spirited Gifts Card Printer (Ctrl+M gift-card print): packaged CRX shipped in ext\ on the drive, force-installed from the local copy
$extSrc = Join-Path $ScriptDir "ext"
if (Test-Path (Join-Path $extSrc "sg-card-printer.crx")) {
    New-Item -ItemType Directory -Path (Join-Path $Work "ext") -Force | Out-Null
    Copy-Item (Join-Path $extSrc "*") (Join-Path $Work "ext") -Force
}
if (Test-Path "C:\SGSetup\ext\sg-card-printer.crx") {
    Set-Reg "$cp\ExtensionInstallForcelist" "2" "$CardExtId;file:///C:/SGSetup/ext/update.xml" "String"
    Ok "Card Printer extension force-installed (Ctrl+M on the ShipStation scan screen prints the gift card)"
} else { Warn "Card Printer extension not on the drive (ext\sg-card-printer.crx) - skipped" }
if ($AdminStation) {
    # admin PCs: managed + bookmarks + start page, but no lockdown (clear any lockdown left from an earlier run)
    foreach ($n in "IncognitoModeAvailability","DeveloperToolsAvailability") { Remove-ItemProperty -Path $cp -Name $n -ErrorAction SilentlyContinue }
    Remove-Item "$cp\URLBlocklist" -Recurse -ErrorAction SilentlyContinue
    Remove-Item "$cp\ExtensionInstallBlocklist" -Recurse -ErrorAction SilentlyContinue
    Ok "Chrome enrolled in Chrome Enterprise Core; ADMIN station - no YouTube block, extensions/DevTools/Incognito allowed"
} else {
    Set-Reg $cp "IncognitoModeAvailability"          1      # 1 = disabled
    Set-Reg $cp "DeveloperToolsAvailability"         2      # 2 = never
    Set-Reg "$cp\URLBlocklist" "1" "youtube.com" "String"
    Set-Reg "$cp\URLBlocklist" "2" "youtu.be" "String"
    Set-Reg "$cp\URLBlocklist" "3" "m.youtube.com" "String"
    # Every extension stays blocked except the ones listed in extensions-allow.txt (one extension ID per line, # for notes).
    # The block is what keeps the junk extensions on Production2 switched off. Wanted extensions (label resizer etc.) are added to that file by ID.
    Set-Reg "$cp\ExtensionInstallBlocklist" "1" "*" "String"
    Remove-Item "$cp\ExtensionInstallAllowlist" -Recurse -ErrorAction SilentlyContinue
    $allowFile = Join-Path $ScriptDir "extensions-allow.txt"; $ai = 3
    if (Test-Path $allowFile) { foreach ($ln in Get-Content $allowFile) { $id = ($ln -split '#')[0].Trim(); if ($id -match '^[a-p]{32}$') { Set-Reg "$cp\ExtensionInstallAllowlist" "$ai" $id "String"; $ai++ } } }
    if ($ai -gt 3) { Ok "Extra extensions allowed from extensions-allow.txt: $($ai - 3)" }
    Set-Reg "$cp\ExtensionInstallAllowlist" "1" $CrdExtId "String"   # Chrome Remote Desktop and the Card Printer are the allowed extensions
    Set-Reg "$cp\ExtensionInstallAllowlist" "2" $CardExtId "String"
    Ok "Chrome enrolled in Chrome Enterprise Core (Warehouse Devices), locked down, YouTube blocked, extensions blocked except the allow list"
}

# ---------------------------------------------------------------- 2b. CHROME REMOTE DESKTOP (done early so the PC can be taken over remotely while the rest runs)
Step "Chrome Remote Desktop"
if (Test-Path "C:\Program Files (x86)\Google\Chrome Remote Desktop") { Ok "Chrome Remote Desktop host already installed" }
else {
    $crd = Join-Path $Work "chromeremotedesktophost.msi"
    if (Get-File $CrdHostUrl $crd) {
        $p = Start-Process msiexec.exe -ArgumentList "/i `"$crd`" /qn /norestart" -PassThru
        if (-not $p.WaitForExit(240000)) { $p.Kill(); Warn "Chrome Remote Desktop installer hung and was stopped" }
        elseif (Test-Path "C:\Program Files (x86)\Google\Chrome Remote Desktop") { Ok "Chrome Remote Desktop host installed" } else { Warn "Chrome Remote Desktop host not found after install (msiexec exit $($p.ExitCode))" }
    }
}
if (Test-Path "C:\ProgramData\Google\Chrome Remote Desktop\host.json") { Ok "Remote access already turned on for this PC" }
elseif (-not $Silent) {
    $chromeExe2 = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    if (Test-Path $chromeExe2) { Start-Process $chromeExe2 -ArgumentList "--new-window https://remotedesktop.google.com/access" }
    Write-Host ""
    Write-Host "    >>> Chrome just opened the Remote Desktop page. Sign in as jamie@spiritedgifts.com, click TURN ON, Next, enter the 6-digit remote PIN." -ForegroundColor Yellow
    Write-Host "    >>> Setup keeps running behind it - do not wait." -ForegroundColor Yellow
    Warn "Remote access not turned on yet - Remote Desktop page was opened: sign in as jamie@spiritedgifts.com, Turn on, 6-digit remote PIN"
}

# ---------------------------------------------------------------- 4b. START PAGE + BOOKMARKS (from sites.txt)
Step "Start page"
$sitesFile = Join-Path $ScriptDir "sites.txt"
$tmplFile  = Join-Path $ScriptDir "start-template.html"
$startHtml = Join-Path $Work "start.html"
$startUrl  = "file:///C:/SGSetup/start.html"
if ((Test-Path $sitesFile) -and (Test-Path $tmplFile)) {
    $sites = @(); $dashUrl = $null
    foreach ($line in Get-Content $sitesFile) {
        $l = $line.Trim(); if (-not $l -or $l.StartsWith("#")) { continue }
        $parts = $l -split "\|", 2; if ($parts.Count -ne 2) { continue }
        $n = $parts[0].Trim(); $u = $parts[1].Trim()
        if ($n -eq "DASHBOARD") { $dashUrl = $u } elseif ($u -match '^https?://') { $sites += @{ Name = $n; Url = $u } }
    }
    $tiles = ($sites | ForEach-Object {
        $hn = ([uri]$_.Url).Host
        "    <a class=`"tile`" href=`"$($_.Url)`"><img src=`"https://www.google.com/s2/favicons?domain=$hn&sz=64`" alt=`"`"><div><div class=`"n`">$($_.Name)</div><div class=`"u`">$hn</div></div></a>"
    }) -join "`n"
    $dash = if ($dashUrl) { "    <iframe src=`"$dashUrl`" loading=`"lazy`"></iframe>" } else { "    <div class=`"soon`"><b>Coming soon.</b> Floor stats and the leaderboard will show here once the dashboard is live.</div>" }
    $html = (Get-Content $tmplFile -Raw -Encoding UTF8).Replace("<!--SITES-->", $tiles).Replace("<!--DASHBOARD-->", $dash).Replace("<!--PCNAME-->", $env:COMPUTERNAME)
    Set-Content -Path $startHtml -Value $html -Encoding UTF8
    Set-Reg $cp "HomepageLocation"      $startUrl "String"
    Set-Reg $cp "HomepageIsNewTabPage"  0
    Set-Reg $cp "NewTabPageLocation"    $startUrl "String"
    Set-Reg $cp "ShowHomeButton"        1
    Set-Reg $cp "RestoreOnStartup"      4
    Set-Reg "$cp\RestoreOnStartupURLs"  "1" $startUrl "String"
    Set-Reg $cp "BookmarkBarEnabled"    1
    $bm = @($sites | ForEach-Object { @{ name = $_.Name; url = $_.Url } })
    Set-Reg $cp "ManagedBookmarks" (ConvertTo-Json -InputObject $bm -Compress) "String"
    Ok "Start page built with $($sites.Count) sites (home, new tab, startup, bookmarks bar)$(if ($dashUrl) { ' + dashboard panel' })"
} else { Warn "sites.txt or start-template.html missing next to script - start page skipped" }

# ---------------------------------------------------------------- 4c. TASKBAR / EDGE REMOVAL / PER-USER FIRST-LOGON SETUP
Step "Taskbar and per-user setup"
$chromeLnk = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk"
# Station PCs: Chrome prints silently to the default printer (gift cards via the Card Printer extension) - admin PCs keep the normal dialog
try {
    $wsC = New-Object -ComObject WScript.Shell; $lC = $wsC.CreateShortcut($chromeLnk)
    if (Test-Path $chromeLnk) { $lC.Arguments = $(if ($AdminStation) { "" } else { "--kiosk-printing" }); $lC.Save() }
    $pubChrome = "C:\Users\Public\Desktop\Google Chrome.lnk"
    if (Test-Path $pubChrome) { $lP = $wsC.CreateShortcut($pubChrome); $lP.Arguments = $(if ($AdminStation) { "" } else { "--kiosk-printing" }); $lP.Save() }
    if (-not $AdminStation) { Ok "Chrome shortcuts run with --kiosk-printing (silent print to the default printer)" }
} catch { Warn "Could not set Chrome kiosk-printing shortcut: $($_.Exception.Message)" }
# "Space Warehouse" shortcut (opens the start page in Chrome) for the Start menu
$swLnk = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Space Warehouse.lnk"
try {
    $ws2 = New-Object -ComObject WScript.Shell; $l2 = $ws2.CreateShortcut($swLnk)
    $l2.TargetPath = "C:\Program Files\Google\Chrome\Application\chrome.exe"; $l2.Arguments = "file:///C:/SGSetup/start.html"
    $l2.IconLocation = "C:\Program Files\Google\Chrome\Application\chrome.exe,0"; $l2.Description = "Spirited Gifts Space Warehouse start page"; $l2.Save()
} catch { Warn "Could not create Space Warehouse shortcut: $($_.Exception.Message)" }
# Start menu: fixed pin set for everyone (Windows 11 ConfigureStartPins policy)
$startPins = @{ pinnedList = @(
    @{ desktopAppLink = "%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Space Warehouse.lnk" },
    @{ desktopAppLink = "%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk" },
    @{ desktopAppLink = "%APPDATA%\Microsoft\Windows\Start Menu\Programs\System Tools\File Explorer.lnk" },
    @{ packagedAppId = "Microsoft.WindowsCalculator_8wekyb3d8bbwe!App" },
    @{ packagedAppId = "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App" },
    @{ packagedAppId = "windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel" }
) }
$pinsJson = (ConvertTo-Json $startPins -Depth 4 -Compress) + (" " * ([int]($ScriptVersion -replace '\D','') % 7))   # trailing spaces change per version so Windows re-applies the pins to existing users
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "ConfigureStartPins" $pinsJson "String"
Ok "Start menu pinned to: Space Warehouse, Chrome, File Explorer, Calculator, Notepad, Settings (policy; Windows 11 22H2+)"
# Start-layout clone: a start2.bin next to the script (copied from the reference PC) is applied to every user, any Windows 11 build
$smPkg = "Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState"
$refStart = Join-Path $ScriptDir "start2.bin"
if (Test-Path $refStart) {
    Copy-Item $refStart (Join-Path $Work "start2.bin") -Force
    $defSm = "C:\Users\Default\AppData\Local\$smPkg"; New-Item -ItemType Directory -Path $defSm -Force | Out-Null
    Copy-Item $refStart (Join-Path $defSm "start2.bin") -Force
    Ok "Start menu layout cloned from start2.bin on the drive (applied per user at sign-in)"
} else { Remove-Item (Join-Path $Work "start2.bin") -ErrorAction SilentlyContinue; Warn "No start2.bin on the drive - Start menu pins rely on the policy only (older Windows 11 ignores it). Copy results\<ReferenceStation>-start2.bin to the drive root as start2.bin" }
$layout = @"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        <taskbar:DesktopApp DesktopApplicationLinkPath="$chromeLnk" />
        <taskbar:DesktopApp DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\System Tools\File Explorer.lnk" />
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@
$defShell = "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell"
New-Item -ItemType Directory -Path $defShell -Force | Out-Null
Set-Content -Path (Join-Path $defShell "LayoutModification.xml") -Value $layout -Encoding UTF8
Get-ChildItem "C:\Users\*\Desktop\Microsoft Edge.lnk","C:\Users\Public\Desktop\Microsoft Edge.lnk","C:\Users\Default\Desktop\Microsoft Edge.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem "C:\Users\*\OneDrive*\Desktop\Microsoft Edge.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate" "CreateDesktopShortcutDefault" 0   # Edge updates must not put the icon back
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate" "RemoveDesktopShortcutDefault" 1
Ok "Edge desktop icons removed for every user and blocked from coming back; new sign-ins get a taskbar with Chrome + File Explorer only"

# account pictures: avatar-<username>.png next to the script (avatar-info.png, avatar-admin.png, avatar-hello.png ...)
New-Item -ItemType Directory -Path (Join-Path $Work "avatars") -Force | Out-Null
Get-ChildItem (Join-Path $ScriptDir "avatar-*.png") -ErrorAction SilentlyContinue | Copy-Item -Destination (Join-Path $Work "avatars") -Force
# no avatar files on the drive/live channel? draw the standard ones (amber "SG" for info@, dark "AD" for admin@)
try {
    Add-Type -AssemblyName System.Drawing
    $avSpec = @(@{ n = "info";  bg = "#F2A93B"; fg = "#1B1F24"; t = "SG" }, @{ n = "admin"; bg = "#1B1F24"; fg = "#F2A93B"; t = "AD" })
    foreach ($a in $avSpec) {
        $out = Join-Path $Work "avatars\avatar-$($a.n).png"
        if (Test-Path $out) { continue }
        $bmp = New-Object System.Drawing.Bitmap 512, 512
        $g = [System.Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = "AntiAlias"; $g.TextRenderingHint = "AntiAlias"; $g.Clear([System.Drawing.Color]::Transparent)
        $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($a.bg))), 8, 8, 496, 496)
        $f = New-Object System.Drawing.Font "Segoe UI", 170, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
        $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = "Center"; $sf.LineAlignment = "Center"
        $g.DrawString($a.t, $f, (New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($a.fg))), (New-Object System.Drawing.RectangleF 0, 0, 512, 512), $sf)
        $g.Dispose(); $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    }
} catch { Warn "Could not draw default account pictures: $($_.Exception.Message)" }
Ok "Account pictures on drive: $((Get-ChildItem (Join-Path $Work 'avatars') -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) -join ', ')"
# SYSTEM-level helper: at every sign-in, apply any staged account picture (registry side needs admin)
$apply = @'
Get-ChildItem "C:\SGSetup\avatars\pending-*.txt" -ErrorAction SilentlyContinue | ForEach-Object {
    $sid, $dir = (Get-Content $_.FullName -Raw).Trim() -split "\|"
    if ($sid -and (Test-Path $dir)) {
        $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AccountPicture\Users\$sid"
        New-Item -Path $key -Force | Out-Null
        foreach ($z in 32,40,48,64,96,192,208,240,424,448,1080) { New-ItemProperty -Path $key -Name "Image$z" -Value (Join-Path $dir "$z`x$z.png") -PropertyType String -Force | Out-Null }
        Remove-Item $_.FullName -Force
    }
}
'@
Set-Content -Path (Join-Path $Work "apply-avatars.ps1") -Value $apply -Encoding UTF8
$ta = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\SGSetup\apply-avatars.ps1"
$tt = @((New-ScheduledTaskTrigger -AtLogOn), (New-ScheduledTaskTrigger -AtStartup))
$tt[0].Delay = "PT1M"
$tp = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName "SG-AccountPictures" -Action $ta -Trigger $tt -Principal $tp -Force | Out-Null
Ok "Account-picture helper task registered (runs 1 min after each sign-in)"
# runs once per user at first sign-in (Active Setup): unpin Edge, ask Chrome to become default
$userScript = @'
$ErrorActionPreference = "SilentlyContinue"
$log = "C:\SGSetup\results\user-$env:USERNAME.txt"
New-Item -ItemType Directory -Path (Split-Path $log) -Force | Out-Null
"user-setup ran for $env:USERNAME on $(Get-Date)" | Set-Content $log
# taskbar: wipe this user's pins so Windows re-applies LayoutModification.xml (Chrome + File Explorer, no Edge)
$myShell = "$env:LOCALAPPDATA\Microsoft\Windows\Shell"
New-Item -ItemType Directory -Path $myShell -Force | Out-Null
Copy-Item "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml" (Join-Path $myShell "LayoutModification.xml") -Force
Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband" -Recurse -Force
Remove-Item "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\*" -Force
Remove-Item "$env:USERPROFILE\Desktop\Microsoft Edge.lnk" -Force
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -PropertyType DWord -Force | Out-Null   # widgets/weather button off
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_IrisRecommendations" -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackDocs" -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_Layout" -Value 1 -PropertyType DWord -Force | Out-Null   # more pins, fewer recommendations
New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Force | Out-Null
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 1 -PropertyType DWord -Force | Out-Null   # search = icon only
Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -ErrorAction SilentlyContinue
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0 -PropertyType DWord -Force | Out-Null   # no web results in search
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Value 0 -PropertyType DWord -Force | Out-Null
"taskbar pins reset" | Add-Content $log
# Start menu layout clone (pins identical on every PC)
if (Test-Path "C:\SGSetup\start2.bin") {
    $sm = "$env:LOCALAPPDATA\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState"
    New-Item -ItemType Directory -Path $sm -Force | Out-Null
    Stop-Process -Name StartMenuExperienceHost -Force
    Copy-Item "C:\SGSetup\start2.bin" (Join-Path $sm "start2.bin") -Force
    "start menu layout applied" | Add-Content $log
}
# wallpaper for this user (works even when the machine-wide policy is ignored)
$wpFile = @("C:\SGSetup\wallpaper.png", "C:\SGSetup\wallpaper.jpg") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($wpFile) {
    New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "Wallpaper" -Value $wpFile -PropertyType String -Force | Out-Null
    New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper" -Value "0" -PropertyType String -Force | Out-Null
    Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class SGWall { [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int SystemParametersInfo(int a, int b, string c, int d); }'
    [SGWall]::SystemParametersInfo(20, 0, $wpFile, 3) | Out-Null
    "wallpaper set: $wpFile" | Add-Content $log
} else { "wallpaper file missing in C:\SGSetup" | Add-Content $log }
# Explorer must be restarted for the taskbar to rebuild - but NEVER from inside this script: Active Setup runs it via
# Explorer, so killing Explorer here re-triggers the script forever. Hand the restart to a detached helper that waits
# until this script has exited (and Active Setup has recorded it as done), then restarts Explorer exactly once.
$helper = "C:\SGSetup\restart-explorer.cmd"
"@echo off`r`ntimeout /t 20 /nobreak >nul`r`ntaskkill /f /im explorer.exe >nul 2>&1`r`ntimeout /t 2 /nobreak >nul`r`nstart explorer.exe`r`n" | Set-Content $helper -Encoding ASCII
Start-Process cmd.exe -ArgumentList "/c `"$helper`"" -WindowStyle Hidden
"explorer restart scheduled in 20s" | Add-Content $log
# Windows account picture for this user (so the sign-in tiles look different per account)
$uname = ($env:USERNAME -split "[@._]")[0].ToLower()
$av = @("C:\SGSetup\avatars\avatar-$uname.png", "C:\SGSetup\avatars\avatar-$($env:USERNAME.ToLower()).png") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($av) {
    Add-Type -AssemblyName System.Drawing
    $sid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $dir = "C:\Users\Public\AccountPictures\$sid"; New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $src = [System.Drawing.Image]::FromFile($av)
    $sizes = 32,40,48,64,96,192,208,240,424,448,1080
    $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AccountPicture\Users\$sid"
    foreach ($z in $sizes) {
        $bmp = New-Object System.Drawing.Bitmap $src, $z, $z
        $out = Join-Path $dir "$z`x$z.png"; $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    }
    $src.Dispose()
    # the registry side needs admin; the elevated helper below writes it
    "$sid|$dir" | Set-Content "C:\SGSetup\avatars\pending-$uname.txt"
    "account picture staged: $av" | Add-Content $log
}
# Num Lock off at every sign-in (laptop keyboards otherwise type numbers instead of letters)
New-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -Value "0" -PropertyType String -Force | Out-Null
# clipboard history (Win+V) and voice typing (Win+H) on for this user
New-Item -Path "HKCU:\Software\Microsoft\Clipboard" -Force | Out-Null
New-ItemProperty -Path "HKCU:\Software\Microsoft\Clipboard" -Name "EnableClipboardHistory" -Value 1 -PropertyType DWord -Force | Out-Null
New-Item -Path "HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" -Force | Out-Null
New-ItemProperty -Path "HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" -Name "HasAccepted" -Value 1 -PropertyType DWord -Force | Out-Null
# default printer: Windows never auto-switches it. No default is assigned here (owner order Nov 10: printers get assigned later, station by station).
New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows" -Force | Out-Null
New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows" -Name "LegacyDefaultPrinterMode" -Value 1 -PropertyType DWord -Force | Out-Null
# same look everywhere: Windows light mode, accent from wallpaper off
$pz = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"; New-Item -Path $pz -Force | Out-Null
New-ItemProperty -Path $pz -Name "AppsUseLightTheme" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $pz -Name "SystemUsesLightTheme" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "AutoColorization" -Value 0 -PropertyType DWord -Force | Out-Null
# same taskbar everywhere: Start and icons in the middle, search box shown
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 2 -PropertyType DWord -Force | Out-Null
# Night light off: clearing its saved state puts it back to the Windows default (off, no schedule), so the screen stays bright all day
Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current" -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like "*bluelightreduction*" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
# no "Let's finish setting up your device" / Microsoft-account nag for this user
New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" -Force | Out-Null
New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" -Name "ScoobeSystemSettingEnabled" -Value 0 -PropertyType DWord -Force | Out-Null
$cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
foreach ($n in "SubscribedContent-310093Enabled","SubscribedContent-338389Enabled","SubscribedContent-353694Enabled","SubscribedContent-353696Enabled","SoftLandingEnabled","SystemPaneSuggestionsEnabled") {
    New-ItemProperty -Path $cdm -Name $n -Value 0 -PropertyType DWord -Force | Out-Null
}
"setup-nag off" | Add-Content $log
# ask Windows to make Chrome the default browser (Windows shows its Default apps page - one click)
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (Test-Path $chrome) { Start-Process $chrome -ArgumentList "--make-default-browser" }
# close the stuck Settings window left by v35-v37 (auto-opened PIN page)
Get-Process SystemSettings -ErrorAction SilentlyContinue | Stop-Process -Force
# Num Lock off right now too, not only at next sign-in
if ([Console]::NumberLock) { (New-Object -ComObject WScript.Shell).SendKeys("{NUMLOCK}") }
# Caps Lock off too: the barcode scanners type like a keyboard, so Caps Lock flips the case of every SKU they scan
if ([Console]::CapsLock) { (New-Object -ComObject WScript.Shell).SendKeys("{CAPSLOCK}") }
'@
Set-Content -Path (Join-Path $Work "user-setup.ps1") -Value $userScript -Encoding UTF8
# machine-wide: Windows tips, "finish setting up" and Microsoft-account suggestions off
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableSoftLanding" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableCloudOptimizedContent" 1
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "DisableAutomaticRestartSignOn" 0
$as = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{7A1E5D2C-5601-4F2B-9C3D-0000000000A1}"
Set-Reg $as "(Default)"  "Spirited Gifts user setup" "String"
Set-Reg $as "StubPath"   "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\SGSetup\user-setup.ps1" "String"
Set-Reg $as "Version"    "1,0,0,14" "String"   # bump this whenever user-setup.ps1 changes so existing users get it again at next sign-in
Set-Reg $as "IsInstalled" 1
Ok "Per-user setup registered for next sign-in (taskbar reset to Chrome + Explorer, wallpaper, widgets off, Chrome default prompt)"

# ---------------------------------------------------------------- 4b. SGAdmin (same local admin on every PC)
Set-Reg "Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard" "InitialKeyboardIndicators" "2147483648" "String"   # sign-in screen: Num Lock off
# Windows Update: install quietly, never nag "restart now / wait an hour" on a signed-in user; Windows 10: no end-of-support / upgrade-to-11 screens, no News & Interests
$wu = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
Set-Reg "$wu\AU" "NoAutoRebootWithLoggedOnUsers" 1
Set-Reg $wu "SetAutoRestartNotificationDisable" 1
Set-Reg $wu "SetUpdateNotificationLevel" 1; Set-Reg $wu "UpdateNotificationLevel" 1   # 1 = no toast notifications
if ([Environment]::OSVersion.Version.Build -lt 22000) {
    Set-Reg $wu "DisableOSUpgrade" 1
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Gwx" "DisableGwx" 1
    Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\OSUpgrade" "AllowOSUpgrade" 0
    Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" "EnableFeeds" 0
    Ok "Windows 10 PC: end-of-support / upgrade nags and News & Interests turned off (this PC stays on Windows 10)"
} else { Ok "Windows Update restart reminders off (updates still install at 3 AM)" }
# AnyDesk leftovers (its virtual printer) and, on design/engraving stations, the shared hello@ login - those stations sign in as info@ (Spirited Gifts) only
Get-Printer -Name "AnyDesk*" -ErrorAction SilentlyContinue | Remove-Printer -ErrorAction SilentlyContinue
if ($NeedsDropbox -and -not $AdminStation) {
    foreach ($lu in Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "hello_thinkliquor*" -or $_.Name -like "hello*" }) {
        if ($lu.Name -eq $env:USERNAME) { Warn "Signed in as $($lu.Name) right now - it is hidden from the sign-in screen from the next restart; use Add work account > info@spiritedgifts.com" }
        Disable-LocalUser -Name $lu.Name -ErrorAction SilentlyContinue
        Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList" $lu.Name 0
        Ok "hello@ login removed from this station ($($lu.Name)) - design/engraving stations use info@spiritedgifts.com"
    }
}
Step "SGAdmin local admin"
if ($AdminPassword) {
    $sec = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
    $u = Get-LocalUser -Name "SGAdmin" -ErrorAction SilentlyContinue
    if ($u) { Set-LocalUser -Name "SGAdmin" -Password $sec -PasswordNeverExpires $true -AccountNeverExpires -UserMayChangePassword $false; Enable-LocalUser -Name "SGAdmin"; Ok "SGAdmin already here - password set to the one in secrets.txt" }
    else { New-LocalUser -Name "SGAdmin" -Password $sec -FullName "SG Admin" -Description "Spirited Gifts admin (drive runs, remote fixes)" -PasswordNeverExpires -AccountNeverExpires -UserMayNotChangePassword | Out-Null; Ok "SGAdmin created (local administrator, password in secrets.txt)" }
    if (-not (Get-LocalGroupMember -Group "Administrators" -Member "SGAdmin" -ErrorAction SilentlyContinue)) { Add-LocalGroupMember -Group "Administrators" -Member "SGAdmin" }
    Set-Reg "HKLM:\SOFTWARE\SGSetup" "AdminAccount" "SGAdmin" "String"
} else { Warn "No AdminPassword in secrets.txt - SGAdmin not created" }

# ---------------------------------------------------------------- 5. GCPW
Step "Google Credential Provider for Windows"
$gcpwExe = Join-Path $Work "gcpw64.exe"
if (-not $GcpwToken) { Warn "No Google enrollment token (secrets.txt missing) - GCPW install skipped this run" }
elseif (Get-File $GcpwUrl $gcpwExe) {
    $p = Start-Process $gcpwExe -ArgumentList "/silent /install" -Wait -PassThru
    $gcpwOk = (Test-Path "C:\Program Files\Google\Credential Provider") -or (Test-Path "C:\Program Files\Google\CredentialProvider") -or
              (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object DisplayName -like "Google Credential Provider*")
    if ($gcpwOk) { Ok "GCPW installed" } else { Fail "GCPW install failed (exit $($p.ExitCode))" }
}
Set-Reg "HKLM:\SOFTWARE\Google\GCPW" "domains_allowed_to_login" $GcpwDomains "String"
Set-Reg "HKLM:\SOFTWARE\Google\GCPW" "enable_multi_user_login" 1      # more than one Google account may sign in to this PC (info@ + hello@)
# Windows "only allow Windows Hello sign-in for Microsoft accounts" hides every other sign-in tile (including GCPW) - turn it off
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "DevicePasswordLessBuildVersion" 0
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI" "LastLoggedOnProvider" "" "String"
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "dontdisplaylastusername" 0
Ok "Sign-in screen will show the Add work account option"
Set-Reg "Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard" "InitialKeyboardIndicators" "0" "String"   # Num Lock OFF at the sign-in screen / new users
# device-management enrollment is governed by the Admin Console setting (currently ON); console overrides registry
Set-Reg "HKLM:\SOFTWARE\Policies\Google\CloudManagement" "EnrollmentToken" $GcpwToken "String"
Ok "GCPW: sign-in allowed for $GcpwDomains, org token set"

# ---------------------------------------------------------------- 6. WEBROOT
Step "Webroot"
if (-not $WebrootKey -or $WebrootKey.Length -lt 20) {
    $wr = Join-Path $Work "wsainstall.exe"
    if ((Test-Path "C:\Program Files\Webroot\WRSA.exe")) { Ok "Webroot already installed" }
    elseif (Get-File $WebrootUrl $wr) {
        $ws = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut("C:\Users\Public\Desktop\Install Webroot.lnk")
        $lnk.TargetPath = $wr; $lnk.Description = "Double-click, then enter this PC's Webroot keycode"; $lnk.Save()
        Warn "Webroot not installed (no keycode) - 'Install Webroot' shortcut left on the desktop; double-click it and enter the key"
    }
} elseif (Test-Path "C:\Program Files\Webroot\WRSA.exe") {
    Ok "Webroot already installed"
} else {
    $wr = Join-Path $Work "wsainstall.exe"
    if (Get-File $WebrootUrl $wr) {
        $wp = Start-Process $wr -ArgumentList "/key=$WebrootKey /silent /lang=en" -PassThru
        if (-not $wp.WaitForExit(180000)) { $wp.Kill(); Warn "Webroot installer hung for 3 min and was stopped - install by hand later (Settings > Apps shows if it landed)" }
        Start-Sleep 10
        $wrOk = (Test-Path "C:\Program Files\Webroot\WRSA.exe") -or (Get-ItemProperty $uninstKeys -ErrorAction SilentlyContinue | Where-Object DisplayName -like "Webroot*")
        if ($wrOk) { Ok "Webroot installed" } else { Warn "Webroot installer ran but Webroot not found yet - check Settings > Apps after restart" }
    }
}

# ---------------------------------------------------------------- 6a. IPEVO VISUALIZER (document camera app for the V4K)
Step "IPEVO Visualizer"
$ipevoInstalled = Get-ItemProperty $uninstKeys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*IPEVO*" -or $_.DisplayName -like "Visualizer*" }
if ($ipevoInstalled) { Ok "IPEVO Visualizer already installed" }
else {
    $ipevoMsi = Join-Path $ScriptDir "VisualizerDesktop.msi"                       # ship it on the drive if you have it
    if (-not (Test-Path $ipevoMsi)) { $ipevoMsi = Join-Path $Work "VisualizerDesktop.msi"; if (-not (Get-File $IpevoUrl $ipevoMsi)) { $ipevoMsi = $null } }
    if ($ipevoMsi) {
        $p = Start-Process msiexec.exe -ArgumentList "/i `"$ipevoMsi`" AcceptEULA=1 /qn /norestart" -PassThru
        if (-not $p.WaitForExit(240000)) { $p.Kill(); Warn "IPEVO installer hung for 4 min and was stopped" }
        if ($p.ExitCode -in 0, 3010) { Ok "IPEVO Visualizer installed (document camera)" } else { Warn "IPEVO Visualizer install returned $($p.ExitCode)" }
    }
}

# ---------------------------------------------------------------- 6a2. DROPBOX (Printing / Engraving / Admin stations)
if ($NeedsDropbox) {
    Step "Dropbox"
    $dbxInstalled = (Get-ItemProperty $uninstKeys -ErrorAction SilentlyContinue | Where-Object DisplayName -like "Dropbox*") -or (Test-Path "C:\Program Files (x86)\Dropbox\Client\Dropbox.exe") -or (Test-Path "C:\Program Files\Dropbox\Client\Dropbox.exe")
    if ($dbxInstalled) { Ok "Dropbox already installed" }
    else {
        $dbx = Join-Path $Work "DropboxOfflineInstaller.exe"
        if (Get-File $DropboxUrl $dbx) {
            $p = Start-Process $dbx -ArgumentList "/S /NOLAUNCH" -PassThru
            if (-not $p.WaitForExit(300000)) { $p.Kill(); Warn "Dropbox installer hung for 5 min and was stopped" }
            else { Ok "Dropbox installed - staff sign in to it once from the Start menu" }
        }
    }
}

# ---------------------------------------------------------------- 6a3. HIGH-LOGIC MAINTYPE (font manager for design stations)
if ($NeedsDropbox) {
    Step "MainType font manager"
    $mtExe = @("C:\Program Files\High-Logic\MainType\MainType.exe","C:\Program Files (x86)\High-Logic\MainType\MainType.exe","C:\Program Files\High-Logic MainType\MainType.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    $mtInstalled = $mtExe -or (Get-ItemProperty $uninstKeys -ErrorAction SilentlyContinue | Where-Object DisplayName -like "*MainType*")
    if ($mtInstalled) { Ok "MainType already installed" }
    else {
        $mt = Join-Path $Work "MainTypeSetup-x64.exe"
        if (Get-File $MainTypeUrl $mt) {
            $p = Start-Process $mt -ArgumentList "/VERYSILENT /NORESTART /SUPPRESSMSGBOXES" -PassThru
            if (-not $p.WaitForExit(240000)) { $p.Kill(); Warn "MainType installer hung for 4 min and was stopped - install by hand from C:\SGSetup\MainTypeSetup-x64.exe" }
            elseif (Get-ItemProperty $uninstKeys -ErrorAction SilentlyContinue | Where-Object DisplayName -like "*MainType*") { Ok "MainType installed - enter the license key and add Dropbox\Personalization Department\07 Fonts on first open" }
            else { Warn "MainType installer finished but MainType not found - install by hand from C:\SGSetup\MainTypeSetup-x64.exe" }
        }
    }
}

# MainType runs at every sign-in on design stations (minimized to the tray)
if ($NeedsDropbox) {
    if (-not $mtExe) { $mtExe = @("C:\Program Files\High-Logic\MainType\MainType.exe","C:\Program Files (x86)\High-Logic\MainType\MainType.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1 }
    if ($mtExe) {
        try { $ws3 = New-Object -ComObject WScript.Shell; $l3 = $ws3.CreateShortcut("C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\MainType.lnk"); $l3.TargetPath = $mtExe; $l3.WindowStyle = 7; $l3.Save(); Ok "MainType starts with Windows (minimized)" }
        catch { Warn "Could not add MainType to Startup: $($_.Exception.Message)" }
    }
}

# ---------------------------------------------------------------- 6a5. SLACK (every station)
Step "Slack"
if ((Test-Path "C:\Program Files\Slack\slack.exe") -or (Get-ChildItem "C:\Users\*\AppData\Local\slack\slack.exe" -ErrorAction SilentlyContinue)) { Ok "Slack already installed" }
elseif (Get-Command winget -ErrorAction SilentlyContinue) {
    $p = Start-Process winget -ArgumentList "install --id SlackTechnologies.Slack -e --scope machine --silent --accept-package-agreements --accept-source-agreements --disable-interactivity" -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -eq 0) { Ok "Slack installed (machine-wide) - staff sign in once" } else { Warn "Slack install failed (winget exit $($p.ExitCode))" }
} else { Warn "winget not available - Slack skipped" }

# ---------------------------------------------------------------- 6a5b. DITTO (clipboard) AND CCLEANER (every station, owner order Nov 10)
Step "Ditto and CCleaner"
foreach ($app in @(@{ Name = "Ditto"; Id = "Ditto.Ditto" }, @{ Name = "CCleaner"; Id = "Piriform.CCleaner" })) {
    $have = Get-ItemProperty $uninstKeys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "$($app.Name)*" }
    if ($have) { Ok "$($app.Name) already installed" }
    elseif (Get-Command winget -ErrorAction SilentlyContinue) {
        $p = Start-Process winget -ArgumentList "install --id $($app.Id) -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity" -Wait -PassThru -WindowStyle Hidden
        if ($p.ExitCode -eq 0) { Ok "$($app.Name) installed" } else { Warn "$($app.Name) install failed (winget exit $($p.ExitCode))" }
    } else { Warn "winget not available - $($app.Name) skipped (installs on the next manual SG-Run)" }
}

# ---------------------------------------------------------------- 6a6. SHIPSTATION CONNECT (every station with a printer)
Step "ShipStation Connect"
$ssInstalled = (Get-ItemProperty $uninstKeys -ErrorAction SilentlyContinue | Where-Object DisplayName -like "*ShipStation Connect*") -or (Get-ChildItem "C:\Users\*\AppData\Local\Programs\ShipStation Connect\*.exe","C:\Program Files\ShipStation Connect\*.exe" -ErrorAction SilentlyContinue)
if ($ssInstalled) { Ok "ShipStation Connect already installed - sign in once with the ShipStation user, then share its printers" }
elseif ($SsConnectUrl -match '^https?://') {
    $ss = Join-Path $Work "ShipStationConnect.exe"
    if (Get-File $SsConnectUrl $ss) {
        $p = Start-Process $ss -ArgumentList "/S" -PassThru
        if (-not $p.WaitForExit(240000)) { $p.Kill(); Warn "ShipStation Connect installer hung and was stopped - run C:\SGSetup\ShipStationConnect.exe by hand" }
        else { Ok "ShipStation Connect installed - sign in once with the ShipStation user, then share its printers" }
    }
} else { Warn "ShipStation Connect: no installer link in the build yet - install from ShipStation > Settings > Printing > Download" }

# ---------------------------------------------------------------- 6b. NETWORK PRINTERS (printers.txt)
Step "Network printers"
$prFile = Join-Path $ScriptDir "printers.txt"
$prAdded = 0
if (Test-Path $prFile) {
    foreach ($line in Get-Content $prFile) {
        $l = $line.Trim(); if (-not $l -or $l.StartsWith("#")) { continue }
        $parts = $l -split "\|", 2; if ($parts.Count -ne 2) { continue }
        $pn = $parts[0].Trim(); $ip = $parts[1].Trim()
        try {
            if (-not (Get-PrinterDriver -Name "Microsoft PCL6 Class Driver" -ErrorAction SilentlyContinue)) { Add-PrinterDriver -Name "Microsoft PCL6 Class Driver" -ErrorAction Stop }
            $portName = "IP_$ip"
            if (-not (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)) { Add-PrinterPort -Name $portName -PrinterHostAddress $ip -ErrorAction Stop }
            if (Get-Printer -Name $pn -ErrorAction SilentlyContinue) { Ok "Printer already present: $pn" }
            else { Add-Printer -Name $pn -DriverName "Microsoft PCL6 Class Driver" -PortName $portName -ErrorAction Stop; Ok "Printer added: $pn ($ip)" }
            $prAdded++
        } catch { Fail "Printer $pn ($ip) failed: $($_.Exception.Message)" }
    }
}
if ($prAdded -eq 0) { Warn "No network printers added - fill in printers.txt (Angelina / Gabriel IPs) and re-run" }

# Local printers renamed after the station: <Station>-Card (Canon), <Station>-Label (4x6), <Station>-Barcode (2.25")
$printerList = @()
foreach ($pr in Get-Printer -ErrorAction SilentlyContinue) {
    $printerList += "$($pr.Name)  [$($pr.DriverName)]  port $($pr.PortName)"
    if ($pr.Name -match '^(Angelina|Gabriel)$' -or $pr.Name -match 'Microsoft|OneNote|Fax|PDF|XPS|Adobe') { continue }
    if ($pr.Name -match '^(.+)-(Card|Label|Barcode)$') {
        if ($Matches[1] -eq $Station) { continue }     # already right
        $fix = "$Station-$($Matches[2])"
        try { Rename-Printer -Name $pr.Name -NewName $fix -ErrorAction Stop; Ok "Printer renamed: '$($pr.Name)' -> $fix" } catch { Warn "Could not rename printer '$($pr.Name)': $($_.Exception.Message)" }
        continue
    }
    $d = "$($pr.Name) $($pr.DriverName)"
    $role = $null
    # the printer's current name wins when it already says what it is (e.g. "Production Shipping Label Printer")
    if     ($pr.Name -match 'Barcode')                                        { $role = "Barcode" }
    elseif ($pr.Name -match 'Label|Shipping')                                 { $role = "Label" }
    elseif ($pr.Name -match 'Card')                                           { $role = "Card" }
    elseif ($d -match 'Canon')                                                { $role = "Card" }
    elseif ($d -match 'Rollo|4XL|ZD420|ZD421|ZD620|ZD621|ZP450|ZP505|GK420|GX420|ZT|LP2844|TLP2844|Brother QL-1|MUNBYN|Phomemo|Arkscan') { $role = "Label" }
    elseif ($d -match 'ZD410|ZD411|ZD510|LabelWriter 4\d0|LabelWriter 5\d0|Brother QL-[5678]|TSC|Honeywell|GC420|GK420t') { $role = "Barcode" }
    if ($role) {
        $newPr = "$Station-$role"
        if (-not (Get-Printer -Name $newPr -ErrorAction SilentlyContinue)) {
            try { Rename-Printer -Name $pr.Name -NewName $newPr -ErrorAction Stop; Ok "Printer renamed: '$($pr.Name)' -> $newPr" } catch { Warn "Could not rename printer '$($pr.Name)': $($_.Exception.Message)" }
        }
    } else { Warn "Printer '$($pr.Name)' not renamed (can't tell its role from the driver) - tell Jamie: Card / Label / Barcode" }
}
# Stop Windows from switching the default printer to whatever printed last; per-user part in user-setup.ps1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers" "LegacyDefaultPrinterMode" 1
Ok "Windows will no longer auto-change the default printer"

# ---------------------------------------------------------------- 6c. DICTATION, CLIPBOARD HISTORY, DITTO
Step "Dictation and clipboard"
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "AllowClipboardHistory" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization" "AllowInputPersonalization" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Speech" "AllowSpeechModelUpdate" 1
Ok "Win+H dictation and Win+V clipboard history allowed (user-setup turns them on per sign-in)"

# ---------------------------------------------------------------- 7. WINDOWS UPDATE
Step "Windows Update schedule"
$au = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
Set-Reg $au "NoAutoUpdate"                   0
Set-Reg $au "AUOptions"                      4      # auto download + scheduled install
Set-Reg $au "ScheduledInstallDay"            0      # every day
Set-Reg $au "ScheduledInstallTime"           3      # 3 AM
Set-Reg $au "NoAutoRebootWithLoggedOnUsers"  1
Set-Reg $au "AlwaysAutoRebootAtScheduledTime" 0
$wu = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
Set-Reg $wu "SetActiveHours"      1
Set-Reg $wu "ActiveHoursStart"    6
Set-Reg $wu "ActiveHoursEnd"      0      # midnight (18h max window)
Set-Reg $wu "DeferFeatureUpdates" 1
Set-Reg $wu "DeferFeatureUpdatesPeriodInDays" 180   # big version upgrades wait 6 months
Set-Reg $wu "DeferQualityUpdates" 1
Set-Reg $wu "DeferQualityUpdatesPeriodInDays" 7     # security patches wait 1 week
Set-Reg "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" "ActiveHoursStart" 6
Set-Reg "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" "ActiveHoursEnd"   0
Ok "Updates install ~3 AM, no restart while signed in, active hours 6 AM-midnight, feature upgrades deferred 180d"

# ---------------------------------------------------------------- 8. WALLPAPER
Step "Wallpaper"
$wpSrc = Join-Path $ScriptDir "wallpaper.jpg"
$wp    = Join-Path $Work "wallpaper.jpg"
if (Test-Path $wpSrc) { Copy-Item $wpSrc $wp -Force }
elseif ($WallpaperUrl -match '^https?://') { $wp = Join-Path $Work "wallpaper.png"; Get-File $WallpaperUrl $wp | Out-Null }
# make sure what we have is really an image (PNG or JPEG header), not an error page
$isImg = $false
if (Test-Path $wp) {
    $b = [System.IO.File]::ReadAllBytes($wp)[0..3]
    $isImg = ($b[0] -eq 0x89 -and $b[1] -eq 0x50) -or ($b[0] -eq 0xFF -and $b[1] -eq 0xD8)
    if (-not $isImg) { Remove-Item $wp -Force; Fail "Wallpaper download was not an image - desktop background left as is" }
}
if ($isImg) {
    # point the Chrome start page at the same image
    if (Test-Path $startHtml) { (Get-Content $startHtml -Raw).Replace("file:///C:/SGSetup/wallpaper.jpg", "file:///C:/SGSetup/" + (Split-Path $wp -Leaf)) | Set-Content $startHtml -Encoding UTF8 }
    $pol = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    Set-Reg $pol "Wallpaper"      $wp "String"
    Set-Reg $pol "WallpaperStyle" "10" "String"    # 10 = fill screen, no distortion
    Ok "Wallpaper set for all users (applied per user at next sign-in)"
} else { Warn "No wallpaper available - desktop background left as is" }

# save this PC's current Start layout (hello@ profile) so one PC can serve as the reference for all the others
$helloSm = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName "AppData\Local\$smPkg\start2.bin" } | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($helloSm) { Copy-Item $helloSm (Join-Path $ResultsDir "$Station-start2.bin") -Force -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------- 8b. WALLPAPER ROTATION
Step "Wallpaper rotation"
$wpDir = Join-Path $Work "wallpapers"; New-Item -ItemType Directory -Path $wpDir -Force | Out-Null
$wpSrcDir = Join-Path $ScriptDir "wallpapers"
if (Test-Path $wpSrcDir) { Get-ChildItem $wpSrcDir -Include *.jpg,*.jpeg,*.png -Recurse -ErrorAction SilentlyContinue | Copy-Item -Destination $wpDir -Force }
$rotate = @'
$ErrorActionPreference = "SilentlyContinue"
$pics = Get-ChildItem "C:\SGSetup\wallpapers" -Include *.jpg,*.jpeg,*.png -Recurse
if (-not $pics) { $pics = Get-ChildItem "C:\SGSetup\wallpaper.*" -Include *.jpg,*.png }
if (-not $pics) { return }
$last = (Get-ItemProperty "HKCU:\Software\SGSetup" -Name LastWallpaper).LastWallpaper
$pool = @($pics | Where-Object { $_.FullName -ne $last }); if (-not $pool) { $pool = @($pics) }
$pick = ($pool | Get-Random).FullName
New-Item -Path "HKCU:\Software\SGSetup" -Force | Out-Null
New-ItemProperty -Path "HKCU:\Software\SGSetup" -Name LastWallpaper -Value $pick -PropertyType String -Force | Out-Null
New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "Wallpaper" -Value $pick -PropertyType String -Force | Out-Null
New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10" -PropertyType String -Force | Out-Null
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class SGWall2 { [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int SystemParametersInfo(int a, int b, string c, int d); }'
[SGWall2]::SystemParametersInfo(20, 0, $pick, 3) | Out-Null
'@
Set-Content -Path (Join-Path $Work "rotate-wallpaper.ps1") -Value $rotate -Encoding UTF8
try {
    $ra = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\SGSetup\rotate-wallpaper.ps1"
    $rt = @((New-ScheduledTaskTrigger -AtLogOn), (New-ScheduledTaskTrigger -Daily -At 6:00AM))
    $rt[0].Delay = "PT2M"
    $rp = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Users" -RunLevel Limited   # runs as whoever is signed in
    $rs = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName "SG-Wallpaper" -Action $ra -Trigger $rt -Principal $rp -Settings $rs -Force | Out-Null
    Ok "Wallpaper: random pick from C:\SGSetup\wallpapers at each sign-in and 6 AM ($((Get-ChildItem $wpDir -ErrorAction SilentlyContinue).Count) images on this PC)"
} catch { Warn "Wallpaper rotation task not registered: $($_.Exception.Message)" }

# ---------------------------------------------------------------- 8c. SELF-UPDATER
Step "Self-updater"
Set-Reg "HKLM:\SOFTWARE\SGSetup" "Station" $Station "String"
Set-Reg "HKLM:\SOFTWARE\SGSetup" "LiveUrl" $LiveUrl "String"
$updater = @'
# SG-Update: nightly. Pulls the live build (every file in manifest.txt) from the GitHub repo, re-runs setup silently when
# VERSION changed, refreshes wallpapers and tidies Edge icons every time. Secrets stay in C:\SGSetup\secrets.txt.
$ErrorActionPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$log = "C:\SGSetup\update.log"
function L($m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm') $m" | Add-Content $log }
$reg = Get-ItemProperty "HKLM:\SOFTWARE\SGSetup"
$base = $reg.LiveUrl
if (-not $base) { L "no LiveUrl set - nothing to do"; return }
if (-not $base.EndsWith('/')) { $base += '/' }
$live = "C:\SGSetup\live"
try { $newVer = (Invoke-WebRequest -Uri ($base + "VERSION.txt?t=" + [int](Get-Date -UFormat %s)) -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop).Content.Trim() } catch { L "VERSION check failed: $($_.Exception.Message)"; return }
$curVer = "SG-Setup " + $reg.Version
if ($newVer -eq $curVer) { L "up to date ($curVer)"; return }
L "updating: $curVer -> $newVer"
try { $files = (Invoke-WebRequest -Uri ($base + "manifest.txt") -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop).Content -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') } } catch { L "manifest download failed: $($_.Exception.Message)"; return }
Remove-Item $live -Recurse -Force; New-Item -ItemType Directory -Path $live -Force | Out-Null
$bad = 0
foreach ($f in $files) {
    $dest = Join-Path $live ($f -replace '/', '\')
    New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
    try { Invoke-WebRequest -Uri ($base + $f) -OutFile $dest -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop } catch { L "download failed: $f"; $bad++ }
}
if ($bad -gt 0 -or -not (Test-Path (Join-Path $live "SG-Setup.ps1"))) { L "incomplete download ($bad failed) - not running"; return }
# wallpapers: mirror every time a version lands
$wpSrc = Join-Path $live "wallpapers"
if (Test-Path $wpSrc) {
    $wpDst = "C:\SGSetup\wallpapers"; New-Item -ItemType Directory -Path $wpDst -Force | Out-Null
    $keep = Get-ChildItem $wpSrc -Include *.jpg,*.jpeg,*.png -Recurse | ForEach-Object { Copy-Item $_.FullName $wpDst -Force; $_.Name }
    Get-ChildItem $wpDst | Where-Object { $keep -notcontains $_.Name } | Remove-Item -Force
    L "wallpapers synced: $($keep.Count)"
}
Get-ChildItem "C:\Users\*\Desktop\Microsoft Edge.lnk","C:\Users\Public\Desktop\Microsoft Edge.lnk" | Remove-Item -Force
$env:SG_SILENT = "1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $live "SG-Setup.ps1") *>> "C:\SGSetup\update-run.log"
L "setup run finished (exit $LASTEXITCODE); now $((Get-ItemProperty 'HKLM:\SOFTWARE\SGSetup').Version)"
'@
Set-Content -Path (Join-Path $Work "sg-update.ps1") -Value $updater -Encoding UTF8
try {
    $ua = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\SGSetup\sg-update.ps1"
    $ut = @((New-ScheduledTaskTrigger -Daily -At 3:30AM), (New-ScheduledTaskTrigger -AtStartup))
    $ut[1].Delay = "PT10M"
    $up = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    $us = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2) -RunOnlyIfNetworkAvailable
    Register-ScheduledTask -TaskName "SG-Update" -Action $ua -Trigger $ut -Principal $up -Settings $us -Force | Out-Null
    Ok "Self-updater on: checks GitHub (sg-ops-setup-live) nightly at 3:30 AM and 10 min after boot; re-runs setup when a new version is posted"
} catch { Warn "Self-updater task not registered: $($_.Exception.Message)" }

# ---------------------------------------------------------------- 9. POWER
Step "Power"
powercfg /change standby-timeout-ac 0      | Out-Null
powercfg /change hibernate-timeout-ac 0    | Out-Null
powercfg /change monitor-timeout-ac 60     | Out-Null
powercfg /hibernate off                    | Out-Null
# no sign-in prompt when the screen wakes - staff sign in once at boot
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 0 | Out-Null
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 0 | Out-Null
powercfg /SETACTIVE SCHEME_CURRENT | Out-Null
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" "NoLockScreen" 1
Ok "Never sleeps on AC; screen off after 30 min; no sign-in prompt on wake (lock with Win+L when needed)"

# ---------------------------------------------------------------- RESULTS
Stop-Transcript | Out-Null
$header = @(
  "Spirited Gifts shipping station setup $ScriptVersion - $env:COMPUTERNAME - $(Get-Date)"
  "$($cs.Manufacturer) $($cs.Model) | Serial $($bios.SerialNumber) | $edition build $($os.BuildNumber)"
  ""
)
$extInv = @(Get-ChildItem "C:\Users\*\AppData\Local\Google\Chrome\User Data\*\Extensions\*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $mf = Get-ChildItem $_.FullName -Recurse -Filter manifest.json -ErrorAction SilentlyContinue | Select-Object -First 1
    $nm = try { (Get-Content $mf.FullName -Raw | ConvertFrom-Json).name } catch { "?" }
    "$($_.Name)  $nm  ($(($_.FullName -split '\\')[2]))"
} | Sort-Object -Unique)
$tail = @("", "---- Chrome extensions found in user profiles ----") + $extInv + @("", "---- Printers on this PC ----") + $printerList + @("", "---- Installed programs (for remove-apps.txt) ----") + $inventory + @("", "---- Store apps ----") + $storeApps
($header + $Summary + $tail) | Set-Content -Path $ResultFile -Encoding UTF8
Set-Reg "HKLM:\SOFTWARE\SGSetup" "Version" $ScriptVersion "String"   # stamped only when the run got this far
Set-Reg "HKLM:\SOFTWARE\SGSetup" "LastRun" (Get-Date -Format "yyyy-MM-dd HH:mm") "String"
Write-Host "`n===================== DONE =====================" -ForegroundColor Cyan
$Summary | ForEach-Object { Write-Host "  $_" }
Write-Host "`nResults saved to $ResultFile"
Write-Host "Full log:         $Work\setup-$Stamp.log"

# A rename picked up on the nightly update only takes effect after a restart: do it once, with a 5 minute warning on screen.
if ($Silent -and $RenamedByMap -and $RenameOk) { shutdown.exe /r /t 300 /c "This PC is being renamed to $NewName and will restart in 5 minutes. Save your work." | Out-Null }
if ($AutoRestart) {
    Write-Host "`nRestarting in 30 seconds. After restart: bottom-left click 'Other user' > 'Sign in with your work account' > hello@thinkliquor.com" -ForegroundColor Yellow
    if ($LeaveDomain) { Write-Host "Backup local sign-in if Google fails: user '$LocalAdminName' with the password you just set." -ForegroundColor Yellow }
    Write-Host "Press Ctrl+C now to cancel the restart."
    Start-Sleep 30
    Restart-Computer -Force
} else {
    Write-Host "`nRestart this PC, then sign in at the Google prompt as hello@thinkliquor.com" -ForegroundColor Yellow
}
