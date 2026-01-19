function Show-StackDrift
{
    [CmdletBinding()]
    [Alias('stack_drift_show')]
    param (
        [Parameter(Position = 0, Mandatory)]
        [string]
        $StackName,

        [ValidateSet('Default')]
        [string]
        $View = 'Default',

        [ValidateSet('LogicalResourceId')]
        [string]
        $GroupBy = 'LogicalResourceId',

        [Int[]]
        $Sort,

        [Int[]]
        $Exclude,

        [switch]
        $PlainText,

        [switch]
        $NoRowSeparator
    )

    # For easy pick up.
    # $_param_set = $PSCmdlet.ParameterSetName

    $_select_definition = @{
        LogicalResourceId = {
            $_.LogicalResourceId
        }
        PropertyPath = {
            $_.PropertyPath
        }
        DifferenceType = {
            $_.DifferenceType
        }
        ExpectedValue = {
            ($_.ExpectedValue | Out-Json) -split "`n"
        }
        ActualValue = {
            ($_.ActualValue | Out-Json) -split "`n"
        }
    }

    # For easy pick-up.
    $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name

    # Use snake_case.
    $_stack_name       = $StackName
    $_view             = $View
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    $_view_definition = @{
        'Default' = @(
            'LogicalResourceId', 'PropertyPath', 'DifferenceType', 'ExpectedValue', 'ActualValue'
        )
    }

    try {
        $_drifted_resource_list = Get-CFNStackResourceList -Verbose:$false $_stack_name | Where-Object {
            $_.DriftInformation.StackResourceDriftStatus -ne 'IN_SYNC'
        } | ForEach-Object {
            $_logical_resource_id = $_.LogicalResourceId
            Write-Message -Progress $_cmdlet_name "Retrieving stack resource $($_logical_resource_id)."
            Get-CFNStackResourceDrift -Verbose:$false `
                -LogicalResourceId $_.LogicalResourceId $_stack_name |
            Select-Object -ExpandProperty PropertyDifferences | ForEach-Object {
                $_ | Add-Member 'LogicalResourceId' $_logical_resource_id
                $_
            }
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught error.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Exit early if there are no drifted resources.
    if (-not $_drifted_resource_list) {
        return
    }

    # Apply default sort order.
    if ($_group_by -eq 'StackName' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(1, 2) # => Sort by ResourceType, LogicalId
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
    $_output = `
        $_drifted_resource_list | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column `
            -GroupBy $_group_by -AlignLeft ResourceStatus, DriftStatus `
            -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
    }

}