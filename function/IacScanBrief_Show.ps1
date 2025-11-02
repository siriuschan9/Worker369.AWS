using namespace Worker369.Utility

function Show-IacScanBrief
{
    [CmdletBinding()]
    [Alias('iac_scan_brief')]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]
        $ResourceScanId,

        [Parameter()]
        [Int[]]
        $Sort = @(1),

        [Parameter()]
        [Int[]]
        $Exclude,

        [Parameter()]
        [switch]
        $PlainText,

        [Parameter()]
        [switch]
        $NoRowSeparator
    )

    # Use snake case.
    $_scan_id          = $ResourceScanId
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    try {
        $_resource_list = Get-CFNResourceScanResource -Verbose:$false $_scan_id
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Exit early if there are not resources to show.
    if(-not $_resource_list) { return }

    # Display a dimmed dash for zero.
    $_style_number_settings = [NumberInfoSettings]::Make()
    $_style_number_settings.Format.Unscaled = "#,###;#,###;`e[2m-`e[0m"

    # Display an unstyled dash for zero.
    $_plain_number_settings = [NumberInfoSettings]::Make()
    $_plain_number_settings.Format.Unscaled = '#,###;#,###;-'

    $_view_definition = @{
        Default = @('ResourceType', 'Scanned', 'Unmanaged', 'Managed')
    }

    $_select_definition = @{
        ResourceType = {
            $_.Name
        }
        Scanned = {
            $_num_scanned  = $_.Count
            $_num_settings = $_plain_text ? $_plain_number_settings : $_style_number_settings

            New-NumberInfo -FormatSettings $_num_settings $_num_scanned
        }
        Managed = {
            $_num_managed  = ($_.Group | Where-Object ManagedByStack | Measure-Object).Count
            $_num_settings = $_plain_text ? $_plain_number_settings : $_style_number_settings

            New-NumberInfo -FormatSettings $_num_settings $_num_managed
        }
        Unmanaged = {
            $_num_unmanaged = ($_.Group | Where-Object -Not ManagedByStack | Measure-Object).Count
            $_num_settings  = $_plain_text ? $_plain_number_settings : $_style_number_settings

            New-NumberInfo -FormatSettings $_num_settings $_num_unmanaged
        }
    }

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             'Default' `
        -Sort             $_sort `
        -Exclude          $_exclude

    $_resource_list              |
    Group-Object  ResourceType   |
    Select-Object $_select_list  |
    Sort-Object   $_sort_list    |
    Select-Object $_project_list |
    Format-Column -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
}