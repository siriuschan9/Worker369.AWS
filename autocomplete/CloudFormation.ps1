$_cmd_lookup = @{

    CallAs = @(
        'Show-StackSet',
        'Show-StackInstance'
    )

    StackSetName = @(
        'Show-StackInstance'
    )
}

Register-ArgumentCompleter -ParameterName 'CallAs' -CommandName $_cmd_lookup['CallAs'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    [Amazon.CloudFormation.CallAs].GetFields() | ForEach-Object { $_.GetValue($null).Value } |
    Where-Object { $_ -like "$_word_to_complete*" } | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

Register-ArgumentCompleter -ParameterName 'StackSetName' -CommandName $_cmd_lookup['StackSetName'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_call_as = $_fake_bound_parameters['CallAs'] ?? 'SELF'

    Get-CFNStackSetList -CallAs $_call_as -Select Summaries.StackSetName -Status ACTIVE |
    Where-Object { $_ -like "$_word_to_complete*" } | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}