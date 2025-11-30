function Show-Lambda
{
    [Alias('func_show')]
    [CmdletBinding(DefaultParameterSetName = 'None')]
    param (
        [parameter(Position = 0)]
        [ValidateSet('Default', 'Logging')]
        [string]
        $View = 'Default',

        [ValidateSet('Runtime', 'Type', 'Role', 'LogFormat', $null)]
        [string]
        $GroupBy = 'Runtime',

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
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    $_select_definition = @{
        ApplicationLogLevel = {
            $_.LoggingConfig.ApplicationLogLevel
        }
        Architectures = {
            $_.Architectures -join "`n"
        }
        LastModified = {
            [DateTime]::Parse($_.LastModified)
        }
        LogFormat = {
            $_.LoggingConfig.LogFormat
        }
        LogGroup = {
            $_.LoggingConfig.LogGroup
        }
        Memory = {
            New-NumberInfo $_.MemorySize
        }
        Name = {
            $_.FunctionName
        }
        Role = {
            ($_.Role -split '/')[-1]
        }
        Runtime = {
            $_.Runtime
        }
        Size = {
            New-ByteInfo -MetricSystem SI $_.CodeSize
        }
        SystemLogLevel = {
            $_.LoggingConfig.SystemLogLevel
        }
        Timeout = {
            $_.Timeout
        }
        Type = {
            $_.PackageType
        }
    }

    $_view_definition = @{
        Default = @(
            'Name', 'Architectures', 'Runtime', 'Type', 'Role', 'Memory', 'Timeout', 'Size', 'LastModified'
        )
        Logging = @(
            'Name', 'SystemLogLevel', 'ApplicationLogLevel', 'LogFormat', 'LogGroup'
        )
    }

    # Apply default sort order.
    if (
        $_group_by -eq 'Runtime' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(1) # => Sort by FunctionName
    }

    try {
        $_lambda_list = Get-LMFunctionList -Verbose:$false
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    if (-not $_lambda_list) { return }

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             $_view `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    # Print out the summary table.
    $_lambda_list                |
    Select-Object $_select_list  |
    Sort-Object   $_sort_list    |
    Select-Object $_project_list |
    Format-Column -GroupBy $_group_by -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
}