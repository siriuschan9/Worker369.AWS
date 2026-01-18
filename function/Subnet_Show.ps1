using namespace System.Collections
using namespace System.Collections.Generic
using namespace Amazon.EC2.Model

function Show-Subnet
{
    [Alias('subnet_show')]
    [CmdletBinding(DefaultParameterSetName = 'None')]
    param(
        [parameter(Position = 0)]
        [validateSet('Default', 'Attributes', 'NetworkAcl', 'RouteTable')]
        [string]
        $View = 'Default',

        [Parameter(ParameterSetName = 'VpcId')]
        [ValidatePattern('^vpc-[0-9a-f]{17}$')]
        [string[]]
        $VpcId,

        [Parameter(ParameterSetName = 'VpcName')]
        [string[]]
        $VpcName,

        [Parameter()]
        [Filter[]]
        $Filter,

        [Parameter()]
        [ValidateSet('Vpc', 'AvailabilityZone', 'SubnetType', 'NetworkStack', 'RouteTable', 'NetworkAcl', $null)]
        [string]
        $GroupBy = 'Vpc',

        [Parameter()]
        [Int[]]
        $Sort,

        [Parameter()]
        [Int[]]
        $Exclude,

        [Parameter()]
        [switch]
        $PlainText,

        [Parameter()]
        [switch]
        $NoRowSeparator
    )

    # Use snake_case.
    $_view             = $View
    $_vpc_id           = $VpcId
    $_vpc_name         = $VpcName
    $_exclude          = $Exclude
    $_sort             = $Sort
    $_group_by         = $GroupBy
    $_filter           = $Filter
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    $_select_definition = @{
        ARecord = {
            New-Checkbox -PlainText:$_plain_text $_.PrivateDnsNameOptionsOnLaunch.EnableResourceNameDnsARecord
        }
        AAAARecord = {
            New-Checkbox -PlainText:$_plain_text $_.PrivateDnsNameOptionsOnLaunch.EnableResourceNameDnsAAAARecord
        }
        AutoAssignPublicIp = {
            New-Checkbox -PlainText:$_plain_text $_.MapPublicIpOnLaunch
        }
        AutoAssignIpv6Address = {
            New-Checkbox -PlainText:$_plain_text $_.AssignIpv6AddressOnCreation
        }
        AvailableIpv4Address = {
            New-NumberInfo $_.AvailableIpAddressCount
        }
        AvailabilityZone = {
            $_.AvailabilityZone
        }
        Dns64 = {
            New-Checkbox -PlainText:$_plain_text $_.EnableDns64
        }
        BlockPublicAccess = {
            $_.BlockPublicAccessStates.InternetGatewayBlockMode
        }
        HostnameType = {
            $_.PrivateDnsNameOptionsOnLaunch.HostnameType
        }
        Ipv4Cidr = {
            $_.CidrBlock | New-IPv4Subnet
        }
        Ipv6Cidr = {
            $_.Ipv6CidrBlockAssociationSet | Where-Object { $_.Ipv6CidrBlockState.State[0] -eq 'associated' } |
            Select-Object -ExpandProperty Ipv6CidrBlock | New-IPv6Subnet
        }
        Name = {
            $_.Tags | Where-Object Key -eq 'Name' | Select-Object -ExpandProperty Value
        }
        NetworkStack = {
            $_has_ipv4_cidr = $null -ne $_.CidrBlock
            $_has_ipv6_cidr = $null -ne $_.Ipv6CidrBlockAssociationSet -and
                ($_.Ipv6CidrBlockAssociationSet | Where-Object {
                    $_.Ipv6CidrBlockState.State[0] -eq 'associated'
                }).Count -gt 0

            if     (     $_has_ipv4_cidr -and      $_has_ipv6_cidr) { 'dual-stack' }
            elseif (     $_has_ipv4_cidr -and -not $_has_ipv6_cidr) { 'ipv4-only'  }
            elseif (-not $_has_ipv4_cidr -and      $_ipv6_cidr    ) { 'ipv6-only'  }
        }
        NetworkAcl = {
            $_acl_id = $_acl_id_lookup_by_subnet_id[$_.SubnetId]

            $_acl_dict[$_acl_id] | Get-ResourceString `
                -IdPropertyName 'NetworkAclId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
        RouteTable = {
            $_rt_id = $_rt_id_lookup_by_subnet_id[$_.SubnetId]

            $_rt_dict[$_rt_id] | Get-ResourceString `
                -IdPropertyName 'RouteTableId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
        RouteTableAssociationId = {
            $_rt_assoc_id_lookup_by_subnet_id[$_.SubnetId]
        }
        State = {
            $_.State
        }
        SubnetId = {
            $_.SubnetId
        }
        SubnetType = {
            $_rt_id = $_rt_id_lookup_by_subnet_id[$_.SubnetId]

            $_public_route_table_id_list -contains $_rt_id ? 'public' : 'private'
        }
        Vpc = {
            $_vpc = $_vpc_dict[$_.VpcId]
            $_vpc | Get-ResourceString -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
    }

    # VPC field will not be shown but used for grouping in Format-Column.
    $_view_definition = @{
        Default    = @(
            'Vpc', 'SubnetId', 'Name', 'State', 'AvailabilityZone', 'SubnetType',
            'Ipv4Cidr', 'Ipv6Cidr', 'AvailableIpv4Address', 'BlockPublicAccess'
        )
        Attributes = @(
            'Vpc', 'SubnetId', 'Name', 'SubnetType', 'Ipv4Cidr', 'Ipv6Cidr', 'HostnameType',
            'ARecord', 'AAAARecord', 'Dns64',  'AutoAssignPublicIp',  'AutoAssignIpv6Address'
        )
        RouteTable = @(
            'Vpc', 'SubnetId', 'Name', 'SubnetType', 'Ipv4Cidr', 'Ipv6Cidr', 'RouteTable', 'RouteTableAssociationId'
        )
        NetworkAcl = @(
            'Vpc', 'SubnetId', 'Name', 'SubnetType', 'Ipv4Cidr', 'Ipv6Cidr', 'NetworkAcl'
        )
    }

    # Route table lookup by subnet ID.
    $_rt_id_lookup_by_subnet_id = [Dictionary[string, string]]::new()

    # Route table association ID lookup by subnet ID
    $_rt_assoc_id_lookup_by_subnet_id = [Dictionary[string, string]]::new()

    # ACL lookup by subnet ID.
    $_acl_id_lookup_by_subnet_id = [Dictionary[string, string]]::new()

    # Main route table ID lookup by VPC ID.
    $_main_rt_id_lookup_by_vpc_id = [Dictionary[string, string]]::new()

    # Route table IDs lookup by VPC ID.
    $_rt_id_list_lookup_by_vpc_id = [Dictionary[string, string[]]]::new()

    # Dictionary to save VPC objects.
    $_vpc_dict = [Dictionary[string, Vpc]]::new()

    # Dictionary to save route tables objects.
    $_rt_dict = [Dictionary[string, RouteTable]]::new()

    # Dictionary to save ACL objects.
    $_acl_dict = [Dictionary[string, NetworkAcl]]::new()

    # This try block invokes all AWS APIs necessary to print out the subnet list.
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

        # Query Subnets.
        $_subnet_list = Get-EC2Subnet -Verbose:$false `
            -Filter $($_filter_list.Count -eq 0 ? $null : $_filter_list)

        # Exit early if there are no subnets to show.
        if (-not $_subnet_list) { return }

        # Query VPCs.
        $_vpc_list = Get-EC2Vpc -Verbose:$false -Filter @{
            Name   = 'vpc-id'
            Values = $_subnet_list.VpcId
        }

        # Query route tables.
        $_rt_list = Get-EC2RouteTable -Verbose:$false -Filter @{
            Name   = 'vpc-id'
            Values = $_subnet_list.VpcId
        }

        # Query Network ACLs
        $_acl_list = Get-EC2NetworkAcl -Verbose:$false -Filter @{
            Name   = 'vpc-id'
            Values = $_subnet_list.VpcId
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught error.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Filter out route tables that has default route to internet gateway.
    $_public_route_table_id_list
    $_public_route_table_id_list = $_rt_list | Where-Object {
        $_.Routes.GatewayId -like 'igw-*' -and
        (
            $_.Routes.DestinationCidrBlock -contains '0.0.0.0/0' -or
            $_.Routes.DestinationIpv6CidrBlock -contains '::/0'
        )
    } | Select-Object -expand RouteTableId

    # Process VPCs.
    foreach ($_this_vpc in $_vpc_list)
    {
        # save a copy of the VPC ID.
        $_this_vpc_id = $_this_vpc.VpcId

        # Put VPC in dictionary.
        $_vpc_dict[$_this_vpc_id] = $_this_vpc

        # filter out route tables in this VPC.
        $_this_vpc_rt_list = $_rt_list | Where-Object VpcId -eq $_this_vpc_id

        # filter out main route table of this VPC.
        $_this_vpc_main_rt = $_this_vpc_rt_list | Where-Object { $_.Associations.Main -contains $true }

        # Put VPC route table IDs in lookup hashtable.
        $_rt_id_list_lookup_by_vpc_id[$_this_vpc_id] = $_this_vpc_rt_list.RouteTableId

        # Put VPC main route table ID in lookup hashtable.
        $_main_rt_id_lookup_by_vpc_id[$_this_vpc_id] = $_this_vpc_main_rt.RouteTableId
    }

    # Process route tables.
    foreach ($_rt in $_rt_list)
    {
        # Put route table in dictionary.
        $_rt_dict[$_rt.RouteTableId] = $_rt
    }

    # Process route table associations
    foreach ($_rt_assoc in $_rt_list.Associations.Where( {-not [string]::IsNullOrEmpty($_.SubnetId)} ))
    {
        # Put route table association ID in dictionary to lookup by Subnet ID.
        $_rt_assoc_id_lookup_by_subnet_id[$_rt_assoc.SubnetId] = $_rt_assoc.RouteTableAssociationId
    }

    # Process ACLs
    foreach ($_acl in $_acl_list)
    {
        # Put ACL in dictionry.
        $_acl_dict[$_acl.NetworkAclId] = $_acl
    }

    # Process subnets - find their associated route tables.
    foreach ($_this_subnet in $_subnet_list)
    {
        # Save Subnet ID, VPC ID of this subnet.
        $_this_subnet_id     = $_this_subnet.SubnetId
        $_this_subnet_vpc_id = $_this_subnet.VpcId

        # Get all route table IDs in this VPC.
        $_this_subnet_vpc_rt_id_list = $_rt_id_list_lookup_by_vpc_id[$_this_subnet_vpc_id]

        # Process all the route table IDs in this VPC.
        foreach ($_rt_id in $_this_subnet_vpc_rt_id_list)
        {
            # Save this route table.
            $_rt = $null
            $_rt = $_rt_dict[$_rt_id]

            # Check if the current subnet is associated with this route table.
            if($_this_subnet_id -in $_rt.Associations.SubnetId)
            {
                # if yes - save the route table ID into the lookup hashtable.
                $_rt_id_lookup_by_subnet_id[$_this_subnet_id] = $_rt_id
                break
            }
        }

        # If no route table association was found for the current subnet..
        if(-not $_rt_id_lookup_by_subnet_id[$_this_subnet_id])
        {
            # Get the main route table ID in this VPC.
            $_this_subnet_vpc_main_rt_id = $_main_rt_id_lookup_by_vpc_id[$_this_subnet_vpc_id]

            # save the MAIN route table ID into the lookup hashtable.
            $_rt_id_lookup_by_subnet_id[$_this_subnet_id] = $_this_subnet_vpc_main_rt_id
        }
    }

    # Process subnets (find their associated ACLs).
    foreach($_this_subnet in $_subnet_list)
    {
        # Save Subnet ID of this subnet.
        $_this_subnet_id = $_this_subnet.SubnetId

        # Loop through each ACL.
        foreach($_acl in $_acl_list)
        {
            # Save a list of subnet ID accosicated with this ACL.
            $_this_acl_subnet_id_list = $_acl.Associations.SubnetId

            # Check if subnet is associated with this ACL.
            if($_this_subnet_id -in $_this_acl_subnet_id_list)
            {
                # If yes - save the ACL ID into the lookup hashtable.
                $_acl_id_lookup_by_subnet_id[$_this_subnet_id] = $_acl.NetworkAclId
                break
            }
        }
    }

    # Apply default sort order.
    if ($_group_by -eq 'Vpc' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(2, 1) # => Sort by Name, SubnetId
    }

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             $_view `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    # Print out the summary table.
    $_data = `
        $_subnet_list                |
        Select-Object $_select_list  |  # Initial columns based on selected view.
        Sort-Object   $_sort_list    |  # Sort before exclude.
        Select-Object $_project_list    # Takes into account exclued columns.

    if ($global:EnableHtmlOutput) {
        $_data | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_data | Format-Column -GroupBy $_group_by -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
    }
}