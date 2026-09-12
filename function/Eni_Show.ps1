using namespace System.Collections.Generic
using namespace Amazon.EC2.Model
using namespace Worker369.Utility

function Show-NetworkInterface
{
    [CmdletBinding(DefaultParameterSetName = 'None')]
    [Alias('eni_show')]
    param (
        [Parameter(Position = 0)]
        [ValidateSet('Attachment', 'IpAssignment', 'Network', 'Status', 'Security')]
        [string]
        $View = 'Status',

        [Parameter(ParameterSetName = 'VpcId')]
        [ValidatePattern('^vpc-[0-9a-f]{17}$')]
        [string[]]
        $VpcId,

        [Parameter(ParameterSetName = 'VpcName')]
        [string[]]
        $VpcName,

        [Amazon.EC2.Model.Filter[]]
        $Filter,

        [ValidateSet('Vpc', 'Subnet', 'AvailabilityZone', 'ResourceType', $null)]
        [string]
        $GroupBy = 'Vpc',

        [Int[]]
        $Sort,

        [Int[]]
        $Exclude,

        [switch]
        $PlainText,

        [switch]
        $NoRowSeparator
    )

    # Use snake_case.
    $_view             = $View
    $_vpc_id           = $VpcId
    $_vpc_name         = $VpcName
    $_filter           = $Filter
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    # For easy pick-up later.
    $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name

    $_view_definition = @{
        Attachment = @(
            'NetworkInterfaceId', 'AttachmentId', 'DeviceIndex' ,'DeleteOnTermination', 'ResourceType', 'Description'
        )
        Network = @(
            'NetworkInterfaceId', 'Subnet', 'AvailabilityZone',
            'PrivateIp', 'PublicIp', 'Ipv6Address', 'MacAddress'
        )
        IpAssignment = @(
            'NetworkInterfaceId', 'PrivateIp', 'PublicIp', 'Ipv6Address', 'AutoAssignPublicIp',
            'Ipv4Prefix', 'Ipv6Prefix'
        )
        Security = @(
            'NetworkInterfaceId', 'Status', 'SecurityGroups', 'SourceDestCheck',
            'TcpEstablishedTimeout', 'UdpStreamTimeout', 'UdpTimeout'
        )
        Status = @(
            'NetworkInterfaceId', 'Status', 'PrivateIp', 'PublicIp', 'Ipv6Address', 'ResourceType', 'Description'
        )
    }

    $_select_definition = @{
        AutoAssignPublicIp = {
            $_auto_assign_public_ip_lookup[$_.NetworkInterfaceId]
        }
        AvailabilityZone = {
            $_.AvailabilityZone
        }
        AttachmentId = {
            $_.Attachment.AttachmentId
        }
        DeleteOnTermination = {
            New-Checkbox -PlainText:$_plain_text $_.Attachment.DeleteOnTermination
        }
        Description = {
            $_.Description
        }
        DeviceIndex = {
            $_.Attachment.DeviceIndex
        }
        InterfaceType = {
            $_.InterfaceType
        }
        Ipv6Address = {
            $_sort_expr = {$_.Ipv6Address | New-IPv6Address}
            $_map_expr  = {$_.IsPrimaryIpv6 ? "[ P ] $($_.Ipv6Address)" : "[   ] $($_.Ipv6Address)"}

            $_.Ipv6Addresses | Sort-Object @{Expression = $_sort_expr} | ForEach-Object $_map_expr
        }
        Ipv4Prefix = {
            $_.Ipv4Prefixes | Select-Object -ExpandProperty IPv4Prefix | New-IPv4Subnet | Sort-Object
        }
        Ipv6Prefix = {
            $_.Ipv6Prefixes | Select-Object -ExpandProperty IPv6Prefix | New-IPv6Subnet | Sort-Object
        }
        MacAddress = {
            $_.MacAddress
        }
        Name = {
            $_.TagSet | Where-Object Key -eq 'Name' | Select-Object -ExpandProperty Value
        }
        NetworkInterfaceId = {
            $_.NetworkInterfaceId
        }
        PrivateIp = {
            $_sort_expr = {$_.PrivateIpAddress | New-IPv4Address}
            $_map_expr  = {$_.Primary ? "[ P ] $($_.PrivateIpAddress)" : "[   ] $($_.PrivateIpAddress)"}

            $_.PrivateIpAddresses | Sort-Object @{Expression = $_sort_expr} | ForEach-Object $_map_expr
        }
        PublicIp = {
            $_dash      = $_plain_text ? '-' : "$($PSStyle.Dim)-$($PSStyle.Reset)"
            $_sort_expr = {$_.PrivateIpAddress | New-IPv4Address}
            $_map_expr  = {$_.Primary `
                ? "[ P ] $($_.Association.PublicIp ?? $_dash)" `
                : "[   ] $($_.Association.PublicIp ?? $_dash)"
            }
            $_.PrivateIpAddresses | Sort-Object @{Expression = $_sort_expr} | ForEach-Object $_map_expr
        }
        SecurityGroups = {
            $_.Groups | ForEach-Object {
                $_sg_lookup[$_.GroupId] |
                Get-ResourceString -IdPropertyName 'GroupId' -NamePropertyName 'GroupName' -PlainText:$_plain_text
            }
        }
        SourceDestCheck = {
            New-Checkbox -PlainText:$_plain_text $_.SourceDestCheck
        }
        Status = {
            $_status = $_.Status.Value
            New-Checkbox -PlainText:$_plain_text -Description $_status ($_status -eq 'in-use')
        }
        Subnet = {
            $_subnet_lookup[$_.SubnetId] | Get-ResourceString `
                -IdPropertyName 'SubnetId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
        TcpEstablishedTimeout = {
            $_value   = $_.ConnectionTrackingConfiguration.TcpEstablishedTimeout
            $_default = $_plain_text ? 'Default' : "$($PSStyle.Dim)Default$($PSStyle.Reset)"
            $_value   ? (New-NumberInfo $_value) : $_default
        }
        UdpStreamTimeout = {
            $_value   = $_.ConnectionTrackingConfiguration.UdpStreamTimeout
            $_default = $_plain_text ? 'Default' : "$($PSStyle.Dim)Default$($PSStyle.Reset)"
            $_value   ? (New-NumberInfo $_value) : $_default
        }
        UdpTimeout = {
            $_value   = $_.ConnectionTrackingConfiguration.UdpTimeout
            $_default = $_plain_text ? 'Default' : "$($PSStyle.Dim)Default$($PSStyle.Reset)"
            $_value   ? (New-NumberInfo $_value) : $_default
        }
        Vpc = {
            $_vpc_lookup[$_.VpcId] | Get-ResourceString `
                -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
        ResourceType = {
            $_types_lookup[$_.NetworkInterfaceId]
        }
    }

    try {
        # Initialize a filter list.
        $_filter_list = [List[Filter]]::new()

        # Add elements in the -Filter parameter to the filter list.
        $_filter.ForEach({
            $_filter_list.Add($_)
        })

        # Add the -VpcId parameter to the filter list.
        if (-not [string]::IsNullOrEmpty($_vpc_id))
        {
            $_filter_list.Add([Filter]@{
                Name   = 'vpc-id'
                Values = $_vpc_id
            })
        }

        # Find out the VPC ID from the -VpcName parameter.
        if (-not [string]::IsNullOrEmpty($_vpc_name))
        {
            $_vpc_id_filter = Get-EC2Vpc -Verbose:$false `
                -Select Vpcs.VpcId -Filter @{Name = 'tag:Name'; Values = $_vpc_name}

            # Add a vpc-id filter to the filter list.
            if ($_vpc_id_filter)
            {
                $_vpc_filter = [Filter]@{
                    Name   = 'vpc-id'
                    Values = $_vpc_id_filter
                }
                $_filter_list.Add($_vpc_filter)
            }
        }

        # Query ENIs.
        Write-Message -Progress $_cmdlet_name 'Fetching ENI data.'
        $_eni_list = `
            Get-EC2NetworkInterface -Verbose:$false -Filter $($_filter_list.Count -eq 0 ? $null : $_filter_list)

        # Exit early if there are no ENIs to show.
        if (-not $_eni_list) { return }

        # Query VPCs.
        if ($_group_by -in ('Vpc')) {
            Write-Message -Progress $_cmdlet_name 'Fetching VPC data.'
            $_vpc_id_list = $_eni_list | Select-Object -Unique -ExpandProperty VpcId
            $_vpc_lookup  = `
                Get-EC2Vpc -Verbose:$false -Filter @{ Name = 'vpc-id'; Values = $_vpc_id_list} |
                Group-Object -AsHashTable VpcId
        }

        # Query Subnets.
        if ($_view -in @('Network') -or $_group_by -in ('Vpc', 'Subnet')) {
            Write-Message -Progress $_cmdlet_name 'Fetching Subnet data.'
            $_subnet_id_list = $_eni_list | Select-Object -Unique -ExpandProperty SubnetId
            $_subnet_lookup  = `
                Get-EC2Subnet -Verbose:$false -Filter @{ Name = 'subnet-id'; Values = $_subnet_id_list } |
                Group-Object -AsHashTable SubnetId
        }

        # Query Security Groups.
        if ($_view -in @('Security')) {
            Write-Message -Progress $_cmdlet_name 'Fetching Security Group data.'
            $_sg_id_list = $_eni_list | Select-Object -ExpandProperty Groups | Select-Object -Unique -ExpandProperty GroupId
            $_sg_lookup  = `
                Get-EC2SecurityGroup -Verbose:$false -Filter @{ Name = 'group-id'; Values = $_sg_id_list } |
                Group-Object -AsHashTable GroupId
        }

        if ($_iew -in @('IpAssignment')) {
            Write-Message -Progress $_cmdlet_name 'Fetching ENI attribute data.'
        }

        # Query EIPs.
        # $_eip_lookup = Get-EC2Address -Verbose:$false | Group-Object -AsHashTable PrivateIpAddress
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    $_types_lookup = @{}
    foreach ($_eni in $_eni_list)
    {
        if ($_eni.InterfaceType -eq 'interface')
        {
            switch ($_eni.RequesterId)
            {
                'amazon-rds' { $_types_lookup[$_eni.NetworkInterfaceId] = 'RDS' }
                'amazon-elb' { $_types_lookup[$_eni.NetworkInterfaceId] = 'ALB' }
                default      { $_types_lookup[$_eni.NetworkInterfaceId] = 'EC2' }
            }
        }
        elseif ($_eni.InterfaceType -eq 'network_load_balancer')
        {
            $_types_lookup[$_eni.NetworkInterfaceId] = 'NLB'
        }
        elseif ($_eni.InterfaceType -eq 'gateway_load_balancer_endpoint')
        {
            $_types_lookup[$_eni.NetworkInterfaceId] = 'GWLB'
        }
        elseif ($_eni.InterfaceType -eq 'vpc_endpoint')
        {
            $_types_lookup[$_eni.NetworkInterfaceId] = 'VPCE'
        }
        elseif ($_eni.InterfaceType -eq 'nat_gateway')
        {
            $_types_lookup[$_eni.NetworkInterfaceId] = 'NAT'
        }
        elseif ($_eni.InterfaceType -eq 'transit_gateway')
        {
            $_types_lookup[$_eni.NetworkInterfaceId] = 'TGW'
        }
        elseif ($_eni.InterfaceType -eq 'lambda')
        {
            $_types_lookup[$_eni.NetworkInterfaceId] = 'Lambda'
        }
    }

    # Apply default sort order.
    if ($_group_by -eq 'Vpc' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(2) # => Sort by Name
    }

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             $_view `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    # Generate output after sorting and exclusion.
    $_output = $_eni_list | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column `
            -GroupBy $_group_by `
            -PlainText:$_plain_text `
            -NoRowSeparator:$_no_row_separator `
            -AlignLeft Status `
            -AlignRight TcpEstablishedTimeout, UdpStreamTimeout, UdpTimeout
    }
}
