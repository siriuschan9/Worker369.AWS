function Show-IamRole
{
    [Alias('iam_role_show')]
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [ValidateSet('General', 'Usage', 'Identifier', 'Permission')]
        [string]
        $View = 'General',

        [ValidateSet('Path', $null)]
        [string]
        $GroupBy,

        [Int[]]
        $Sort,

        [Int[]]
        $Exclude,

        [scriptblock]
        $Where = {$true},

        [switch]
        $PassThru,

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
    $_where            = $Where
    $_pass_thru        = $PassThru.IsPresent
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name

    $_dash = $_plain_text ? "-" : "$($PSStyle.Dim)-$($PSStyle.Reset)"

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
            $_supplement_info = $_supplement_lookup[$_.RoleId]
            $_supplement_info.RoleLastUsed.LastUsedDate ?? $_dash
        }
        LastUsedRegion = {
            $_supplement_info = $_supplement_lookup[$_.RoleId]
            $_supplement_info.RoleLastUsed.Region ?? $_dash
        }
        LastUsedSince = {
            $_supplement_info = $_supplement_lookup[$_.RoleId]
            $_last_used_date  = $_supplement_info.RoleLastUsed.LastUsedDate
            if ($_last_used_date) {
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
            else { $_dash }
        }
        PermissionsBoundary = {
            $_supplement_info      = $_supplement_lookup[$_.RoleId]
            $_permissions_boundary = $_supplement_info.PermissionsBoundary
            $_permissions_boundary ? ($_permissions_boundary.PermissionsBoundaryArn -split '/')[-1] :$_dash
        }
        Policies = {
            $_supplement_info = $_supplement_lookup[$_.RoleId]

            $_attached_policy_list = $_supplement_info.AttachedManagedPolicies `
                | Where-Object { $null -ne $_ } `
                | ForEach-Object {
                    $_.PolicyArn -like 'arn:aws:iam::aws:policy/*' `
                        ? "[A] $($_.PolicyName)" `
                        : "[C] $($_.PolicyName)"
                }
            $_inline_policy_list = $_supplement_info.RolePolicyList `
                | Where-Object   { $null -ne $_ } `
                | ForEach-Object {"[I] $($_.PolicyName)" }

            @($_attached_policy_list) + @($_inline_policy_list) | Sort-Object
        }
    }

    $_view_definition = @{
        'General' = @(
            'RoleName', 'CreateDate', 'Description'
        )
        'Identifier' = @(
            'RoleId', 'RoleArn'
        )
        'Permission' = @(
            'RoleName', 'Policies', 'PermissionsBoundary'
        )
        'Usage' = @(
            'RoleName', 'MaxSessionDuration', 'LastUsedSince', 'LastUsedDate', 'LastUsedRegion'
        )
    }

    try {
        Write-Message -Progress $_cmdlet_name 'Fetching IAM role data.'
        $_role_list = Get-IAMRoleList -Verbose:$false

        Write-Message -Progress $_cmdlet_name 'Fetching supplement data.'
        $_supplement_lookup =
            Get-IAMAccountAuthorizationDetail -Verbose:$false -Filter 'Role' |
            Select-Object -ExpandProperty RoleDetailList |
            Group-Object -AsHashTable RoleId
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
    if ($_null -eq $_group_by -and
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
    $_output = $_role_list `
        | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list | Where-Object $_where

    # If -PassThru, put the objects in the pipeline.
    if ($_pass_thru) {$_output; return }

    # If EnableHtmlOutput is set, output html markup.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
        return
    }

    # Print out the output to the terminal.
    $_align_left  = @()
    $_align_right = @('LastUsedSince', 'LastUsedDate', 'LastUsedRegion')
    $_output | Format-Column `
        -AlignLeft $_align_left `
        -AlignRight $_align_right `
        -GroupBy $_group_by `
        -PlainText:$_plain_text `
        -NoRowSeparator:$_no_row_separator
}