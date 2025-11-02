using namespace System.Collections.Generic
using namespace Amazon.CloudFormation

function Show-StackInstance
{
    [CmdletBinding(DefaultParameterSetName = 'None')]
    [Alias('stackinstance_show')]
    param (
        [ValidateSet('Default')]
        [string]
        $View = 'Default',

        [Amazon.CloudFormation.CallAs]
        $CallAs = 'DELEGATED_ADMIN',

        [Parameter(ParameterSetName = 'StackSetName')]
        [string]
        $StackSetName,

        [ValidateSet('StackSetName')]
        [ValidateSet('StackSetName', 'OuId', 'Account', 'Region', 'DetailedStatus', 'DriftStatus')]
        [string]
        $GroupBy = 'StackSetName',

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
    $_param_set   = $PSCmdlet.ParameterSetName
    $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name

    # Use snake_case.
    $_view             = $View
    $_call_as          = $CallAs
    $_ss_name          = $StackSetName
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    $_select_definition = @{
        Account = {
            $_.Account.Insert(4, '-').Insert(9, '-')
        }
        DetailedStatus = {
            $_succeeded = $_.StackInstanceStatus.DetailedStatus -eq 'SUCCEEDED'

            New-Checkbox -PlainText:$_plain_text -Description $_.StackInstanceStatus.DetailedStatus $_succeeded
        }
        DriftUpdatedOn = {
            $_.LastDriftCheckTimestamp
        }
        DriftStatus = {
            $_is_in_sync = $_.DriftStatus -eq 'IN_SYNC'

            New-Checkbox -PlainText:$_plain_text -Description $_.DriftStatus $_is_in_sync
        }
        OuId = {
            $_.OrganizationalUnitId
        }
        Region = {
            $_.Region
        }
        StackName = {
            $_.StackId `
                -replace 'arn:aws:cloudformation:.+:\d{12}:stack\/' `
                -replace '\/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}'
        }
        StackSetName  = {
            $_.StackSetId -replace ':[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
        }
        StatusReason = {
            $_.StatusReason
        }
    }

    $_view_definition = @{
        Default = @(
            'StackSetName', 'Account', 'Region', 'DetailedStatus', 'DriftStatus', 'DriftUpdatedOn', 'StackName'
        )
    }

    # This try block invokes all AWS APIs necessary to print out the stack instances.
    try {
        # Query StackSets.

        if ($_param_set -eq 'StackSetName') {
            Write-Message -Progress $_cmdlet_name "Querying StackSet '$_ss_name'."
            $_ss_name_list = Get-CFNStackSet -Verbose:$false -CallAs $_call_as $_ss_name -Select StackSet.StackSetName
        }
        else {
            Write-Message -Progress $_cmdlet_name "Querying StackSets."
            $_ss_name_list = Get-CFNStackSetList -Verbose:$false -CallAs $_call_as ACTIVE -Select Summaries.StackSetName
        }

        # If there are no StackSets to work on, exit early.
        if (-not $_ss_name_list) { return }

        # Query Stack Instances.
        $_si_list = $_ss_name_list | ForEach-Object {

            Write-Message -Progress $_cmdlet_name "Querying Stack Instances for StackSet '$_'."
            Get-CFNStackInstanceList -Verbose:$false -CallAs $_call_as -StackSetName $_
        }

        # Close the progress bar
        Write-Message -Progress -Complete $_cmdlet_name "Querying Stack Instances completed."

        # If there are no Stack Instances to show, exit early.
        if (-not $_si_list) { return }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught error.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Apply default sort order.
    if ($_group_by -eq 'StackSetName' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(1, 2) # => Sort by OU, Account, Region
    }

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             $_view `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    # Print out the summary table.
    $_si_list                    |
    Select-Object $_select_list  |  # Initial columns based on selected view.
    Sort-Object   $_sort_list    |  # Sort before exclude.
    Select-Object $_project_list |  # Takes into account exclued columns.
    Format-Column `
        -GroupBy $_group_by `
        -PlainText:$_plain_text `
        -NoRowSeparator:$_no_row_separator `
        -AlignLeft 'DetailedStatus', 'DriftStatus', 'DriftUpdatedOn'
}

<#
'arn:aws:cloudformation:ap-southeast-1:051826723662:stack/StackSet-StateChangeAlert-132f9a7c-8f77-4265-8cd2-5d5c7421208a/e48c02a0-af54-11f0-b533-0a5966eca78d' -replace 'arn:aws:cloudformation:.+:\d{12}:stack\/' -replace '\/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}'

#>