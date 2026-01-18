using namespace Amazon.CloudFormation

function Show-Stack
{
    [CmdletBinding()]
    [Alias('stack_show')]
    param (
        [ValidateSet('Status', 'Export')]
        [string]
        $View = 'Status',

        [ValidateSet('State', 'StackStatus', 'DriftStatus')]
        [string]
        $GroupBy = 'State',

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
    #$_param_set   = $PSCmdlet.ParameterSetName
    #$_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name

    # Use snake_case.
    $_view             = $View
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    $_select_definition = @{
        DriftStatus = {
            $_is_in_sync = $_.DriftInformation.StackDriftStatus -eq 'IN_SYNC'

            New-Checkbox -PlainText:$_plain_text -Description $_.DriftInformation.StackDriftStatus $_is_in_sync
        }
        DriftUpdatedOn = {
            # Time here is in UTC, Console is using Local Time.
            $_.DriftInformation.LastCheckTimestamp
        }
        State = {
            switch -Regex ($_.StackStatus)
            {
                '^[_A-Z]+COMPLETE$'    { 'Active' }
                '^[_A-Z]+IN_PROGRESS$' { 'In-Progress'}
                '^[_A-Z]+FAILED$'      { 'Failed'}
                '^DELETE_COMPLETE$'    { 'Deleted'}
            }
        }
        StackName = {
            $_.StackName
        }
        StackStatus = {
            $_is_complete = $_.StackStatus -like '*COMPLETE'

            New-Checkbox -PlainText:$_plain_text -Description $_.StackStatus $_is_complete
        }
        StatusUpdatedOn = {
            # Time here is in UTC, Console is using Local Time.
            @($_.CreationTime, $_.DeletionTime, $_.LastUpdatedTime) |
                Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
        }
        Description = {
            $_.Description
        }
    }

    $_view_definition = @{
        Status = @(
            'State', 'StackName', 'StackStatus', 'StatusUpdatedOn', 'DriftStatus', 'DriftUpdatedOn', 'Description'
        )
    }

    try {
        $_stack_list = Get-CFNStack -Verbose:$false
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught error.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Apply default sort order.
    if ($_group_by -eq 'State' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(1) # => Sort by StackName
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
    $_output = $_stack_list | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column `
            -GroupBy $_group_by StackStatus, DriftStatus, StatusUpdatedOn, DriftUpdatedOn `
            -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
    }
}
<#
Capabilities                : {CAPABILITY_NAMED_IAM}
ChangeSetId                 :
CreationTime                : 2025-10-23 09:57:31 AM
DeletionMode                :
DeletionTime                :
Description                 : SES Consumer Assume Role Permission
DetailedStatus              :
DisableRollback             : False
DriftInformation            : Amazon.CloudFormation.Model.StackDriftInformation
EnableTerminationProtection : False
LastUpdatedTime             :
NotificationARNs            :
Outputs                     : {PolicyArn}
Parameters                  : {PolicyDescription, PolicyName}
ParentId                    :
RetainExceptOnCreate        :
RoleARN                     :
RollbackConfiguration       : Amazon.CloudFormation.Model.RollbackConfiguration
RootId                      :
StackId                     : arn:aws:cloudformation:ap-southeast-1:051826723662:stack/StackSet-iam-policy-ses-consumer-assume-role-34d34a9f-59c8-4d22-8e46-824f789981a9/b10f4930-aff6-11f0-a755-064fddb24919
StackName                   : StackSet-iam-policy-ses-consumer-assume-role-34d34a9f-59c8-4d22-8e46-824f789981a9
StackStatus                 : CREATE_COMPLETE
StackStatusReason           :
Tags                        :
TimeoutInMinutes            :
#>