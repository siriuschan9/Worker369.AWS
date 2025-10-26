$_cmd_lookup = @{
    NetworkAclId = @(
        'Remove-NetworkAcl',
        'Rename-NetworkAcl'

    )
    NetworkAclName = @(
        'Remove-NetworkAcl',
        'Rename-NetworkAcl'
    )
}

# NetworkAclId
Register-ArgumentCompleter -ParameterName 'NetworkAclId' -CommandName $_cmd_lookup['NetworkAclId'] -ScriptBlock {
    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_acl_list = Get-EC2NetworkAcl -Verbose:$false -Filter @{
        Name   = 'network-acl-id'
        Values = "$_word_to_complete*"
    }

    if (-not $_acl_list) { return }

    $_align = $_acl_list.NetworkAclId.Length | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    $_acl_list | Get-HintItem -IdPropertyName 'NetworkAclId' -TagPropertyName 'Tags' -Align $_align |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_.ResourceId,    # completionText
            $_ ,              # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# NetworkAclName
Register-ArgumentCompleter -ParameterName 'NetworkAclName' -CommandName $_cmd_lookup['NetworkAclName'] -ScriptBlock {
    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    Get-EC2NetworkAcl -Verbose:$false -Filter @{
        Name   = 'tag:Name'
        Values = "$_word_to_complete*"
    } |
    Select-Object -ExpandProperty Tags | Where-Object Key -eq 'Name' |
    Select-Object -Unique -ExpandProperty Value | Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}