$_cmd_lookup = @{

    PrefixListId = @(
        'Resolve-PrefixList'
    )

    PrefixListName = @(
        'Resolve-PrefixList'
    )

}

# PrefixListId
Register-ArgumentCompleter -ParameterName 'PrefixListId' -CommandName $_cmd_lookup['PrefixListId'] -ScriptBlock {
    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

        $_dim   = [System.Management.Automation.PSStyle]::Instance.Dim
        $_reset = [System.Management.Automation.PSStyle]::Instance.Reset

        Get-EC2ManagedPrefixList -Verbose:$false -Filter @{
            Name   = 'prefix-list-id'
            Values = "$_word_to_complete*"
        } |
        Sort-Object PrefixListName | ForEach-Object {

            $_display_item = '{0,-20} {1}' -f $_.PrefixListId, "$_dim| $($_.PrefixListName)$_reset"

            [System.Management.Automation.CompletionResult]::new(
                $_.PrefixListId,  # completionText
                $_display_item,   # listItemText
                'ParameterValue', # resultType
                $_display_item    # toolTip
            )
    }
}

# PrefixListName
Register-ArgumentCompleter -ParameterName 'PrefixListName' -CommandName $_cmd_lookup['PrefixListName'] -ScriptBlock {
    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    Get-EC2ManagedPrefixList -Select PrefixLists.PrefixListName -Verbose:$false -Filter @{
        Name   = 'prefix-list-name'
        Values = "$_word_to_complete*"
    } |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}