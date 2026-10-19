[CmdletBinding()]
param(
    [string]$SigningDirectory = (Join-Path $env:USERPROFILE '.android\yomipalette-signing'),
    [string]$JavaBin = 'C:\Program Files\Android\Android Studio\jbr\bin'
)
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$directory = [IO.Path]::GetFullPath($SigningDirectory)
if ($directory -eq $repository -or $directory.StartsWith($repository + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Signing material must be stored outside the repository.'
}
if (Test-Path -LiteralPath $directory) {
    throw 'Signing directory already exists. Existing keys will not be overwritten.'
}
$keytool = Join-Path $JavaBin 'keytool.exe'
if (!(Test-Path -LiteralPath $keytool)) { throw 'keytool.exe not found. Specify -JavaBin.' }

# Restrict the directory before creating any private material.
New-Item -ItemType Directory -Path $directory | Out-Null
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetOwner($identity)
$acl.SetAccessRuleProtection($true, $false)
$rule = New-Object Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$acl.AddAccessRule($rule)
Set-Acl -LiteralPath $directory -AclObject $acl

$bytes = New-Object byte[] 48
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes)
$rng.Dispose()
$password = [Convert]::ToBase64String($bytes)
$keystore = Join-Path $directory 'upload.jks'
$properties = Join-Path $directory 'key.properties'
$oldPassword = $env:YOMIPALETTE_KEYTOOL_PASSWORD
try {
    $env:YOMIPALETTE_KEYTOOL_PASSWORD = $password
    & $keytool -genkeypair -keystore $keystore -storetype JKS -alias upload -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=YomiPalette Upload' -storepass:env YOMIPALETTE_KEYTOOL_PASSWORD -keypass:env YOMIPALETTE_KEYTOOL_PASSWORD
    if ($LASTEXITCODE -ne 0) { throw 'Upload key generation failed. Inspect the signing directory before retrying.' }
    $content = "storeFile=$($keystore.Replace('\', '/'))`nstorePassword=$password`nkeyAlias=upload`nkeyPassword=$password`n"
    [IO.File]::WriteAllText($properties, $content, (New-Object Text.UTF8Encoding($false)))
    & $keytool -exportcert -rfc -keystore $keystore -alias upload -storepass:env YOMIPALETTE_KEYTOOL_PASSWORD -file (Join-Path $directory 'upload-certificate.pem')
    if ($LASTEXITCODE -ne 0) { throw 'Certificate export failed.' }
} finally {
    $env:YOMIPALETTE_KEYTOOL_PASSWORD = $oldPassword
    $password = $null
    $content = $null
    [Array]::Clear($bytes, 0, $bytes.Length)
}
Write-Host "Created upload key and signing properties in: $directory"
Write-Host 'Back up this directory securely. key.properties contains passwords; never share or commit it.'
