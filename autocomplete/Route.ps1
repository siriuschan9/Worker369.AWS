Register-ArgumentCompleter -CommandName 'Remove-Route' -ParameterName 'Destination' -ScriptBlock {
    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_rt_id   = $_fake_bound_parameters['RouteTableId']
    $_rt_name = $_fake_bound_parameters['RouteTableName']

    if (-not [string]::IsNullOrEmpty($_rt_id))
    {
        $_rt = Get-EC2RouteTable -Verbose:$false -Filter @{Name = 'route-table-id'; Values = $_rt_id}
    }
    elseif (-not [string]::IsNullOrEmpty($_rt_name))
    {
        $_rt = Get-EC2RouteTable -Verbose:$false -Filter @{Name = 'tag:Name'; Values = $_rt_name}
    }
    elseif ($_default_rt = Get-DefaultRouteTable -Raw)
    {
        $_rt = Get-EC2RouteTable -Verbose:$false -Filter @{Name = 'route-table-id'; Values = $_default_rt.RouteTableId}
    }
    else { return }

    if (-not $_rt -or $_rt.Count -gt 1) { return }

    $_routes = $_rt.Routes | Where-Object Origin -ne 'CreateRouteTable'

    $_dst_ipv4 = (
        $_routes | Select-Object -ExpandProperty DestinationCidrBlock | New-IPv4Subnet | Sort-Object
    ) -as [Array]

    $_dst_ipv6 = (
        $_routes | Select-Object -ExpandProperty DestinationIpv6CidrBlock | New-IPv6Subnet | Sort-Object
    ) -as [Array]

    $_dst_pl = (
        $_routes | Select-Object -ExpandProperty DestinationPrefixListId | Sort-Object
    ) -as [Array]

    $_dst_ipv4 + $_dst_ipv6 + $_dst_pl | Where-Object { $_ -like "$_word_to_complete*" } | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

Register-ArgumentCompleter -CommandName 'Add-Route' -ParameterName 'Gateway' -ScriptBlock {
    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_rt_id   = $_fake_bound_parameters['RouteTableId']
    $_rt_name = $_fake_bound_parameters['RouteTableName']

    if (-not [string]::IsNullOrEmpty($_rt_id))
    {
        $_rt = Get-EC2RouteTable -Verbose:$false -Filter @{Name = 'route-table-id'; Values = $_rt_id}
    }
    elseif (-not [string]::IsNullOrEmpty($_rt_name))
    {
        $_rt = Get-EC2RouteTable -Verbose:$false -Filter @{Name = 'tag:Name'; Values = $_rt_name}
    }
    elseif ($_default_rt = Get-DefaultRouteTable -Raw)
    {
        $_rt = Get-EC2RouteTable -Verbose:$false -Filter @{Name = 'route-table-id'; Values = $_default_rt.RouteTableId}
    }
    else { return }

    if (-not $_rt -or $_rt.Count -gt 1) { return }

    switch -Regex ($_word_to_complete)
    {
        # Internet Gateway
        '^igw-[0-9-a-f]{0,17}$' {
            $_igw_list = Get-EC2InternetGateway -Verbose:$false -Filter @{
                Name   = 'internet-gateway-id'
                Values = "$_word_to_complete*"
            }, @{
                Name   = 'attachment.vpc-id'
                Values = $_rt.VpcId
            }

            if (-not $_igw_list) { return }

            $_igw_align = $_igw_list.InternetGatewayId.Length | Measure-Object | Select-Object -ExpandProperty Maximum

            $_igw_list | Get-HintItem -IdPropertyName 'InternetGatewayId' -TagPropertyName 'Tags' -Align $_igw_align |
            Sort-Object | ForEach-Object {

                [System.Management.Automation.CompletionResult]::new(
                    $_.ResourceId,    # completionText
                    $_,               # listItemText
                    'ParameterValue', # resultType
                    $_                # toolTip
                )
            }
        }
        # Virtual Private Gateway
        '^vgw-[0-9-a-f]{0,17}$' {
            $_vgw_list = Get-EC2VpnGateway -Verbose:$false -Filter @{
                Name   = 'vpn-gateway-id'
                Values = "$_word_to_complete*"
            }

            if (-not $_vgw_list) { return }

            $_vgw_align = $_vgw_list.VpnGatewayId | Measure-Object | Select-Object -ExpandProperty Maximum

            $_vgw_list | Get-HintItem -IdPropertyName 'VpnGatewayId' -TagPropertyName 'Tags' -Align $_vgw_align |
            Sort-Object | ForEach-Object {

                [System.Management.Automation.CompletionResult]::new(
                    $_.ResourceId,    # completionText
                    $_,               # listItemText
                    'ParameterValue', # resultType
                    $_                # toolTip
                )
            }
            break
        }
        # VPC Peering Connection
        '^pcx-[0-9-a-f]{0,17}$' {
            $_requester_list = (
                Get-EC2VpcPeeringConnection -Verbose:$false -Filter @{
                    Name   = 'vpc-peering-connection-id'
                    Values = "$_word_to_complete*"
                }, @{
                    Name   = 'requester-vpc-info.vpc-id'
                    Values = $_rt.VpcId
                }
            ) -as [Array]

            $_accepter_list = (
                Get-EC2VpcPeeringConnection -Verbose:$false -Filter @{
                    Name   = 'vpc-peering-connection-id'
                    Values = "$_word_to_complete*"
                }, @{
                    Name   = 'accepter-vpc-info.vpc-id'
                    Values = $_rt.VpcId
                }
            ) -as [Array]

            if ($_accepter_list.Length -eq 0 -and $_requester_list.Length -eq 0) { return }

            $_pcx_align = (
                $_requester_list + $_accepter_list
            ).VpcPeeringConnectionId.Length | Measure-Object | Select-Object -ExpandProperty Maximum

            $_requester_list + $_accepter_list |
            Get-HintItem -IdPropertyName 'VpcPeeringConnectionId' -TagPropertyName 'Tags' -Align $_pcx_align |
            Sort-Object | ForEach-Object {

                [System.Management.Automation.CompletionResult]::new(
                    $_.ResourceId,    # completionText
                    $_,               # listItemText
                    'ParameterValue', # resultType
                    $_                # toolTip
                )
            }
            break
        }
        # NAT Gateway
        '^nat-[0-9-a-f]{0,17}$' {
            $_nat_list = Get-EC2NatGateway -Verbose:$false -Filter @{
                Name   = 'nat-gateway-id'
                Values = "$_word_to_complete*"
            }

            if (-not $_nat_list) { return }

            $_nat_align = $_nat_list.NatGatewayId.Length | Measure-Object | Select-Object -ExpandProperty Maximum

            $_nat_list | Get-HintItem -IdPropertyName 'NatGatewayId' -TagPropertyName 'Tags' -Align $_nat_align |
            Sort-Object | ForEach-Object {

                [System.Management.Automation.CompletionResult]::new(
                    $_.ResourceId,    # completionText
                    $_,               # listItemText
                    'ParameterValue', # resultType
                    $_                # toolTip
                )
            }
            break
        }
        # Transit Gateway
        '^tgw-[0-9-a-f]{0,17}$' {
            $_tgw_attach_list = Get-EC2TransitGatewayAttachment -Verbose:$false -Filter @{
                Name   = 'resource-id'
                Values = $_rt.VpcId
            }

            if (-not $_tgw_attach_list) { return }

            $_tgw_list = Get-EC2TransitGateway -Verbose:$false -Filter @{
                Name   = 'transit-gateway-id'
                Values = $_tgw_attach_list.TransitGatewayId
            }

            if (-not $_tgw_list) { return }

            $_tgw_align = $_tgw_list.TransitGatewayId.Length | Measure-Object | Select-Object -ExpandProperty Maximum

            $_tgw_list | Get-HintItem -IdPropertyName 'TransitGatewayId' -TagPropertyName 'Tags' -Align $_tgw_align |
            Sort-Object | ForEach-Object {

                [System.Management.Automation.CompletionResult]::new(
                    $_.ResourceId,    # completionText
                    $_,               # listItemText
                    'ParameterValue', # resultType
                    $_                # toolTip
                )
            }
            break
        }
        # Network Interface
        '^eni-[0-9-a-f]{0,17}$' {
            $_eni_list = Get-EC2NetworkInterface -Verbose:$false -Filter @{
                Name   = 'network-interface-id'
                Values = "$_word_to_complete*"
            }

            if (-not $_eni_list) { return }

            $_eni_align = $_eni_list.NetworkInterfaceId | Measure-Object | Select-Object -ExpandProperty Maximum

            $_eni_list | Get-HintItem -IdPropertyName 'NetworkInterfaceId' -TagPropertyName 'Tags' -Align $_eni_align |
            Sort-Object | ForEach-Object {

                [System.Management.Automation.CompletionResult]::new(
                    $_.ResourceId,    # completionText
                    $_,               # listItemText
                    'ParameterValue', # resultType
                    $_                # toolTip
                )
            }
            break
        }
        # EC2 Instance
        '^i-[0-9-a-f]{0,17}$' {
            $_ec2_list = Get-EC2Instance -Verbose:$false -Select Reservations.Instances -Filter @{
                Name   = 'instance-id'
                Values = "$_word_to_complete*"
            }

            if (-not $_ec2_list) { return }

            $_ec2_align = $_ec2_list.NetworkInterfaceId | Measure-Object | Select-Object -ExpandProperty Maximum

            $_ec2_list | Get-HintItem -IdPropertyName 'NetworkInterfaceId' -TagPropertyName 'Tags' -Align $_ec2_align |
            Sort-Object | ForEach-Object {

                [System.Management.Automation.CompletionResult]::new(
                    $_.ResourceId,    # completionText
                    $_,               # listItemText
                    'ParameterValue', # resultType
                    $_                # toolTip
                )
            }
            break
        }
        # VPC Endpoint
        '^vpce-[0-9-a-f]{0,17}$' {
            $_vpce_list = Get-EC2VpcEndpoint -Verbose:$false -Filter @{
                Name   = 'vpc-endpoint-id'
                Values = "$_word_to_complete*"
            }, @{
                Name   = 'vpc-id'
                Values = $_rt.VpcId
            }

            if (-not $_vpce_list) {return }

            $_vpce_align = $_vpce_list.VpcEndpointId | Measure-Object | Select-Object -ExpandProperty Maximum

            $_vpce_list | Get-HintItem -IdPropertyName 'VpcEndpointId' -TagPropertyName 'Tags' -Align $_vpce_align |
            Sort-Object | ForEach-Object {

                [System.Management.Automation.CompletionResult]::new(
                    $_.ResourceId,    # completionText
                    $_,               # listItemText
                    'ParameterValue', # resultType
                    $_                # toolTip
                )
            }
            break
        }
        # Transit Gateway
        '^tgw-[0-9-a-f]{0,17}$' {
            $_tgw_list = Get-EC2TransitGateway -Verbose:$false -Filter @{
                Name   = 'transit-gateway-id'
                Values = "$_word_to_complete*"
            }

            if (-not $_tgw_list) { return }

            $_tgw_align = $_tgw_list.TransitGatewayId | Measure-Object | Select-Object -ExpandProperty Maximum

            $_tgw_list | Get-HintItem -IdPropertyName 'TransitGatewayId' -TagPropertyName 'Tags' -Align $_tgw_align |
            Sort-Object | ForEach-Object {

                [System.Management.Automation.CompletionResult]::new(
                    $_.ResourceId,    # completionText
                    $_,               # listItemText
                    'ParameterValue', # resultType
                    $_                # toolTip
                )
            }
            break
        }
        # Prefix List
        '^pl-[0-9a-f]{0,17}' {
            $_pl_list = Get-EC2ManagedPrefixList -Verbose:$false -Filter @{
                Name   = 'prefix-list-id'
                Values = "$_word_to_complete*"
            }

            if (-not $_pl_list) { return }

            $_pl_list | Sort-Object PrefixListName | ForEach-Object {

                $_display_item = '{0,-20} {1}' -f $_.PrefixListId, "$_dim| $($_.PrefixListName)$_reset"

                [System.Management.Automation.CompletionResult]::new(
                    $_.PrefixListId,  # completionText
                    $_display_item,   # listItemText
                    'ParameterValue', # resultType
                    $_display_item    # toolTip
                )
            }
        }
        default { return }
    }
}

Register-ArgumentCompleter -CommandName 'Add-Route' -ParameterName 'Destination' -ScriptBlock {
    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_rt_id   = $_fake_bound_parameters['RouteTableId']
    $_rt_name = $_fake_bound_parameters['RouteTableName']
    $_gw      = $_fake_bound_parameters['Gateway']

    # Exit early if we do not have a -Gateway parameter.
    if ([string]::IsNullOrEmpty($_gw)) { return }

    # Try to get the route table in attention.
    if (-not [string]::IsNullOrEmpty($_rt_id))
    {
        $_rt = Get-EC2RouteTable -Verbose:$false -Filter @{Name = 'route-table-id'; Values = $_rt_id}
    }
    elseif (-not [string]::IsNullOrEmpty($_rt_name))
    {
        $_rt = Get-EC2RouteTable -Verbose:$false -Filter @{Name = 'tag:Name'; Values = $_rt_name}
    }
    elseif ($_default_rt = Get-DefaultRouteTable -Raw)
    {
        $_rt = Get-EC2RouteTable -Verbose:$false -Filter @{Name = 'route-table-id'; Values = $_default_rt.RouteTableId}
    }
    else { return }

    # Exit early if the route table in attention is not specified.
    if (-not $_rt -or $_rt.Count -gt 1) { return }

    $_dst_ipv4 = $_rt.Routes | Select-Object -ExpandProperty DestinationCidrBlock
    $_dst_ipv6 = $_rt.Routes | Select-Object -ExpandProperty DestinationIpv6CidrBlock
    $_dst_pl   = $_rt.Routes | Select-Object -ExpandProperty DestinationPrefixListId

    switch -Regex ($_gw)
    {
        # VPC Peering Connection - Hint remote CIDRs.
        '^pcx-[0-9a-f]{17}$' {
            if ($_pcx = Get-EC2VpcPeeringConnection -Verbose:$false $_gw)
            {
                if ($_rt.VpcId -eq $_pcx.RequesterVpcInfo.VpcId)
                {
                    $_pcx.AccepterVpcInfo.CidrBlockSet | Select-Object -ExpandProperty Cidr |
                    Where-Object { $_ -NotIn $_dst_ipv4 -and $_ -like "$_word_to_complete*" } | New-IPv4Subnet |
                    Sort-Object | ForEach-Object {

                        [System.Management.Automation.CompletionResult]::new(
                            $_,               # completionText
                            $_,               # listItemText
                            'ParameterValue', # resultType
                            $_                # toolTip
                        )
                    }

                    $_pcx.AccepterVpcInfo.Ipv6CidrBlockSet | Select-Object -ExpandProperty Value |
                    Where-Object { $_ -NotIn $_dst_ipv6 -and $_ -like "$_word_to_complete*" } | New-IPv6Subnet |
                    Sort-Object | ForEach-Object {

                        [System.Management.Automation.CompletionResult]::new(
                            $_,               # completionText
                            $_,               # listItemText
                            'ParameterValue', # resultType
                            $_                # toolTip
                        )
                    }
                }
                else
                {
                    $_pcx.RequesterVpcInfo.CidrBlockSet | Select-Object -ExpandProperty Cidr |
                    Where-Object { $_ -NotIn $_dst_ipv4 -and $_ -like "$_word_to_complete*"} | New-IPv4Subnet |
                    Sort-Object | ForEach-Object {

                        [System.Management.Automation.CompletionResult]::new(
                            $_,               # completionText
                            $_,               # listItemText
                            'ParameterValue', # resultType
                            $_                # toolTip
                        )
                    }

                    $_pcx.RequesterVpcInfo.Ipv6CidrBlockSet | Select-Object -ExpandProperty Value |
                    Where-Object { $_ -notin $_dst_ipv6 -and $_ -like "$_word_to_complete*" } | New-IPv6Subnet |
                    Sort-Object | ForEach-Object {

                        [System.Management.Automation.CompletionResult]::new(
                            $_,               # completionText
                            $_,               # listItemText
                            'ParameterValue', # resultType
                            $_                # toolTip
                        )
                    }
                }
            }
        }
        # Internet Gateway - Hint 0.0.0.0/0 and ::/0.
        '^igw-[0-9a-f]{17}$' {
            '0.0.0.0/0' | Where-Object { $_ -notin $_dst_ipv4 -and $_ -like "$_word_to_complete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    $_,               # completionText
                    $_,               # listItemText
                    'ParameterValue', # resultType
                    $_                # toolTip
                )
            }
            '::/0' | Where-Object { $_ -notin $_dst_ipv6 -and $_ -like "$_word_to_complete*"} | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    $_,               # completionText
                    $_,               # listItemText
                    'ParameterValue', # resultType
                    $_                # toolTip
                )
            }
        }
        # Transit Gateway - Hint TGW route entries.
        'tgw-[0-9a-f]{17}$' {

            if ($_tgw = Get-EC2TransitGateway -Verbose:$false -TransitGatewayId $_gw)
            {
                $_tgw_rt_id = Get-EC2TransitGatewayAttachment -Verbose:$false -Filter @{
                    Name   = 'resource-id'
                    Values = $_rt.VpcId
                } `
                | Where-Object TransitGatewayId -EQ $_tgw.TransitGatewayId `
                | Select-Object -ExpandProperty Association `
                | Select-Object -ExpandProperty TransitGatewayRouteTableId

                if (-not $_tgw_rt_id) { return }

                $_route_list = Search-EC2TransitGatewayRoute $_tgw_rt_id -Verbose:$false -Filter @{
                    Name = 'state'
                    Values = 'active'
                } `
                | Select-Object -ExpandProperty Routes `
                | Where-Object {
                    (
                        $_.TransitGatewayAttachments |
                        Select-Object -ExpandProperty ResourceId
                    ) -notcontains $_rt.VpcId
                }

                if (-not $_route_list) { return }

                $_route_list | Select-Object -ExpandProperty DestinationCidrBlock | Where-Object {
                    $_ -notin (@($_dst_ipv4) + @($_dst_ipv6)) -and $_ -like "$($_word_to_complete)*"
                } `
                | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new(
                        $_,               # completionText
                        $_,               # listItemText
                        'ParameterValue', # resultType
                        $_                # toolTip
                    )
                }

                $_route_list | Select-Object -ExpandProperty PrefixListId | Where-Object {
                    $_ -notin $_dst_pl -and $_ -like "$($_word_to_complete)*"
                } `
                | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new(
                        $_,               # completionText
                        $_,               # listItemText
                        'ParameterValue', # resultType
                        $_                # toolTip
                    )
                }
            }
        }
        # VPC Endpoint for S3 or DynamoDB - Hint prefix list.
        '^vpce-[0-9a-f]{17}$' {

            $_dim   = [System.Management.Automation.PSStyle]::Instance.Dim
            $_reset = [System.Management.Automation.PSStyle]::Instance.Reset

            if ($_vpce = Get-EC2VpcEndpoint -Verbose:$false $_gw)
            {
                $_s3_pl = Get-EC2ManagedPrefixList -Verbose:$false -Filter @{
                    Name   = 'prefix-list-name'
                    Values = "com.amazonaws.$(Get-DefaultAWSRegion).s3"
                }

                if ($_vpce.ServiceName -eq $_s3_pl.PrefixListName)
                {
                    $_s3_pl | Where-Object {
                        $_.PrefixListId -notin $_dst_pl -and
                        $_.PrefixListId -like "$_word_to_complete*"
                    }
                    | Sort-Object PrefixListName | ForEach-Object {

                        $_display_item = '{0,-20} {1}' -f $_.PrefixListId, "$_dim| $($_.PrefixListName)$_reset"

                        [System.Management.Automation.CompletionResult]::new(
                            $_.PrefixListId,  # completionText
                            $_display_item,   # listItemText
                            'ParameterValue', # resultType
                            $_display_item    # toolTip
                        )
                    }
                    return
                }

                $_dynamo_pl = Get-EC2ManagedPrefixList -Verbose:$false -Filter @{
                    Name   = 'prefix-list-name'
                    Values = "com.amazonaws.$(Get-DefaultAWSRegion).dynamodb"
                }

                if ($_vpce.ServiceName -eq $_dynamo_pl.PrefixListName)
                {
                    $_dynamo_pl | Where-Object {
                        $_.PrefixListId -notin $_dst_pl -and
                        $_.PrefixListId -like "$_word_to_complete*"
                    }
                    | Sort-Object PrefixListName | ForEach-Object {

                        $_display_item = '{0,-20} {1}' -f $_.PrefixListId, "$_dim| $($_.PrefixListName)$_reset"

                        [System.Management.Automation.CompletionResult]::new(
                            $_.PrefixListId,  # completionText
                            $_display_item,   # listItemText
                            'ParameterValue', # resultType
                            $_display_item    # toolTip
                        )
                    }
                    return
                }
            }
        }
    }
}