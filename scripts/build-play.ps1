[CmdletBinding()]
param(
    [string]$SigningProperties = (Join-Path $env:USERPROFILE '.android\yomipalette-signing\key.properties'),
    [string]$JavaBin = 'C:\Program Files\Android\Android Studio\jbr\bin',
    [switch]$InternalTestBilling,
    [switch]$EntitlementDiagnostics,
    [ValidateRange(1, 2100000000)]
    [int]$BuildNumber,
    [string]$PurchaseVerifierUrl = $env:YOMIPALETTE_BILLING_VERIFY_URL,
    [string]$IntegrityProjectNumber = $env:YOMIPALETTE_PLAY_INTEGRITY_PROJECT_NUMBER,
    [string]$OfflineGrantPublicKey = $env:YOMIPALETTE_OFFLINE_GRANT_PUBLIC_KEY,
    [string]$OfflineGrantKeyId = $env:YOMIPALETTE_OFFLINE_GRANT_KEY_ID,
    [string]$GoogleWebClientId = $env:YOMIPALETTE_GOOGLE_WEB_CLIENT_ID,
    [string]$TrialVerifierUrl = $env:YOMIPALETTE_TRIAL_VERIFY_URL,
    [string]$TrialGrantPublicKey = $env:YOMIPALETTE_TRIAL_GRANT_PUBLIC_KEY,
    [string]$TrialGrantKeyId = $env:YOMIPALETTE_TRIAL_GRANT_KEY_ID,
    [string]$ReviewAccessUrl = $env:YOMIPALETTE_REVIEW_ACCESS_URL,
    [string]$ReviewGrantPublicKey = $env:YOMIPALETTE_REVIEW_GRANT_PUBLIC_KEY,
    [string]$ReviewGrantKeyId = $env:YOMIPALETTE_REVIEW_GRANT_KEY_ID
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
    if ($PSBoundParameters.ContainsKey('BuildNumber')) {
        $flutterArgs += "--build-number=$BuildNumber"
    }
    if ($InternalTestBilling) {
        # A QA-only AAB: explicitly unverified Billing flow.
        # Never promote it to the production track.
        $flutterArgs += '--dart-define=YOMIPALETTE_BILLING_QA=true'
        Write-Host 'Building INTERNAL TEST ONLY AAB (QA Billing).'
    } else {
        # An ordinary Play release must not grant entitlements without a backend.
        if ([string]::IsNullOrWhiteSpace($PurchaseVerifierUrl) -or
            $PurchaseVerifierUrl -notmatch '^https://[^/]+') {
            throw 'Production AAB blocked: configure an HTTPS purchase verification backend via -PurchaseVerifierUrl. Use -InternalTestBilling only for internal QA.'
        }
        $projectNumber = 0L
        if ($IntegrityProjectNumber -notmatch '^[0-9]+$' -or
            ![long]::TryParse($IntegrityProjectNumber, [ref]$projectNumber) -or $projectNumber -le 0) {
            throw 'Production AAB blocked: configure the linked Google Cloud project number via -IntegrityProjectNumber.'
        }
        $flutterArgs += "--dart-define=YOMIPALETTE_PLAY_INTEGRITY_PROJECT_NUMBER=$projectNumber"
        $flutterArgs += "--dart-define=YOMIPALETTE_BILLING_VERIFY_URL=$PurchaseVerifierUrl"
        if ($OfflineGrantPublicKey -cnotmatch '^[A-Za-z0-9_-]{43}$' -or
            $OfflineGrantKeyId -cnotmatch '^[A-Za-z0-9_-]{1,32}$') {
            throw 'Production AAB blocked: configure the Ed25519 offline grant public key and key ID.'
        }
        $flutterArgs += "--dart-define=YOMIPALETTE_OFFLINE_GRANT_PUBLIC_KEY=$OfflineGrantPublicKey"
        $flutterArgs += "--dart-define=YOMIPALETTE_OFFLINE_GRANT_KEY_ID=$OfflineGrantKeyId"
        # Production trial requires a configured Google OAuth Web client ID.
        if ($GoogleWebClientId -notmatch '^[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$') {
            throw 'Production AAB blocked: configure YOMIPALETTE_GOOGLE_WEB_CLIENT_ID with the Google OAuth Web client ID.'
        }
        $flutterArgs += "--dart-define=YOMIPALETTE_GOOGLE_WEB_CLIENT_ID=$GoogleWebClientId"
        if (![string]::IsNullOrWhiteSpace($TrialVerifierUrl)) {
            # Internal Play track only. Public purchase verification remains
            # on -PurchaseVerifierUrl with the production purchase public key.
            $trialUri = $null
            if (![uri]::TryCreate($TrialVerifierUrl, [UriKind]::Absolute, [ref]$trialUri) -or
                $trialUri.Scheme -ne 'https' -or
                $trialUri.AbsolutePath -ne '/trial' -or
                $trialUri.Query -ne '' -or
                $trialUri.Fragment -ne '' -or
                $trialUri.UserInfo -ne '' -or
                $TrialGrantPublicKey -cnotmatch '^[A-Za-z0-9_-]{43}$' -or
                $TrialGrantKeyId -cnotmatch '^[A-Za-z0-9_-]{1,32}$') {
                throw 'Isolated trial endpoint requires HTTPS /trial, a valid trial Ed25519 public key, and key ID.'
            }
            if ($TrialVerifierUrl -eq $PurchaseVerifierUrl) {
                throw 'Trial verifier must be different from production paid verifier for isolated staging test.'
            }
            $flutterArgs += "--dart-define=YOMIPALETTE_TRIAL_VERIFY_URL=$TrialVerifierUrl"
            $flutterArgs += "--dart-define=YOMIPALETTE_TRIAL_GRANT_PUBLIC_KEY=$TrialGrantPublicKey"
            $flutterArgs += "--dart-define=YOMIPALETTE_TRIAL_GRANT_KEY_ID=$TrialGrantKeyId"
            Write-Warning 'ISOLATED STAGING TRIAL TEST BUNDLE: never promote to a public Play release.'
        }
    }
    if (![string]::IsNullOrWhiteSpace($ReviewAccessUrl)) {
        $reviewUri = $null
        if (![uri]::TryCreate($ReviewAccessUrl, [UriKind]::Absolute, [ref]$reviewUri) -or
            $reviewUri.Scheme -ne 'https' -or $reviewUri.AbsolutePath -ne '/review' -or
            $reviewUri.UserInfo -ne '' -or $reviewUri.Query -ne '' -or $reviewUri.Fragment -ne '') {
            throw 'ReviewAccessUrl must be an HTTPS /review endpoint without credentials, query or fragment.'
        }
        $flutterArgs += "--dart-define=YOMIPALETTE_REVIEW_ACCESS_URL=$ReviewAccessUrl"
        if (![string]::IsNullOrWhiteSpace($ReviewGrantPublicKey) -or
            ![string]::IsNullOrWhiteSpace($ReviewGrantKeyId)) {
            if ($ReviewGrantPublicKey -cnotmatch '^[A-Za-z0-9_-]{43}$' -or
                $ReviewGrantKeyId -cnotmatch '^[A-Za-z0-9_-]{1,32}$') {
                throw 'Configure both review grant public key and key ID.'
            }
            $flutterArgs += "--dart-define=YOMIPALETTE_REVIEW_GRANT_PUBLIC_KEY=$ReviewGrantPublicKey"
            $flutterArgs += "--dart-define=YOMIPALETTE_REVIEW_GRANT_KEY_ID=$ReviewGrantKeyId"
        }
    }
    if ($EntitlementDiagnostics) {
        $flutterArgs += '--dart-define=YOMIPALETTE_ENTITLEMENT_DIAGNOSTICS=true'
        Write-Host 'INTERNAL TEST DIAGNOSTICS ENABLED: do not promote this AAB to public Play.'
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
    if ($InternalTestBilling) {
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
