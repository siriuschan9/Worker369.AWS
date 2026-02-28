function Show-KmsKey
{
    [Alias('kms_show')]
    [CmdletBinding()]
    param (

        [Parameter()]
        [ValidateSet('ALL', 'AWS', 'CUSTOMER')]
        [string]
        $KeyManager = 'ALL',

        [ValidateSet('Default')]
        [string]
        $View = 'Default',

        [ValidateSet('KeyManager', 'KeyType', 'KeyState', 'KeyUsage', 'Regionality')]
        [string]
        $GroupBy = 'KeyManager',

        [Int[]]
        $Sort,

        [Int[]]
        $Exclude,

        [switch]
        $PlainText,

        [switch]
        $NoRowSeparator
    )

    # For easy pickup.
    $_dim       = [System.Management.Automation.PSStyle]::Instance.Dim
    $_reset     = [System.Management.Automation.PSStyle]::Instance.Reset

    # Use snake_case.
    $_view               = $View
    $_group_by           = $GroupBy
    $_sort               = $Sort
    $_exclude            = $Exclude
    $_plain_text         = $PlainText.IsPresent
    $_no_row_separator   = $NoRowSeparator.IsPresent
    $_key_manager_filter = switch ($KeyManager)
    {
        'ALL'      { { $true } }
        'AWS'      { { $_.KeyManager -eq 'AWS' } }
        'CUSTOMER' { { $_.KeyManager -eq 'CUSTOMER' } }
        default    { { $true } }
    }

    $_select_definition = @{
        KeyManager = {
            $_key_manager = $_.KeyManager
            $_enabled     = $_enabled_lookup[$_.KeyId]

            $_enabled -or $_plain_text -or $_group_by -eq 'KeyManager' `
                ? "$($_key_manager)"
                : "$($_dim)$($_key_manager)$($_reset)"
        }
        KeyId = {
            $_key_id  = $_.KeyId
            $_enabled = $_enabled_lookup[$_key_id]

            $_enabled -or $_plain_text  `
                ? "$($_key_id)"
                : "$($_dim)$($_key_id)$($_reset)"
        }
        KeyState = {
            $_key_state = $_.KeyState
            $_checked   = $_key_state -eq 'Enabled'

            New-Checkbox -PlainText:$_plain_text -Description $_key_state $_checked
        }
        KeyType = {
            $_key_type = $_.KeySpec -eq 'SYMMETRIC_DEFAULT' ? 'Symmetric' : 'Asymmetric'
            $_enabled  = $_enabled_lookup[$_.KeyId]

            $_enabled -or $_plain_text -or $_group_by -eq 'KeyType' `
                ? "$($_key_type)"
                : "$($_dim)$($_key_type)$($_reset)"
        }
        KeySpec = {
            $_key_spec = $_.KeySpec
            $_enabled  = $_enabled_lookup[$_.KeyId]

            $_enabled -or $_plain_text `
                ? "$($_key_spec)"
                : "$($_dim)$($_key_spec)$($_reset)"
        }
        KeyUsage  = {
            $_key_usage = $_.KeyUsage
            $_enabled   = $_enabled_lookup[$_.KeyId]

            $_enabled -or $_plain_text -or $_group_by -eq 'KeyUsage' `
                ? "$($_key_usage)"
                : "$($_dim)$($_key_usage)$($_reset)"
        }
        Regionality = {
            $_regionality = $_.MultiRegion ? 'Multi Region' : 'Single Region'
            $_enabled     = $_enabled_lookup[$_.KeyId]

            $_enabled -or $_plain_text -or $_group_by -eq 'Regionality' `
                ? "$($_regionality)"
                : "$($_dim)$($_regionality)$($_reset)"
        }
        KeyAlias = {
            $_key_alias = $_alias_lookup[$_.KeyId]
            $_enabled   = $_enabled_lookup[$_.KeyId]

            $_map = $_enabled -or $_plain_text `
                ? { "$($_)" }
                : { "$($_dim)$($_)$($_dim)" }
            $_key_alias | ForEach-Object $_map
        }
        CreationDate = {
            $_creation_date = $_.CreationDate
            $_enabled       = $_enabled_lookup[$_.KeyId]

            $_enabled -or $_plain_text `
                ? "$($_creation_date)"
                : "$($_dim)$($_creation_date)$($_reset)"
        }
    }

    $_view_definition = @{
        'Default' = @(
            'KeyManager', 'KeyId', 'KeyState', 'KeyType', 'KeySpec', 'KeyUsage',
            'Regionality', 'KeyAlias', 'CreationDate'
        )
    }

    # Retrieve keys and aliases.
    try {
        $_key_list = Get-KMSKeyList -Verbose:$false | Get-KMSKey -Verbose:$false
        $_alias_list = Get-KMSAliasList -Verbose:$false
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught error.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # If there are no keys to show, exit early.
    if (-not $_key_list) {
        return
    }

    # Create a lookup for aliases.
    $_alias_lookup = @{}
    foreach ($_key in $_key_list)
    {
        $_alias_lookup[$_key.KeyId] = `
            $_alias_list | Where-Object TargetKeyId -eq $_key.KeyId | Select-Object -ExpandProperty AliasName
    }

    # Create a lookup for key status.
    $_enabled_lookup = @{}
    foreach ($_key in $_key_list)
    {
        $_enabled_lookup[$_key.KeyId] = $_key.KeyState -eq 'Enabled'
    }

    # Apply default sort order.
    if ($_group_by -eq 'KeyManager' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(2, 7) # => Sort by KeyState, CreationDate
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
    $_output = $_key_list |
        Select-Object $_select_list |
        Sort-Object $_sort_list |
        Select-Object $_project_list |
        Where-Object $_key_manager_filter

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column `
            -GroupBy $_group_by `
            -AlignLeft KeyState `
            -PlainText:$_plain_text `
            -NoRowSeparator:$_no_row_separator
    }
}