function Show-IamRole
{
    [Alias('role_show')]
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [ValidateSet('General', 'Usage', 'Identifier')]
        [string]
        $View = 'General',

        [ValidateSet('Path', $null)]
        [string]
        $GroupBy = 'Path',

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
    $_view               = $View
    $_group_by           = $GroupBy
    $_sort               = $Sort
    $_exclude            = $Exclude
    $_plain_text         = $PlainText.IsPresent
    $_no_row_separator   = $NoRowSeparator.IsPresent

    $_select_definition = @{
        Path = {
            $_.Path
        }
        RoleArn = {
            $_.Arn.Trim()
        }
        RoleName = {
            $_.RoleName
        }
        RoleId = {
            $_.RoleId
        }
        CreateDate = {
            $_.CreateDate
        }
        Description = {
            $_description  = $_.Description
            $_words        = $_description -split '\s+'
            $_max_width    = 44
            $_current_line = ''
            foreach ($_word in $_words)
            {
                # Add first word regardless of word length. Add subsequent words till line approaches max_width
                if ($_current_line -eq '' -or $_current_line.Length + $_word.Length -le $_max_width) {
                    $_current_line += $_word + ' '
                }
                else {
                    $_current_line.TrimEnd() # Remove last space from current_line.
                    $_current_line = ''      # Print current_line.
                }
            }
            # Print last line.
            if ($_current_line.Length -gt 0) {
                $_current_line
            }
        }
        MaxSessionDuration = {
            $_.MaxSessionDuration
        }
        LastUsedDate = {
            $_.RoleLastUsed.LastUsedDate
        }
        LastUsedRegion = {
            $_.RoleLastUsed.Region
        }
        LastUsedSince = {
            if ($_last_used_date = $_.RoleLastUsed.LastUsedDate) {
                $_timespan = $_now - $_last_used_date
                $_timespan.Days -eq 1 `
                    ? "$($_timespan.Days) day ago"
                    : $_timespan.Days -gt 1 `
                        ? "$($_timespan.Days) days ago"
                        : $_timespan.Hours -eq 1 `
                            ? "$($_timespan.Hours) hour ago"
                            : $_timespan.Hours -gt 1 `
                                ? "$($_timespan.Hours) hours ago"
                                : $_timespan.Minutes -eq 1 `
                                    ? "$($_timespan.Minutes) minute ago"
                                    : $_timespan.Minutes -gt 1 `
                                        ? "$($_timespan.Minutes) minutes ago"
                                        : 'Just now'
            }
        }
        PermissionBoundary = {
            $_.PermissionBoundary
        }
    }

    $_view_definition = @{
        'General' = @(
            'Path', 'RoleName', 'CreateDate', 'Description'
        )
        'Identifier' = @(
            'RoleId', 'RoleArn'
        )
        'Usage' = @(
            'Path', 'RoleName', 'MaxSessionDuration', 'LastUsedSince', 'LastUsedDate', 'LastUsedRegion'
        )
    }

    try {
        $_role_list = Get-IAMRoleList -Verbose:$false

        if ($_view -eq 'Usage') {
            foreach ($_role in $_role_list) {
                $_role.RoleLastUsed = (Get-IAMRole -Verbose:$false -Select Role.RoleLastUsed $_role.RoleName)
            }
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught error.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # If there are not roles to show, exit early.
    if (-not $_role_list) { return }

    # Apply default sort order.
    if ($_group_by -eq 'Path' -and
        $_view -eq 'General' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(1) # => Sort by RoleName
    }

    # Lock the time now. Use this locked time to compute LastUsedSince.
    $_now = (Get-Date).ToUniversalTime()

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             $_view `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    # Generate output after sorting and exclusion.
    $_output = $_role_list | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column `
            -GroupBy $_group_by `
            -AlignRight LastUsedSince `
            -PlainText:$_plain_text `
            -NoRowSeparator:$_no_row_separator
    }
}