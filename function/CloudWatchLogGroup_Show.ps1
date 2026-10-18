function Show-CloudWatchLogGroup
{
    [CmdletBinding()]
    [Alias('cwlg_show')]
    param (
        [string]
        $LogGroupNamePattern = '*',

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

        [ScriptBlock]
        $Where = {$true},

        [switch]
        $PassThru,

        [switch]
        $PlainText,

        [switch]
        $NoRowSeparator
    )

    # Use snake_case.
    $_lg_name_pattern  = $LogGroupNamePattern
    $_view             = $View
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_where            = $Where
    $_pass_thru        = $PassThru.IsPresent
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name

    $_view_definition = @{
        Subscription = @(
            'LogGroupName', 'FilterName', 'FilterPattern', 'DestinationArn', 'LastIngestionTime'
        )
    }

    $_select_definition = @{
        LogGroupName = {
            $_.LogGroupName
        }
        FilterName = {
            $_subscription_lookup[$_.LogGroupName] | Select-Object -ExpandProperty FilterName
        }
        FilterPattern = {
            $_subscription_lookup[$_.LogGroupName] | Select-Object -ExpandProperty FilterPattern
        }
        DestinationArn = {
            $_subscription_lookup[$_.LogGroupName] | Select-Object -ExpandProperty DestinationArn
        }
        LastIngestionTime = {
            $_last_ingestion_time_lookup[$_.LogGroupName]
        }
    }

    try {
        Write-Message -Progress $_cmdlet_name 'Fetching Log Groups.'
        $_log_group_list = `
            Get-CWLLogGroup -Verbose:$false -LogGroupNamePattern $_lg_name_pattern |
            Where-Object {$_.LogGroupClass -eq 'STANDARD'}

        Write-Message -Progress $_cmdlet_name 'Fetching Subscription Filters.'
        $_subscription_lookup = @{}

        foreach ($_log_group in $_log_group_list)
        {
            while ($true)
            {
                try {
                    $_subscription_lookup[$_log_group.LogGroupName] = `
                    Get-CWLSubscriptionFilter -LogGroupName $_log_group.LogGroupName | `
                    Sort-Object FilterName | `
                    Select-Object FilterName, FilterPattern, DestinationArn

                    break
                }
                catch {
                    $_is_throttle = `
                        $_.Exception.Message -match 'Throttle|Rate exceeded|TooManyRequests|RequestLimitExceeded'
                    if ($_is_throttle) {
                        Write-Host $_.Exception.Message
                        Start-Sleep -Seconds 1.5
                    } else {
                        Write-Host $_.Exception.Message
                        throw
                    }
                }
            }
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
    $_output = $_log_group_list `
        | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list | Where-Object $_where

    # Print out the output. If -PassThru, put the objects in the pipeline.
    if ($_pass_thru) {
        $_output
    } else {
        if ($global:EnableHtmlOutput) {
            $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
        } else {
            $_output | Format-Column -GroupBy $_group_by -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
        }
    }
}