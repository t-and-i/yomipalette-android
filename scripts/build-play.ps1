[CmdletBinding()]
param(
    [string]$SigningProperties = (Join-Path $env:USERPROFILE '.android\yomipalette-signing\key.properties'),
    [string]$JavaBin = 'C:\Program Files\Android\Android Studio\jbr\bin'
)
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (!(Test-Path -LiteralPath $SigningProperties -PathType Leaf)) {
    throw 'Signing properties are missing. Run scripts/initialize-play-signing.ps1 first.'
}
$jarsigner = Join-Path $JavaBin 'jarsigner.exe'
if (!(Test-Path -LiteralPath $jarsigner)) { throw 'jarsigner.exe not found. Specify -JavaBin.' }
$keytool = Join-Path $JavaBin 'keytool.exe'
$certificate = Join-Path (Split-Path ([IO.Path]::GetFullPath($SigningProperties))) 'upload-certificate.pem'
if (!(Test-Path -LiteralPath $certificate)) { throw 'Expected upload-certificate.pem beside the signing properties.' }
if (!(Test-Path -LiteralPath $keytool)) { throw 'keytool.exe not found. Specify -JavaBin.' }
$oldPlayRelease = $env:ORG_GRADLE_PROJECT_PLAY_RELEASE
$oldProperties = $env:ORG_GRADLE_PROJECT_PLAY_SIGNING_PROPERTIES
Push-Location $repository
try {
    $env:ORG_GRADLE_PROJECT_PLAY_RELEASE = 'true'
    $env:ORG_GRADLE_PROJECT_PLAY_SIGNING_PROPERTIES = [IO.Path]::GetFullPath($SigningProperties)
    & flutter build appbundle --release
    if ($LASTEXITCODE -ne 0) { throw 'Play AAB build failed; do not use a previous output.' }
    $bundle = Join-Path $repository 'build\app\outputs\bundle\release\app-release.aab'
    $verification = & $jarsigner '-J-Duser.language=en' '-J-Duser.country=US' -verify $bundle 2>&1
    if ($LASTEXITCODE -ne 0 -or ($verification -join "`n") -notmatch 'jar verified\.' -or ($verification -join "`n") -match 'unsigned entries') {
        throw 'AAB signature verification failed.'
    }
    $bundleCertificate = & $keytool '-J-Duser.language=en' '-J-Duser.country=US' -printcert -rfc -jarfile $bundle 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the AAB signing certificate.' }
    $pattern = '(?s)-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----'
    $actual = [regex]::Match(($bundleCertificate -join "`n"), $pattern)
    $expected = [regex]::Match([IO.File]::ReadAllText($certificate), $pattern)
    if (!$actual.Success -or !$expected.Success -or
        ($actual.Groups[1].Value -replace '\s', '') -cne ($expected.Groups[1].Value -replace '\s', '')) {
        throw 'The AAB signer does not match the saved upload certificate.'
    }
    Write-Host "Signed Play upload bundle: $bundle"
    Get-FileHash -Algorithm SHA256 -LiteralPath $bundle
    Write-Host 'Nothing was uploaded. Play App Signing and Play Console review are separate steps.'
} finally {
    $env:ORG_GRADLE_PROJECT_PLAY_RELEASE = $oldPlayRelease
    $env:ORG_GRADLE_PROJECT_PLAY_SIGNING_PROPERTIES = $oldProperties
    Pop-Location
}
