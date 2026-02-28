$_cmd_lookup = @{

    RoleName = @(
        'Show-IamRoleTrustPolicy'
    )
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

    Get-IAMRoleList -Verbose:$false -Select Roles.RoleName | Where-Object {
        $_ -like "$_word_to_complete*"
    } | Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}