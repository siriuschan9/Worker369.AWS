$_cmd_lookup = @{
    LoadBalancerArn = @(
        'Get-Elb2LoadBalancer'
    )
}

# LoadBalancerName
Register-ArgumentCompleter -ParameterName 'LoadBalancerArn' -CommandName $_cmd_lookup['LoadBalancerArn'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    Get-ELB2LoadBalancer -Verbose:$false -Select LoadBalancers.LoadBalancerArn | 
    Where-Object {$_ -like "$_word_to_complete*"} | Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}
