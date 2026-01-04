$_cmd_lookup = @{
    InstanceId = @(
        'Get-EC2SystemLog',
        'New-EC2CpuAlarm', 'New-EC2StatusAlarm'
    )
    InstanceName = @(
        'Get-EC2SystemLog'
    )
}

# InstanceId
Register-ArgumentCompleter -ParameterName 'InstanceId' -CommandName $_cmd_lookup['InstanceId'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_ec2_list = Get-EC2Instance -Verbose:$false -Select Reservations.Instances -Filter @{
        Name   = 'instance-id'
        Values = "$($_word_to_complete)*"
    }

    if (-not $_ec2_list) { return }

    $_align = `
        $_ec2_list.InstanceId | Select-Object -ExpandProperty Length |
        Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    $_ec2_list | Get-HintItem -IdPropertyName 'InstanceId' -TagPropertyName 'Tags' -Align $_align |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_.ResourceId,    # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# InstanceName
Register-ArgumentCompleter -ParameterName 'InstanceName' -CommandName $_cmd_lookup['InstanceName'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    Get-EC2Instance -Verbose:$false -Filter @{
        Name = 'tag:Name'
        Values = "$_word_to_complete*"
    } |
    Select-Object -ExpandProperty Instances | Select-Object -ExpandProperty Tags |
    Where-Object Key -eq 'Name' | Select-Object -Unique -ExpandProperty Value |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}