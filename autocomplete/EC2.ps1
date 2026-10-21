$_cmd_lookup = @{
    InstanceId = @(
        'Start-Ec2', 'Stop-Ec2',
        'Get-Ec2SystemLog',
        'New-Ec2CpuAlarm', 'New-Ec2StatusAlarm',
        'Disable-EbsDeleteOnTermination'
    )
    InstanceName = @(
        'Start-Ec2', 'Stop-Ec2',
        'Get-Ec2SystemLog',
        'Disable-EbsDeleteOnTermination'
    )
    DeviceName = @(
        'Disable-EbsDeleteOnTermination'
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

# DeviceName
Register-ArgumentCompleter -ParameterName 'DeviceName' -CommandName $_cmd_lookup['DeviceName'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_instance_id = $_fake_bound_parameters['InstanceId']
    $_instance_name = $_fake_bound_parameters['InstanceName']

    if (-not [string]::IsNullOrEmpty($_instance_id))
    {
        $_instance_list = `
            Get-EC2Instance -Verbose:$false -Filter @{Name = 'instance-id'; Values = $_instance_id} |
            Select-Object -ExpandProperty Instances
    }
    elseif (-not [string]::IsNullOrEmpty($_instance_name))
    {
        $_instance_list = `
            Get-EC2Instance -Verbose:$false -Filter @{Name = 'tag:Name'; Values = $_instance_name} |
            Select-Object -ExpandProperty Instances
    }
    else { return }

    if (-not $_instance_list -or $_instance_list.Count -gt 1) { return }

    $_instance_list[0] | Select-Object -ExpandProperty BlockDeviceMappings |
    Select-Object -ExpandProperty DeviceName | Where-Object { $_ -like "$_word_to_complete*" } |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}