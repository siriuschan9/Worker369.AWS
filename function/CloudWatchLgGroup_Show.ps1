function Show-CloudWatchLogGroup
{
    [CmdletBinding()]
    [Alias('cwlg_show')]
    param (
        [Parameter(Position = 0)]
        [ValidateSet('Default', 'Subscription')]
        [string]
        $View = 'Subscription',

        [ValidateSet($null)]
        [string]
        $GroupBy = $null,

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
    #$_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name

    $_view_definition = @{
        Subscription = @(
            'LogGroupName', 'Subscription', 'LastIngestionTime'
        )
    }

    $_select_definition = @{
        LogGroupName = {
            $_.LogGroupName
        }
        Subscription = {
            $_subscription_lookup[$_.LogGroupName]
        }
        LastIngestionTime = {
            $_last_ingestion_time_lookup[$_.LogGroupName]
        }
    }

    try {
        Write-Message -Progress $_cmdlet_name 'Fetching Log Groups.'
        $_log_group_list = Get-CWLLogGroupList -Verbose:$false | Where-Object {$_.LogGroupClass -eq 'STANDARD'}

        Write-Message -Progress $_cmdlet_name 'Fetching Subscription Filters.'
        $_subscription_lookup = @{}
        foreach ($_log_group in $_log_group_list)
        {
            $_subscription_lookup[$_log_group.LogGroupName] = `
                Get-CWLSubscriptionFilter -LogGroupName $_log_group.LogGroupName | `
                Sort-Object DestinationArn | `
                Select-Object -ExpandProperty DestinationArn
        }

        Write-Message -Progress $_cmdlet_name 'Fetching Log Group Last Ingestion Time.'
        $_last_ingestion_time_lookup = @{}
        foreach ($_log_group in $_log_group_list)
        {
            $_last_ingestion_time_lookup[$_log_group.LogGroupName] = `
                Get-CWLLogStream $_log_group.LogGroupName `
                    -OrderBy LastEventTime `
                    -Descending $true `
                    -NoAutoIteration |
                Sort-Object -Descending LastIngestionTime | Select-Object -First 1 -ExpandProperty LastIngestionTime
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
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
    $_output = $_log_group_list | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column -GroupBy $_group_by -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
    }
}