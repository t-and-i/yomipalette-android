[CmdletBinding()]
param(
    [string]$SigningProperties = (Join-Path $env:USERPROFILE '.android\yomipalette-signing\key.properties'),
    [string]$JavaBin = 'C:\Program Files\Android\Android Studio\jbr\bin',
    [switch]$InternalTestAds,
    [string]$PurchaseVerifierUrl = $env:YOMIPALETTE_BILLING_VERIFY_URL
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
    $flutterArgs = @('build', 'appbundle', '--release')
    if ($InternalTestAds) {
        # A QA-only AAB: use sample ads AND the explicitly unverified Billing flow.
        # Never promote it to the production track.
        $flutterArgs += '--dart-define=YOMIPALETTE_TEST_ADS=true'
        $flutterArgs += '--dart-define=YOMIPALETTE_AD_DIAGNOSTICS=true'
        $flutterArgs += '--dart-define=YOMIPALETTE_BILLING_QA=true'
        Write-Host 'Building INTERNAL TEST ONLY AAB (sample ads + QA Billing).'
    } else {
        # An ordinary Play release must not grant entitlements without a backend.
        if ([string]::IsNullOrWhiteSpace($PurchaseVerifierUrl) -or
            $PurchaseVerifierUrl -notmatch '^https://[^/]+') {
            throw 'Production AAB blocked: configure an HTTPS purchase verification backend via -PurchaseVerifierUrl. Use -InternalTestAds only for internal QA.'
        }
        $flutterArgs += "--dart-define=YOMIPALETTE_BILLING_VERIFY_URL=$PurchaseVerifierUrl"
    }
    & flutter @flutterArgs
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
    if ($InternalTestAds) {
        $versionLine = Get-Content (Join-Path $repository 'pubspec.yaml') | Where-Object { $_ -match '^version:\s*\S+' } | Select-Object -First 1
        if ($versionLine -notmatch '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
            throw 'Cannot determine the version from pubspec.yaml.'
        }
        $qaFilename = "YomiPalette-$($Matches[1])-build$($Matches[2])-internal-test.aab"
        $qaBundle = Join-Path $repository "release\$qaFilename"
        New-Item -ItemType Directory -Path (Split-Path $qaBundle) -Force | Out-Null
        Copy-Item -LiteralPath $bundle -Destination $qaBundle -Force
        Write-Host "Signed QA-only AAB: $qaBundle"
        Get-FileHash -Algorithm SHA256 -LiteralPath $qaBundle
    }
    Write-Host 'Nothing was uploaded. Play App Signing and Play Console review are separate steps.'
} finally {
    $env:ORG_GRADLE_PROJECT_PLAY_RELEASE = $oldPlayRelease
    $env:ORG_GRADLE_PROJECT_PLAY_SIGNING_PROPERTIES = $oldProperties
    Pop-Location
}
