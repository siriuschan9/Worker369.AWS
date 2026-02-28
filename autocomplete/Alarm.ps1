$_cmd_lookup = @{
    SnsAction = @(
        'New-EC2CpuAlarm', 'New-EC2StatusAlarm'
    )
    LambdaAction = @(
        'New-EC2CpuAlarm', 'New-EC2StatusAlarm'
    )
}

# SnsAction
Register-ArgumentCompleter -ParameterName 'SnsAction' -CommandName $_cmd_lookup['SnsAction'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    Get-SNSTopic -Verbose:$false | Select-Object -ExpandProperty TopicArn |
    Where-Object { $_ -like "$($_word_to_complete)*"} | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# LamdaAction
Register-ArgumentCompleter -ParameterName 'LambdaAction' -CommandName $_cmd_lookup['LambdaAction'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    Get-LMFunctionList -Verbose:$false | Select-Object -ExpandProperty FunctionArn |
    Where-Object { $_ -like "$($_word_to_complete)*"} | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}