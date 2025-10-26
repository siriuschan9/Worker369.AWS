$_cmd_lookup = @{

    GroupId = @(
        'Rename-SecurityGroup', 'Remove-SecurityGroup', 'Clear-SecurityGroup',
        'Set-DefaultSecurityGroup',
        'Show-SecurityGroupRule'

    )
    TagName = @(
        'Rename-SecurityGroup', 'Remove-SecurityGroup', 'Clear-SecurityGroup',
        'Set-DefaultSecurityGroup',
        'Show-SecurityGroupRule'
    )
}

# SecurityGroupId
Register-ArgumentCompleter -ParameterName 'GroupId' -CommandName $_cmd_lookup['GroupId'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_sg_list = Get-EC2SecurityGroup -Verbose:$false -Filter @{
        Name   = 'group-id'
        Values = "$_word_to_complete*"
    }

    if (-not $_sg_list) { return }

    $_align = $_sg_list.SecurityGroupId.Length | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    $_sg_list | Get-HintItem -IdPropertyName 'GroupId' -TagPropertyName 'Tags' -Align $_align |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_.ResourceId,    # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# SecurityGroupName
Register-ArgumentCompleter `
    -ParameterName 'TagName' -CommandName $_cmd_lookup['TagName'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    Get-EC2SecurityGroup -Verbose:$false -Filter @{
        Name = 'tag:Name'
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