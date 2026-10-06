function Show-SsmCommand
{
    [CmdletBinding()]
    [Alias('ssm_cmd_show')]
    param (
        #[Parameter()]
        #[ValidatePattern('^i-([0-9a-f]{8}|[0-9a-f]{17})$')]
        #[string]
        #$InstanceId,

        [Parameter(Position = 0)]
        [ValidateSet('Complete', 'Executing')]
        $ExecutionStage = 'Executing',

        [int]
        [ValidateRange(1, 10000)]
        $First,

        [Parameter(Position = 1)]
        [ValidateSet('Default')]
        [string]
        $View = 'Default',

        [Amazon.SimpleSystemsManagement.Model.CommandFilter[]]
        $Filter,

        [ValidateSet('ExecutionStage', 'Status', 'DocumentName', $null)]
        [string]
        $GroupBy = 'ExecutionStage',

        [int[]]
        $Sort,

        [int[]]
        $Exclude,

        [switch]
        $PlainText,

        [switch]
        $NoRowSeparator
    )

    # Use snake_case.
    $_execution_stage  = $ExecutionStage
    $_first            = $First
    $_view             = $View
    $_filter           = $Filter
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    # For easy pick-up later.
    $_cmdlet_name       = $PSCmdlet.MyInvocation.MyCommand.Name
    $_no_auto_iteration = $global:NoAutoIteration ? ($global:NoAutoIteration['RunCommand'] ?? $true) : $true

    $_view_definition = @{
        Default = @(
            'Status', 'CommandId', 'DocumentName', 'RequestedDateTime', 'Targets', 'Completed', 'Error'
        )
    }

    $_select_definition = @{
        CommandId = {
            $_.CommandId
        }
        Completed = {
            New-NumberInfo -FormatSettings $_num_style $_.CompletedCount
        }
        DocumentName = {
            $_.DocumentName
        }
        Error = {
            New-NumberInfo -FormatSettings $_num_style $_.ErrorCount
        }
        ExecutionStage = {
            $_.Status -in @('InProgress', 'Pending') ? 'Executing' : 'Complete'
        }
        RequestedDateTime = {
            $_.RequestedDateTime
        }
        Status = {
            $_status = $_.Status
            $_checked = $_status -eq 'Success'
            New-Checkbox -PlainText:$_plain_text -Description $_status $_checked
        }
        Targets = {
            New-NumberInfo -FormatSettings $_num_style $_.TargetCount
        }
    }

    # Definition to stream output lazily.
    $_stream = {
        $_next_token = $null
        do{
            Write-Message -Progress $_cmdlet_name 'Fetching Run Commands.'
            $_response = Get-SSMCommand -Verbose:$false `
                -Select * `
                -Filter $_filter `
                -NextToken $_next_token `
                -NoAutoIteration:$_no_auto_iteration

            # Generate output after sorting and exclusion.
            $_output = $_response.Commands `
                | Select-Object $_select_list `
                | Sort-Object   $_sort_list `
                | Select-Object $_project_list

            # Print out the output.
            if ($global:EnableHtmlOutput) {
                $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
            }
            else {
                $_output | Format-Column `
                    -AlignLeft Status `
                    -GroupBy $_group_by `
                    -PlainText:$_plain_text `
                    -NoRowSeparator:$_no_row_separator
            }
            if ($_response.Commands.Count -eq 0 -or -not ($_next_token = $_response.NextToken)) { break }

            Write-Host 'There are more results. Press Enter to Continue. Press Esc to Stop.'

            do {
                $_key_info = [Console]::ReadKey($true) # true means do not intercept
            } until ($_key_info.Key -in @('Enter', 'Escape'))

            if ($_key_info.Key -eq 'Escape') {break}

        } while ($true)
    }

    # Definition to buffer results before printing.
    $_buffer = {
        Write-Message -Progress $_cmdlet_name 'Fetching Run Commands.'
        $_output = Get-SSMCommand -Verbose:$false -Filter $_filter | Select-Object -First $_first `
            | Select-Object $_select_list `
            | Sort-Object   $_sort_list `
            | Select-Object $_project_list

        # Print out the output.
        if ($global:EnableHtmlOutput) {
            $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
        }
        else {
            $_output | Format-Column `
                -AlignLeft Status `
                -GroupBy $_group_by `
                -PlainText:$_plain_text `
                -NoRowSeparator:$_no_row_separator
        }
    }

    # Apply default sort order.
    if (-not $PSBoundParameters.Keys.Contains('Exclude') -and-not $PSBoundParameters.Keys.Contains('Sort')) {
        $_sort = @(-4) # => Sort by RequestDateTime
    }

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             $_view `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    # A number style that display dash for zero.
    $_num_style = [Worker369.Utility.NumberInfoSettings]::Make()
    if ($_plain_text) {
        $_num_style.Format.Unscaled = '#,###;#,###;-'          # undimmed dash
    }
    else {
        $_num_style.Format.Unscaled = "#,###;#,###;`e[2m-`e[0m" # dimmed dash
    }

    $_filter = $_filter + [Amazon.SimpleSystemsManagement.Model.CommandFilter]@{
        Key   = 'ExecutionStage'
        Value = $_execution_stage
    }

    $_mode = $PSBoundParameters.ContainsKey('First') ? 'buffer' :  'stream'

    if ($_execution_stage -eq 'Executing') {$_mode = 'buffer'}

    try {
        switch ($_mode)
        {
            'buffer' {& $_buffer}
            'stream' {& $_stream}
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }
}