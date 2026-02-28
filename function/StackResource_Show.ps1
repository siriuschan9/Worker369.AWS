function Show-StackResource
{
    [CmdletBinding()]
    [Alias('stack_resource_show')]
    param (
        [Parameter(Position = 0, Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]
        $StackName,

        [ValidateSet('Default')]
        [string]
        $View = 'Default',

        [ValidateSet('StackName')]
        [string]
        $GroupBy = 'StackName',

        [Int[]]
        $Sort,

        [Int[]]
        $Exclude,

        [switch]
        $PlainText,

        [switch]
        $NoRowSeparator
    )

    BEGIN
    {
        # For easy pick up.
        # $_param_set = $PSCmdlet.ParameterSetName

        $_select_definition = @{
            ResourceType = {
                $_.ResourceType
            }
            LogicalResourceId = {
                $_.LogicalResourceId
            }
            PhysicalResourceId = {
                $_.PhysicalResourceId
            }
            ResourceStatus = {
                $_resource_status = $_.ResourceStatus
                $_is_complete     = $_resource_status -like '*COMPLETE'

                New-Checkbox -PlainText:$_plain_text -Description $_resource_status $_is_complete
            }
            DriftStatus = {
                $_drift_status = $_.DriftInformation.StackResourceDriftStatus
                $_is_in_sync   = $_drift_status -eq 'IN_SYNC'
                New-Checkbox -PlainText:$_plain_text -Description $_drift_status $_is_in_sync
            }
            StackName = {
                $_.StackName
            }
        }

        $_view_definition = @{
            'Default' = @(
                'StackName', 'ResourceType', 'LogicalResourceId', 'PhysicalResourceId', 'ResourceStatus', 'DriftStatus'
            )
        }

        $_resource_list = [System.Collections.Generic.List[object]]::new()
    }

    PROCESS
    {
        # Use snake_case.
        $_stack_name       = $StackName
        $_view             = $View
        $_group_by         = $GroupBy
        $_sort             = $Sort
        $_exclude          = $Exclude
        $_plain_text       = $PlainText.IsPresent
        $_no_row_separator = $NoRowSeparator.IsPresent

        try {
            $_resource_list.AddRange(
                @(Get-CFNStackResourceList -Verbose:$false $_stack_name)
            )
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }
    }

    END
    {
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
            $_resource_list | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

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
}