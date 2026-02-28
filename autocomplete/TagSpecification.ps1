$_cmd_lookup = @{
    ResourceType = @('New-TagSpecification')
}

Register-ArgumentCompleter -ParameterName 'ResourceType' -CommandName $_cmd_lookup['ResourceType'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    [Amazon.EC2.ResourceType].GetFields() | ForEach-Object {
        $_.GetValue($null).Value
    } |
    Where-Object { $_ -like "$_word_to_complete*" } | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}