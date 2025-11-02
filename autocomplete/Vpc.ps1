$_cmd_lookup = @{

    VpcId = @(
        'Rename-Vpc', 'Remove-Vpc', 'Resolve-Vpc',
        'Enable-VpcDnsHostnames', 'Disable-VpcDnsHostnames',
        'Enable-VpcDnsResolution', 'Disable-VpcDnsResolution',
        'Enable-VpcNauMetrics', 'Disable-VpcNauMetrics',
        'Add-VpcIpv4Cidr', 'Remove-VpcIpv4Cidr',
        'Add-VpcIpv6Cidr', 'Remove-VpcIpv6Cidr',
        'New-VpcBpaExclusion',
        'Show-VpcCidrMap',
        'Mount-InternetGateway',
        'Show-Subnet', 'New-Subnet',
        'Show-RouteTable', 'New-RouteTable',
        'Show-NetworkAcl', 'New-NetworkAcl',
        'Show-SecurityGroup', 'New-SecurityGroup'
    )

    VpcName = @(
        'Rename-Vpc', 'Remove-Vpc',
        'Enable-VpcDnsHostnames', 'Disable-VpcDnsHostnames',
        'Enable-VpcDnsResolution', 'Disable-VpcDnsResolution',
        'Enable-VpcNauMetrics', 'Disable-VpcNauMetrics',
        'Add-VpcIpv4Cidr', 'Remove-VpcIpv4Cidr',
        'Add-VpcIpv6Cidr', 'Remove-VpcIpv6Cidr',
        'New-VpcBpaExclusion',
        'Show-VpcCidrMap',
        'Mount-InternetGateway',
        'Show-Subnet', 'New-Subnet',
        'Show-RouteTable', 'New-RouteTable',
        'Show-NetworkAcl', 'New-NetworkAcl',
        'Show-SecurityGroup', 'New-SecurityGroup'
    )

    Ipv4Cidr = @(
        'Remove-VpcIpv4Cidr', 'Remove-VpcIpv4Cidr2'
    )

    Ipv6Cidr = @(
        'Remove-VpcIpv6Cidr', 'Remove-VpcIpv6Cidr2'
    )

    Tenancy = @(
        'New-Vpc'
    )
}

# VpcId
Register-ArgumentCompleter -ParameterName 'VpcId' -CommandName $_cmd_lookup['VpcId'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_vpc_list = Get-EC2Vpc -Verbose:$false -Filter @{
        Name   = 'vpc-id'
        Values = "$_word_to_complete*"
    }

    if (-not $_vpc_list) { return }

    $_align = `
        $_vpc_list.VpcId | Select-Object -ExpandProperty Length |
        Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    $_vpc_list | Get-HintItem -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -Align $_align |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_.ResourceId,    # completionText
            $_ ,              # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# VpcName
Register-ArgumentCompleter -ParameterName 'VpcName' -CommandName $_cmd_lookup['VpcName'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    Get-EC2Vpc -Verbose:$false -Filter @{
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

# Ipv4Cidr
Register-ArgumentCompleter -ParameterName 'Ipv4Cidr' -CommandName $_cmd_lookup['Ipv4Cidr'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_vpc_id   = $_fake_bound_parameters['VpcId']
    $_vpc_name = $_fake_bound_parameters['VpcName']

    if (-not [string]::IsNullOrEmpty($_vpc_id))
    {
        $_vpc_list = Get-EC2Vpc -Filter @{Name ='vpc-id'; Values = $_vpc_id} -Verbose:$false
    }
    elseif (-not [string]::IsNullOrEmpty($_vpc_name))
    {
        $_vpc_list = Get-EC2Vpc -Filter @{Name ='tag:Name'; Values = $_vpc_name} -Verbose:$false
    }
    else { return }

    if (-not $_vpc_list) { return }

    $_cidr_list = $_vpc_list.CidrBlockAssociationSet | Where-Object { $_.CidrBlockState.State -eq 'associated'} |
    Select-Object -ExpandProperty CidrBlock

    if (-not $_cidr_list) { return }

    # $_cidr_list can contain duplicate entries for common IPv4 CIDR used in multiple VPC.
    # We use Group-Object here (using the predicate "Where-Object { $_.Count -eq $_vpc_list.Count }") to
    #   1. Remove the duplicates.
    #   2. Discard uncommon CIDR blocks.

    $_cidr_list | Group-Object -NoElement | Where-Object { $_.Count -eq $_vpc_list.Count } |
    Select-Object -ExpandProperty Name | Where-Object { $_ -like "$_word_to_complete*" } | ForEach-Object {

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

    $_vpc_id   = $_fake_bound_parameters['VpcId']
    $_vpc_name = $_fake_bound_parameters['VpcName']

    if (-not [string]::IsNullOrEmpty($_vpc_id))
    {
        $_vpc_list = Get-EC2Vpc -Filter @{Name ='vpc-id'; Values = $_vpc_id} -Verbose:$false
    }
    elseif (-not [string]::IsNullOrEmpty($_vpc_name))
    {
        $_vpc_list = Get-EC2Vpc -Filter @{Name ='tag:Name'; Values = $_vpc_name} -Verbose:$false
    }
    else { return }

    if (-not $_vpc_list) { return }

    $_cidr_list = $_vpc_list.Ipv6CidrBlockAssociationSet |
        Where-Object { $_.Ipv6CidrBlockState.State -eq 'associated'} |
        Select-Object -ExpandProperty Ipv6CidrBlock

    if (-not $_cidr_list) { return }

    # $_cidr_list can contain duplicate entries for common IPv6 CIDR used in multiple VPC.
    # We use Group-Object here (using the predicate "Where-Object { $_.Count -eq $_vpc_list.Count }") to
    #   1. Remove the duplicates.
    #   2. Discard uncommon CIDR blocks.

    $_cidr_list | Group-Object -NoElement | Where-Object { $_.Count -eq $_vpc_list.Count } |
    Select-Object -ExpandProperty Name | Where-Object { $_ -like "$_word_to_complete*" } | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# Tenancy
Register-ArgumentCompleter -ParameterName 'Tenancy' -CommandName $_cmd_lookup['Tenancy'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    [Amazon.EC2.Tenancy].GetFields() | ForEach-Object { $_.GetValue($null).Value } |
    Where-Object { $_ -like "$_word_to_complete*" } | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}