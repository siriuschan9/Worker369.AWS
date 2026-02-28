$_cmd_lookup = @{

    ExclusionId = @(
        'Edit-VpcBpaExclusion',
        'Remove-VpcBpaExclusion'
    )

    ExclusionMode = @(
        'Edit-VpcBpaExclusion',
        'New-VpcBpaExclusion'
    )
}

# ExclusionId
Register-ArgumentCompleter -ParameterName 'ExclusionId' -CommandName $_cmd_lookup['ExclusionId'] -ScriptBlock {
    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_excl_list = Get-EC2VpcBlockPublicAccessExclusion `
        -Select VpcBlockPublicAccessExclusions.ExclusionId `
        -Filter @{Name = 'state'; Values = @('create-complete', 'update-complete')} `
        -MaxResult 1000 `
        -Verbose:$false

    if (-not $_excl_list) { return }

    $_excl_list | Where-Object { $_ -like "$_word_to_complete*" } | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# InternetGatewayExclusionMode
Register-ArgumentCompleter -ParameterName 'ExclusionMode' -CommandName $_cmd_lookup['ExclusionMode'] -ScriptBlock {
    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    [Amazon.EC2.InternetGatewayExclusionMode].GetFields() | ForEach-Object { $_.GetValue($null).Value } |
    Where-Object { $_ -like "$_word_to_complete*" } | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}