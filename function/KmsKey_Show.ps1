function Show-KmsKey
{
    [Alias('kms_show')]
    [CmdletBinding()]
    param (

        [Parameter()]
        [ValidateSet('ALL', 'AWS', 'CUSTOMER')]
        [string]
        $KeyManager = 'CUSTOMER',

        [Parameter(Position = 0)]
        [ValidateSet('General', 'KeySpec', 'Status')]
        [string]
        $View = 'General',

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
        CreationDate = {
            $_.CreationDate
        }
        DeletionDate = {
            $_.DeletionDate
        }
        Description = {
            $_.Description
        }
        KeyAlias = {
            $_alias_lookup[$_.KeyId]
        }
        KeyId = {
            $_.KeyId
        }
        KeyManager = {
            $_.KeyManager
        }
        KeyState = {
            $_key_state = $_.KeyState
            $_checked   = $_key_state -eq 'Enabled'
            New-Checkbox -PlainText:$_plain_text -Description $_key_state $_checked
        }
        KeySpec = {
            $_.KeySpec
        }
        KeyType = {
            $_.KeySpec -eq 'SYMMETRIC_DEFAULT' ? 'Symmetric' : 'Asymmetric'
        }
        KeyUsage  = {
            $_.KeyUsage
        }
        Regionality = {
            $_.MultiRegion ? 'Multi Region' : 'Single Region'
        }
    }

    $_view_definition = @{
        'General' = @(
            'KeyManager', 'KeyState', 'KeyId', 'KeyAlias', 'KeyType', 'Description', 'CreationDate'
        )
        'KeySpec' = @(
            'KeyManager', 'KeyState', 'KeyId', 'KeyAlias', 'KeyType', 'KeySpec', 'KeyUsage', 'Regionality'
        )
        'Status' = @(
            'KeyManager', 'KeyState', 'KeyId', 'KeyAlias', 'CreationDate', 'DeletionDate'
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
        $_view -eq 'General' -and
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