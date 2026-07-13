[CmdletBinding(DefaultParameterSetName = 'Toggle')]
param(
    [Parameter(ParameterSetName = 'On')]
    [switch] $On,

    [Parameter(ParameterSetName = 'Off')]
    [switch] $Off,

    [Parameter(ParameterSetName = 'Status')]
    [switch] $Status
)

$ErrorActionPreference = 'Stop'

# Confirmed on this computer as "HID-compliant touch pad". This is the input
# collection used by the ELAN touchpad; COL01 is the mouse collection and must
# never be disabled here.
$touchpadInstanceId = 'HID\ELAN076C&COL03\5&25F3683&0&0002'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-AsAdministrator {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($On) { $arguments += '-On' }
    if ($Off) { $arguments += '-Off' }
    if ($Status) { $arguments += '-Status' }

    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait
    }
    catch {
        throw '无法获取管理员权限。请右键点击脚本并选择“以管理员身份运行”后重试。'
    }
}

function Get-TouchpadDevice {
    $device = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object { $_.PNPDeviceID -eq $touchpadInstanceId } |
        Select-Object -First 1
    if (-not $device) {
        throw "找不到已配置的 ELAN 触摸板设备：$touchpadInstanceId"
    }
    return $device
}

function Test-TouchpadEnabled {
    param([object] $Device)

    # Code 22 means "device disabled". Any other code is not considered disabled;
    # an error will be shown to the user rather than falsely reported as off.
    return ([int] $Device.ConfigManagerErrorCode -ne 22)
}

function Show-TouchpadStatus {
    $device = Get-TouchpadDevice
    $enabled = Test-TouchpadEnabled $device
    $stateText = if ($enabled) { '开启' } else { '关闭' }

    Write-Host "触摸板实际状态：$stateText" -ForegroundColor $(if ($enabled) { 'Green' } else { 'Yellow' })
    Write-Host "设备：$($device.Name)"
    Write-Host "设备状态：$($device.Status)（代码 $($device.ConfigManagerErrorCode)）"
}

if ($Status) {
    Show-TouchpadStatus
    exit 0
}

if (-not (Test-IsAdministrator)) {
    Restart-AsAdministrator
    exit $LASTEXITCODE
}

if (-not (Get-Command Enable-PnpDevice -ErrorAction SilentlyContinue) -or
    -not (Get-Command Disable-PnpDevice -ErrorAction SilentlyContinue)) {
    throw '当前 PowerShell 缺少 PnpDevice 模块，无法修改触摸板设备状态。'
}

$device = Get-TouchpadDevice
$currentlyEnabled = Test-TouchpadEnabled $device

if ($On) {
    $targetEnabled = $true
}
elseif ($Off) {
    $targetEnabled = $false
}
else {
    $targetEnabled = -not $currentlyEnabled
}

if ($targetEnabled -eq $currentlyEnabled) {
    $stateText = if ($targetEnabled) { '开启' } else { '关闭' }
    Write-Host ("触摸板当前已经是{0}状态，无需操作。" -f $stateText) -ForegroundColor Yellow
    exit 0
}

if ($targetEnabled) {
    Enable-PnpDevice -InstanceId $touchpadInstanceId -Confirm:$false -ErrorAction Stop
}
else {
    Disable-PnpDevice -InstanceId $touchpadInstanceId -Confirm:$false -ErrorAction Stop
}

Start-Sleep -Milliseconds 500
$updatedDevice = Get-TouchpadDevice
$actuallyEnabled = Test-TouchpadEnabled $updatedDevice

if ($actuallyEnabled -ne $targetEnabled) {
    throw "操作后状态验证失败：设备状态为 $($updatedDevice.Status)，错误代码为 $($updatedDevice.ConfigManagerErrorCode)。"
}

$stateText = if ($actuallyEnabled) { '开启' } else { '关闭' }
Write-Host ("触摸板已{0}。" -f $stateText) -ForegroundColor Green
