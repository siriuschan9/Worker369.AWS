using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.Management.Automation
using namespace Amazon.EC2.Model

function Show-Route
{
    [CmdletBinding(DefaultParameterSetName = 'RouteTableName')]
    [Alias('route_show')]
    param (
        [Parameter(ParameterSetName = 'RouteTableId')]
        [ValidatePattern('^rtb-[0-9a-f]{17}$', ErrorMessage = 'Invalid RouteTableId.')]
        [string]
        $RouteTableId = $script:DefaultRouteTable,

        [Parameter(ParameterSetName = 'RouteTableName', Position = 0)]
        [string]
        $RouteTableName,

        [ValidateSet('IPv4', 'IPv6', 'Both')]
        [string]
        $IPVersion = 'Both',

        [ValidateSet('IPVersion', 'Gateway', 'GatewayType', $null)]
        [string]
        $GroupBy = 'IPVersion',

        [Int[]]
        $Sort,

        [Int[]]
        $Exclude,

        [switch]
        $Simple,

        [switch]
        $PlainText,

        [switch]
        $NoRowSeparator
    )

    # For easy pick up.
    $_param_set = $PSCmdlet.ParameterSetName

    # Use snake_case.
    $_rt_id            = $RouteTableId
    $_rt_name          = $RouteTableName
    $_show_ip_version  = $IPVersion
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_simple           = $Simple.IsPresent
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    # Apply default sort order.
    if (
        -not $PSBoundParameters.Keys.Contains('GroupBy') -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(-1, 5, 4)      # Sort by Status, Gateway, Destination
    }

    if ($_simple)
    {
        $_sort    = @(-1, 5, 4)   # Ignore -Sort when -Simple is activated.
        $_exclude = @(2, 3, 6, 7) # Show Status, Destination and Gateway only.
    }

    # Configure the filter to query the Route Table.
    if (
        -not $PSBoundParameters.ContainsKey('RouteTableId') -and
        -not $PSBoundParameters.ContainsKey('RouteTableName')
    ) {
        $_default_rt = Get-DefaultRouteTable -Raw

        if (-not $_default_rt)
        {
            Write-Error (
                'Default Route Table has not been set. ' +
                'You can only use this cmdlet with no parameters when ' +
                'Default Route Table can be set using the ''Set-DefaultRouteTable'' cmdlet.'
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

    # Try to query the route table.
    try {
        Write-Verbose "Retrieving Route Table."
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

    # If there are no routes to show, exit early.
    if (-not ($_route_list = $_rt.Routes)) { return }

    # Grab all IDs of prefix list and gateway resources.
    $_pl_id_list   = $_route_list | Select-Object -ExpandProperty DestinationPrefixListId
    $_igw_id_list  = $_route_list | Where-Object GatewayId -like 'igw-*' | Select-Object -ExpandProperty GatewayId
    $_vpce_id_list = $_route_list | Where-Object GatewayId -like 'vpce-*'| Select-Object -ExpandProperty GatewayId
    $_ngw_id_list  = $_route_list | Select-Object -ExpandProperty NatGatewayId
    $_tgw_id_list  = $_route_list | Select-Object -ExpandProperty TransitGatewayId
    $_pcx_id_list  = $_route_list | Select-Object -ExpandProperty VpcPeeringConnectionId
    $_eni_id_list  = $_route_list | Select-Object -ExpandProperty NetworkInterfaceId

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

        if ($_tgw_id_list)
        {
            Write-Verbose "Retrieving Transit Gateways."

            $_tgw_lookup = Get-EC2TransitGateway -Verbose:$false -Filter @{
                Name   = 'transit-gateway-id'
                Values = $_tgw_id_list
            } | Group-Object -AsHashTable TransitGatewayId
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
        $_ip_version   = $null
        $_status       = $null
        $_propagated   = $null
        $_origin       = $null
        $_destination  = $null
        $_gateway      = $null
        $_gateway_type = $null
        $_cidr_list    = $null

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
            'tgw-[0-9a-f]{17}'
            {
                $_gateway_type = 'Transit Gateway'
                $_gateway      = $_tgw_lookup[$_target_id] | Get-ResourceString `
                    -IdPropertyName 'TransitGatewayId' -TagPropertyName 'Tags' -PlainText:$_plain_text
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

        # Yield a PSCustomObject for this route entry.
        [PSCustomObject]@{
            IPVersion    = $_ip_version
            Status       = $_status
            Propagated   = $_propagated
            RouteOrigin  = $_origin
            Destination  = $_destination
            Gateway      = $_gateway
            GatewayType  = $_gateway_type
            ResolvedCidr = $_cidr_list
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

    # Initialize property lists for select > sort > project (exclude).
    $_select_list  = [List[object]]::new()
    $_sort_list    = [List[object]]::new()
    $_project_list = [List[object]]::new()

    # Build the select list.
    foreach ($_name in $_select_names)
    {
        $_select_list.Add($_name)
    }

    # Add group to sort list.
    if($_group_by -and $_group_by -in $_select_names)
    {
        $_sort_list.Add(
                @{
                    Expression = $_group_by;
                    Descending = $false
                }
        ) | Out-Null
    }

    # Remove group from the sortable names. Sort indexes are based on $_sort_names.
    $_sort_names = $_select_names | Where-Object { $_ -ne $_group_by }

    # Build the sort list.
    for($_i = 0 ; $_i -lt $_sort.Length ; $_i++)
    {
        # Column number is 1-based. Column index is 0-based
        $_sort_index = [Math]::Abs($_sort[$_i]) - 1

        # Get the column name
        $_sort_name = $_sort_names[$_sort_index]

        # Get ascending or descending
        $_descending = $($_sort[$_i] -lt 0)

        $_sort_list.Add(
            @{
                Expression = "$_sort_name"
                Descending = $_descending
            }
        )
    }

    # Remove group from the projectable names. Exclude indexes are based on $_project_names.
    $_project_names = $_select_names | Where-Object { $_ -ne $_group_by }

    # Add the group property to the project list first.
    if ($_group_by -and $_group_by -in $_select_names)
    {
        $_project_list.Add($_group_by)
    }

    # For easy pick up.
    $_dim   = [PSStyle]::Instance.Dim
    $_reset = [PSStyle]::Instance.Reset

    # Add all properties not excluded to the project list.
    for ($_i = 0 ; $_i -lt $_project_names.Length; $_i++)
    {
        if (($_i + 1) -notin $_exclude)
        {
            $_project_name = $_project_names[$_i] -as [string]

            $_project_list.Add(
                @{
                    Name = $_project_name
                    Expression = {
                        $_.Status.IsChecked `
                            ? $_.$_project_name
                            : $_plain_text ? $_.$_project_name : "$_dim$($_.$_project_name | Remove-PSStyle)$_reset"
                    }.GetNewClosure()
                }
            )
        }
    }

    # Define Where-Object predicate to filter routes on IP version.
    switch ($_show_ip_version)
    {
        'Both'  { $_ip_version_filter = { $true } }
        'IPv4'  { $_ip_version_filter = { $_.IPVersion -eq 'IPv4' } }
        'IPv6'  { $_ip_version_filter = { $_.IPVersion -eq 'IPv6' } }
        default { $_ip_version_filter = { $true } }
    }

    # Print out the summary table.
    $_custom_route_list               |
    Where-Object  $_ip_version_filter |
    Select-Object $_select_list       |
    Sort-Object   $_sort_list         |
    Select-Object $_project_list      |
    Format-Column `
        -GroupBy $_group_by `
        -AlignLeft 'Status', 'Propagated' `
        -PlainText:$_plain_text `
        -NoRowSeparator:$_no_row_separator
}
# State: Active | Blackhole | Filtered