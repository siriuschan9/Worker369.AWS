using namespace Worker369.AWS

Add-Type -Path $PSScriptRoot/ResourceString.cs

# Define an Variable for Default String Format.
[ResourceStringFormat]$ResourceStringPreference = [ResourceStringFormat]::IdAndName
$ResourceStringPreference | Out-Null