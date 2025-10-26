$_cmd_lookup = @{

    SubnetId = @(
        'Copy-Subnet', 'Remove-Subnet', 'Rename-Subnet',
        'Add-SubnetIpv4Cidr', 'Remove-SubnetIpv4Cidr',
        'Add-SubnetIpv6Cidr', 'Remove-SubnetIpv6Cidr',
        'Enable-SubnetARecord', 'Disable-SubnetARecord',
        'Enable-SubnetAAAARecord', 'Disable-SubnetAAAARecord',
        'Enable-SubnetAutoAssignPublicIP', 'Disable-SubnetAutoAssignPublicIP',
        'Enable-SubnetAutoAssignIPv6', 'Disable-SubnetAutoAssignIPv6',
        'Enable-SubnetDns64', 'Disable-SubnetDns64',
        'Set-SubnetHostnameType',
        'Add-SubnetIpv6Cidr', 'Remove-SubnetIpv6Cidr'
    )

    SubnetName = @(
        'Copy-Subnet', 'Remove-Subnet', 'Rename-Subnet',
        'Add-SubnetIpv4Cidr', 'Remove-SubnetIpv4Cidr',
        'Add-SubnetIpv6Cidr', 'Remove-SubnetIpv6Cidr',
        'Enable-SubnetARecord', 'Disable-SubnetARecord',
        'Enable-SubnetAAAARecord', 'Disable-SubnetAAAARecord',
        'Enable-SubnetAutoAssignPublicIP', 'Disable-SubnetAutoAssignPublicIP',
        'Enable-SubnetAutoAssignIPv6', 'Disable-SubnetAutoAssignIPv6',
        'Enable-SubnetDns64', 'Disable-SubnetDns64',
        'Set-SubnetHostnameType',
        'Add-SubnetIpv6Cidr', 'Remove-SubnetIpv6Cidr'
    )

    AvailabilityZone = @(
        'Copy-Subnet',
        'New-Subnet'
    )

    HostnameType = @(
        'New-Subnet',
        'Set-SubnetHostnameType'
    )

    Ipv6Cidr = @(
        'Remove-SubnetIpv6Cidr'
    )
}

# SubnetId
Register-ArgumentCompleter -ParameterName 'SubnetId' -CommandName $_cmd_lookup['SubnetId'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    # Bug: Filter for 'subnet-id' does not honour wildcard *
    # Hence, for this function, we do the filtering locally.

    $_subnet_list = Get-EC2Subnet -Verbose:$false

    if (-not $_subnet_list) { return }

    $_align = $_subnet_list.SubnetId.Length | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    $_subnet_list | Get-HintItem -IdPropertyName 'SubnetId' -TagPropertyName 'Tags' -Align $_align |
    Sort-Object | Where-Object { $_ -like "$_word_to_complete*" } | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_.ResourceId,    # completionText
            $_ ,              # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# SubnetName
Register-ArgumentCompleter -ParameterName 'SubnetName' -CommandName $_cmd_lookup['SubnetName'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    Get-EC2Subnet -Verbose:$false -Filter @{
        Name   = 'tag:Name'
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

# AvailabilityZone
Register-ArgumentCompleter `
    -ParameterName 'AvailabilityZone' -CommandName $_cmd_lookup['AvailabilityZone'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    Get-EC2AvailabilityZone -Verbose:$false -Select AvailabilityZones.ZoneName -Filter @{
        Name   = 'zone-name'
        Values = "$_word_to_complete*"
    } |
    ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# HostnameType
Register-ArgumentCompleter -ParameterName 'HostnameType' -CommandName $_cmd_lookup['HostnameType'] -ScriptBlock {
    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    [Amazon.EC2.HostnameType].GetFields() | ForEach-Object { $_.GetValue($null).Value } |
    Where-Object { $_ -like "$_word_to_complete*" } | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# Ipv6Cidr
Register-ArgumentCompleter -ParameterName 'Ipv6Cidr' -CommandName $_cmd_lookup['Ipv6Cidr'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_subnet_id   = $_fake_bound_parameters['SubnetId']
    $_subnet_name = $_fake_bound_parameters['SubnetName']

    if ($_subnet_id)
    {
        $_subnet_list = Get-EC2Subnet -Verbose:$false -Filter @{Name ='subnet-id'; Values = $_subnet_id}
    }
    elseif ($_subnet_name)
    {
        $_subnet_list = Get-EC2Subnet -Verbose:$false -Filter @{Name ='tag:Name'; Values = $_subnet_name}
    }
    else { return }

    if (-not $_subnet_list) { return }

    $_subnet_list.Ipv6CidrBlockAssociationSet |
    Where-Object { $_.Ipv6CidrBlockState.State -eq 'associated' } | Select-Object -ExpandProperty Ipv6CidrBlock |
    Where-Object { $_ -like "$_word_to_complete*" } | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}