using namespace Worker369.Utility

function Show-IacScanDetail
{
    [CmdletBinding()]
    [Alias('iac_scan_detail')]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]
        $ResourceScanId,

        [Parameter()]
        [string]
        $ResourceTypePrefix,

        [ValidateSet('ResourceType', $null)]
        [string]
        $GroupBy = 'ResourceType',

        [Parameter()]
        [Int[]]
        $Sort = @(1, 2),

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
    $_type_prefix      = $ResourceTypePrefix
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    try {
        $_resource_list = [string]::IsNullOrEmpty($_type_prefix) `
            ? (Get-CFNResourceScanResource -Verbose:$false $_scan_id)
            : (Get-CFNResourceScanResource -Verbose:$false $_scan_id -ResourceTypePrefix $_type_prefix)
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
        Default = @('ResourceType', 'ManagedByStack', 'ResourceIdentifier')
    }

    $_select_definition = @{
        ResourceType = {
            $_.ResourceType
        }
        ManagedByStack = {
            New-Checkbox -PlainText:$_plain_text $_.ManagedByStack
        }
        ResourceIdentifier = {
            foreach ($_item in $_.ResourceIdentifier.GetEnumerator())
            {
                "{0}: {1}" -f $_item.Key, $_item.Value
            }
        }
    }

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             'Default' `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    # Generate output after sorting and exclusion.
    $_output = $_resource_list | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column `
            -GroupBy $_group_by -AlignLeft ManagedByStack `
            -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
    }
}