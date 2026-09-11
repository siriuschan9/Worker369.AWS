function Show-Fleet
{
    [CmdletBinding()]
    [Alias('fleet_show')]
    param (
        [Parameter(Position = 0)]
        [ValidateSet('Default')]
        [string]
        $View = 'Default',

        [Amazon.SimpleSystemsManagement.Model.InstanceInformationStringFilter[]]
        $Filter,

        [ValidateSet('PlatformType', 'PingStatus', $null)]
        [string]
        $GroupBy = 'PlatformType',

        [Int[]]
        $Sort,

        [Int[]]
        $Exclude,

        [switch]
        $PlainText,

        [switch]
        $NoRowSeparator
    )

    # Use snake_case.
    $_view             = $View
    $_filter           = $Filter
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    # For easy pick-up later.
    $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name

    $_view_definition = @{
        Default = @(
            'InstanceId', 'ComputerName', 'PlatformName', 'PlatformVersion', 'PingStatus', 'AgentVersion'
        )
    }

    $_select_definition = @{
        InstanceId = {
            $_.InstanceId
        }
        ComputerName = {
            $_.ComputerName
        }
        PlatformName = {
            $_.PlatformName
        }
        PlatformVersion = {
            $_.PlatformVersion
        }
        PlatformType = {
            $_.PlatformType
        }
        PingStatus = {
            $_ping_status = $_.PingStatus
            New-Checkbox -PlainText:$_plain_text -Description $_ping_status $($_ping_status -eq 'Online')
        }
        AgentVersion = {
            $_is_latest = $_.IsLatestVersion
            $_agent_version = $_.AgentVersion
            New-Checkbox -PlainText:$_plain_text -Description $_agent_version $_is_latest
        }
    }

    try {
        Write-Message -Progress $_cmdlet_name 'Retrieving fleet.'
        $_fleet = Get-SSMInstanceInformation -Verbose:$false -Filter $_filter
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_) 
    }

    # Apply default sort order.
    if (
        $_view -eq 'Default' -and
        $_group_by -eq 'PlatformType' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(2, 1) # => Sort by ComputerName, InstanceId
    }

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             $_view `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    # Generate output after sorting and exclusion.
    $_output = $_fleet | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column `
            -AlignRight PingStatus, AgentVersion `
            -GroupBy $_group_by `
            -PlainText:$_plain_text `
            -NoRowSeparator:$_no_row_separator
    }
}