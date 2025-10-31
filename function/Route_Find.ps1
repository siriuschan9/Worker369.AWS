using namespace Worker369.Utility
using namespace System.Management.Automation

function Find-Route
{
    [CmdletBinding(DefaultParameterSetName = 'DefaultRouteTable')]
    [Alias('route_find')]
    param (
        [Parameter(ParameterSetName = 'RouteTableId', Mandatory)]
        [ValidatePattern('^rtb-[0-9a-f]{17}$', ErrorMessage = 'Invalid RouteTableId.')]
        [string]
        $RouteTableId,

        [Parameter(ParameterSetName = 'RouteTableName', Mandatory)]
        [string]
        $RouteTableName,

        [Parameter(Mandatory, Position = 0)]
        [ValidateScript(
            {
                $_ipv4_pattern = `
                    '^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}' + # 255.255.255.
                    '([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])' +         # 255
                    '(\/([0-9]|[1-2][0-9]|3[0-2]))?$'

                $_prefix_pattern = "[0-9]|[1-9][0-9]|1[0-1][0-9]|12[0-8]";
                $_hex_pattern    = "[0-9a-fA-F]"
                $_hextet_pattern = "$($_hex_pattern){1,4}"

                $_ipv6_0 = "($($_hextet_pattern):){7}$($_hextet_pattern)"
                $_ipv6_1 = "($($_hextet_pattern):){1,7}:"
                $_ipv6_2 = "($($_hextet_pattern):){1,6}(:$($_hextet_pattern)){1,1}"
                $_ipv6_3 = "($($_hextet_pattern):){1,5}(:$($_hextet_pattern)){1,2}"
                $_ipv6_4 = "($($_hextet_pattern):){1,4}(:$($_hextet_pattern)){1,3}"
                $_ipv6_5 = "($($_hextet_pattern):){1,3}(:$($_hextet_pattern)){1,4}"
                $_ipv6_6 = "($($_hextet_pattern):){1,2}(:$($_hextet_pattern)){1,5}"
                $_ipv6_7 = "($($_hextet_pattern):){1,1}(:$($_hextet_pattern)){1,6}"
                $_ipv6_8 = ":(:$($_hextet_pattern)){1,7}"
                $_ipv6_9 = "::"

                $_ip_pattern = '^(' +
                    $_ipv6_0 + '|' + $_ipv6_1 + '|' + $_ipv6_2 + '|' + $_ipv6_3 + '|' + $_ipv6_4 + '|' +
                    $_ipv6_5 + '|' + $_ipv6_6 + '|' + $_ipv6_7 + '|' + $_ipv6_8 + '|' + $_ipv6_9 + ')$'

                $_ipv6_pattern = $_ip_pattern.TrimEnd('$') + "(\/($($_prefix_pattern)))?$"

                if ($_ -match $_ipv4_pattern -or $_ -match $_ipv6_pattern) { $true }
                else {
                    throw [System.Management.Automation.ValidationMetadataException]::new("Invalid Destination.")
                }
            }
        )]
        [string]
        $Destination,

        [ValidateSet('IPVersion', 'Gateway', 'GatewayType', $null)]
        [string]
        $GroupBy = 'IPVersion',

        [Int[]]
        $Exclude,

        [switch]
        $PlainText
    )

    # For easy pick up.
    $_param_set = $PSCmdlet.ParameterSetName
    $_underline = [PSStyle]::Instance.Reverse
    $_reset     = [PSStyle]::Instance.Reset
    $_loopback4 = New-IPv4Subnet '127.0.0.0/8'
    $_loopback6 = New-IPv6Subnet '::1/128'

    # Use snake_case.
    $_rt_id      = $RouteTableId
    $_rt_name    = $RouteTableName
    $_dst        = $Destination
    $_group_by   = $GroupBy
    $_exclude    = $Exclude
    $_plain_text = $PlainText.IsPresent

    if ($_param_set -eq 'DefaultRouteTable')
    {
        $_default_rt = Get-DefaultRouteTable -Raw

        if (-not $_default_rt)
        {
            Write-Error (
                'Default Route Table has not been set. ' +
                'Default Route Table can be set using the ''Set-DefaultRouteTable'' cmdlet.' +
                'Otherwise, you must specify either -RouteTableId or -RouteTableId parameter.'
            )
            return
        }
        $_filter_name  = 'route-table-id'
        $_filter_value = $_default_rt.RouteTableId
    }
    else
    {
        $_filter_name  = $_param_set -eq 'RouteTableId' ? 'route-table-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'RouteTableId' ? $_rt_id : $_rt_name
    }

    # Try to query the route table first.
    try {
        $_rt_list = Get-EC2RouteTable -Verbose:$false -Filter @{
            Name   = $_filter_name
            Values = $_filter_value
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # If no route tables matched the filter value, exit early.
    if (-not $_rt_list)
    {
        Write-Error "No Route Tables were found for '$_filter_value'."
        return
    }

    # If multiple route tables matched the filter value, exit early.
    if ($_rt_list.Count -gt 1)
    {
        Write-Error "Multiple Route Tables were found for '$_filter_value'. It must match exactly one Route Table."
        return
    }

    # Save a reference to the filtered route table.
    $_rt = $_rt_list[0]

    # If there are no routes to show, exit early
    if (-not ($_route_list = $_rt.Routes)) { return }

    # Grab all IDs of prefix lists, internet gateways, vpc endpoints, ENIs and NAT gateways.
    $_pl_id_list   = $_route_list | Select-Object -ExpandProperty DestinationPrefixListId
    $_igw_id_list  = $_route_list | Where-Object GatewayId -like 'igw-*' | Select-Object -ExpandProperty GatewayId
    $_vpce_id_list = $_route_list | Where-Object GatewayId -like 'vpce-*'| Select-Object -ExpandProperty GatewayId
    $_pcx_id_list  = $_route_list | Select-Object -ExpandProperty VpcPeeringConnectionId
    $_eni_id_list  = $_route_list | Select-Object -ExpandProperty NetworkInterfaceId
    $_ngw_id_list  = $_route_list | Select-Object -ExpandProperty NatGatewayId

    # CIDR list lookup for prefix lists.
    $_pl_entries_lookup = [Hashtable]::new()

    try {
        if ($_pl_id_list)
        {
            Write-Verbose "Retrieving Prefix Lists."

            $_pl_lookup = Get-EC2ManagedPrefixList -Verbose:$false -Filter @{
                Name   = 'prefix-list-id'
                Values = $_pl_id_list
            } | Group-Object -AsHashTable PrefixListId

            foreach ($_pl_id in $_pl_id_list)
            {
                $_pl_cidr_list = `
                    Get-EC2ManagedPrefixListEntry -Verbose:$false -PrefixListId $_pl_id |
                    Select-Object -ExpandProperty Cidr

                $_pl_entries_lookup.Add($_pl_id, $_pl_cidr_list)
            }
        }

        if ($_igw_id_list)
        {
            Write-Verbose "Retrieving Internet Gateways."

            $_igw_lookup = Get-EC2InternetGateway -Verbose:$false -Filter @{
                Name   = 'internet-gateway-id'
                Values = $_igw_id_list
            } | Group-Object -AsHashTable InternetGatewayId
        }

        if ($_vpce_id_list)
        {
            Write-Verbose "Retrieving VPC Endpoints."

            $_vpce_lookup = Get-EC2VpcEndpoint -Verbose:$false -Filter @{
                Name   = 'vpc-endpoint-id'
                Values = $_vpce_id_list
            } | Group-Object -AsHashTable VpcEndpointId
        }

        if ($_ngw_id_list)
        {
            Write-Verbose "Retrieving NAT Gateways."

            $_ngw_lookup = Get-EC2NatGateway -Verbose:$false -Filter @{
                Name   = 'nat-gateway-id'
                Values = $_ngw_id_list
            } | Group-Object -AsHashTable NatGatewayId
        }

        if ($_pcx_id_list)
        {
            Write-Verbose "Retrieving VPC Peering Connections."

            $_pcx_lookup = Get-EC2VpcPeeringConnection  -Verbose:$false -Filter @{
                Name   = 'vpc-peering-connection-id'
                Values = $_pcx_id_list
            } | Group-Object -AsHashTable VpcPeeringConnectionId
        }

        if ($_eni_id_list)
        {
            Write-Verbose "Retrieving Network Interfaces."

            $_eni_lookup = Get-EC2NetworkInterface -Verbose:$false -Filter @{
                Name   = 'network-interface-id'
                Values = $_eni_id_list
            } | Group-Object -AsHashTable NetworkInterfaceId
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    $_custom_route_list = $_route_list | ForEach-Object {

        # Reset all route variables to null.
        $_ip_version            = $null
        $_status                = $null
        $_propagated            = $null
        $_origin                = $null
        $_destination           = $null
        $_gateway               = $null
        $_gateway_type          = $null
        $_cidr_list             = $null
        $_matched_result        = $null
        $_matched_prefix_length = -1    # Use this for finding out the longest prefix match

        # Fill up _origin, _propagated, _status and _destination
        $_origin      = $_.Origin
        $_propagated  = New-Checkbox -PlainText:$_plain_text ($_.Origin -eq 'EnableVgwRoutePropagation')
        $_status      = New-Checkbox -PlainText:$_plain_text -Description $_.State $($_.State -eq 'active')
        $_destination = $_.DestinationCidrBlock ?? $_.DestinationIpv6CidrBlock ?? $_.DestinationPrefixListId

        # Fill up _target_id.
        $_target_id = $_.GatewayId
        $_target_id = $_target_id ?? $_.NatGatewayId
        $_target_id = $_target_id ?? $_.EgressOnlyInternetGatewayId
        $_target_id = $_target_id ?? $_.TransitGatewayId
        $_target_id = $_target_id ?? $_.NetworkInterfaceId
        $_target_id = $_target_id ?? $_.InstanceId
        $_target_id = $_target_id ?? $_.VpcPeeringConnectionId
        $_target_id = $_target_id ?? $_.LocalGatewayId

        # Fill up _gateway and _gateway_type
        switch -Regex ($_target_id)
        {
            'local'
            {
                $_gateway_type = 'Local'
                $_gateway      = 'Connected'
            }
            'igw-[0-9a-f]{17}'
            {
                $_gateway_type = 'Internet Gateway'
                $_gateway      = $_igw_lookup[$_target_id] | Get-ResourceString `
                    -IdPropertyName 'InternetGatewayId' -TagPropertyName 'Tags' -PlainText:$_plain_text
            }
            'vpce-[0-9a-f]{17}'
            {
                $_gateway_type = 'VPC Endpoint'
                $_gateway      = $_vpce_lookup[$_target_id] | Get-ResourceString `
                    -IdPropertyName 'VpcEndpointId' -TagPropertyName 'Tags' -PlainText:$_plain_text
            }
            'nat-[0-9a-f]{17}'
            {
                $_gateway_type = 'NAT Gateway'
                $_gateway      = $_ngw_lookup[$_target_id] | Get-ResourceString `
                    -IdPropertyName 'NatGatewayId' -TagPropertyName 'Tags' -PlainText:$_plain_text
            }
            'eni-[0-9a-f]{17}'
            {
                $_gateway_type = 'Network Interface'
                $_gateway      = $_eni_lookup[$_target_id] | Get-ResourceString `
                    -IdPropertyName 'NetworkInterfaceId' -TagPropertyName 'Tags' -PlainText:$_plain_text
            }
            'pcx-[0-9a-f]{17}'
            {
                $_gateway_type = 'VPC Peering Connection'
                $_gateway      = $_pcx_lookup[$_target_id] | Get-ResourceString `
                    -IdPropertyName 'VpcPeeringConnectionId' -TagPropertyName 'Tags' -PlainText:$_plain_text
            }
            default
            {
                $_error_record = New-ErrorRecord `
                    -ErrorMessage "Gateway type for $_target_id has not been implemented." `
                    -ErrorId 'UnhandledGatewayType' `
                    -ErrorCategory NotImplemented

                $PSCmdlet.WriteError($_error_record)
            }
        }

        # Fill up _cidr_list and _ip_version.
        if ($_.DestinationCidrBlock)
        {
            $_cidr_list  = $_.DestinationCidrBlock | New-IPv4Subnet
            $_ip_version = 'IPv4'
        }
        elseif ($_.DestinationIpv6CidrBlock)
        {
            $_cidr_list  = $_.DestinationIpv6CidrBlock | New-IPv6Subnet
            $_ip_version = 'IPv6'
        }
        elseif ($_.DestinationPrefixListId)
        {
            $_pl         = $_pl_lookup[$_.DestinationPrefixListId]
            $_pl_entries = $_pl_entries_lookup[$_.DestinationPrefixListId]

            if ($_pl -and $_pl.AddressFamily -eq 'IPv4' -and $_pl_entries)
            {
                $_cidr_list  = $_pl_entries | New-IPv4Subnet | Sort-Object
                $_ip_version = 'IPv4'
            }

            if ($_pl -and $_pl.AddressFamily -eq 'IPv6' -and $_pl_entries)
            {
                $_cidr_list  = $_pl_entries | New-IPv6Subnet | Sort-Object
                $_ip_version = 'IPv6'
            }
        }
        else {
            $_error_record = New-ErrorRecord `
                -ErrorMessage "Unable to interpret destination for this route entry." `
                -ErrorId 'UnhandledDestinationPrefixType' `
                -ErrorCategory NotImplemented

            $PSCmdlet.WriteError($_error_record)
        }

        # IPv4 or IPv6 ? Longest Prefix Match or Exact Match ?
        switch -Regex ($_dst)
        {
            ([IPPattern]::IPv4Address) {

                $_cidr2 = New-IPv4Subnet "$_dst/32"
                $_predicate = {
                    param($_cidr1)
                    $_cidr1 -is [IPv4Subnet] `
                        ? ((Test-IPv4CidrOverlap $_cidr1 $_cidr2) -and -not (Test-IPv4CidrOverlap $_cidr2 $_loopback4))
                        : $false
                }.GetNewClosure()
            }
            ([IPPattern]::IPv6Address) {
                $_cidr2 = New-IPv6Subnet "$_dst/128"
                $_predicate = {
                    param($_cidr1)
                    $_cidr1 -is [IPv6Subnet] `
                        ? ((Test-IPv6CidrOverlap $_cidr1 $_cidr2) -and -not (Test-IPv6CidrOverlap $_cidr2 $_loopback6))
                        : $false
                }.GetNewClosure()
            }
            ([IPPattern]::IPv4Subnet) {
                $_cidr2 = New-IPv4Subnet $_dst
                $_predicate = { param($_cidr1) $_cidr1 -eq $_cidr2 }.GetNewClosure()
            }
            ([IPPattern]::IPv6Subnet) {
                $_cidr2 = New-IPv6Subnet $_dst
                $_predicate = { param($_cidr1) $_cidr1 -eq $_cidr2 }.GetNewClosure()
            }
            default {

            }
        }

        $_matched_result = foreach($_cidr in $_cidr_list)
        {
            $_this_is_matched = &$_predicate $_cidr
            $_this_is_matched ? "$_underline$_cidr$_reset" : "$_cidr"

            if ($_this_is_matched -and $_matched_prefix_length -lt $_cidr.PrefixLength) {
                $_matched_prefix_length = $_cidr.PrefixLength
            }
        }

        # Yield a PSCustomObject for this route entry.
        [PSCustomObject]@{
            IPVersion           = $_ip_version
            Status              = $_status
            Propagated          = $_propagated
            RouteOrigin         = $_origin
            Destination         = $_destination
            Gateway             = $_gateway
            GatewayType         = $_gateway_type
            ResolvedCidr        = $_matched_result         # This list will highlight the CIDR that is being matched.
            MatchedPrefixLength = $_matched_prefix_length
        }
    }

   # Grab the list of property names to print out.
    $_select_names = @(
        'IPVersion', 'Status', 'Propagated', 'RouteOrigin', 'Destination', 'Gateway', 'GatewayType', 'ResolvedCidr'
    )

    # If Group By is not in the select names, insert it to the select names.
    if ($_group_by -and $_group_by -notin $_select_names)
    {
        $_select_names = @($_group_by) + @($_select_names)
    }

    # Initialize property lists for select.
    $_select_list  = [List[object]]::new()

    # Build the select list.
    foreach ($_name in $_select_names)
    {
        $_select_list.Add($_name)
    }

    # Remove group from the projectable names. Exclude indexes are based on $_project_names.
    $_project_names = $_select_names | Where-Object { $_ -ne $_group_by }

    # Initialize property lists for project. Project list exclude indexes specified in the -Exclude parameter.
    $_project_list = [List[object]]::new()

    # Add the group property to the project list first.
    if ($_group_by -and $_group_by -in $_select_names)
    {
        $_project_list.Add($_group_by)
    }

    # Build the project list.
    for ($_i = 0; $_i -lt $_project_names.Length; $_i++)
    {
        if (($_i + 1) -notin $_exclude)
        {
            $_project_list.Add($_project_names[$_i])
        }
    }

    # Print out the matched route.
    $_custom_route_list | Where-Object MatchedPrefixLength -gt -1 | Sort-Object MatchedPrefixLength |
    Select-Object -Last 1 $_select_list |
    Select-Object $_project_list |
    Format-Column `
        -GroupBy $_group_by `
        -AlignLeft 'Status', 'Propagated' `
        -PlainText:$_plain_text
}