$_cmd_lookup = @{

    PolicyArn = @(
        'Show-IamPolicyContent'
    )
    RoleName = @(
        'Show-IamRoleTrustPolicy'
    )
}

# PolicyArn
Register-ArgumentCompleter -ParameterName 'PolicyArn' -CommandName $_cmd_lookup['PolicyArn'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_arn_list = $global:IamPolicyCache_Local + $global:IamPolicyCache_AWS
    $_arn_list | Where-Object { $_ -like "$_word_to_complete*" } |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# RoleName
Register-ArgumentCompleter -ParameterName 'RoleName' -CommandName $_cmd_lookup['RoleName'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    Get-IAMRoleList -Verbose:$false -Select Roles.RoleName | Where-Object {$_ -like "$_word_to_complete*" } |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}