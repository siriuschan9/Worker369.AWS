function Remove-Route
{
    [CmdletBinding(DefaultParameterSetName = 'DefaultRouteTable', SupportsShouldProcess)]
    [Alias('route_rm')]
    param (
        [Parameter(ParameterSetName = 'RouteTableId', Mandatory)]
        [ValidatePattern('^rtb-[0-9a-f]{17}$', ErrorMessage = 'Invalid RouteTableId.')]
        [string]
        $RouteTableId,

        [Parameter(ParameterSetName = 'RouteTableName', Mandatory)]
        [string]
        $RouteTableName,

        [Parameter(Mandatory, Position = 0)]
        [string]
        $Destination
    )

    # For easy pick up.
    $_param_set = $PSCmdlet.ParameterSetName

    # Use snake_case.
    $_rt_id   = $RouteTableId
    $_rt_name = $RouteTableName
    $_dst     = $Destination

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

    # Save a reference to the route list.
    $_routes = $_rt.Routes

    $_dst_ipv4 = $_routes | Select-Object -ExpandProperty DestinationCidrBlock
    $_dst_ipv6 = $_routes | Select-Object -ExpandProperty DestinationIpv6CidrBlock
    $_dst_pl   = $_routes | Select-Object -ExpandProperty DestinationPrefixListId

    # Use splatting so that we can build the parameter list dynamically.
    $_remove_route_params = @{
        Verbose      = $false
        RouteTableId = $_rt.RouteTableId
    }

    # Add the relevant destination parameter, and find that route to remove.
    if ($_dst -in $_dst_ipv4) {
        $_remove_route_params.Add('DestinationCidrBlock', $_dst)
        $_route = $_routes | Where-Object DestinationCidrBlock -eq $_dst
    }
    elseif ($_dst -in $_dst_ipv6) {
        $_remove_route_params.Add('DestinationIpv6CidrBlock', $_dst)
        $_route = $_routes | Where-Object DestinationIpv6CidrBlock -eq $_dst
    }
    elseif ($_dst -in $_dst_pl) {
        $_remove_route_params.Add('DestinationPrefixListId', $_dst)
        $_route = $_routes | Where-Object DestinationPrefixListId -eq $_dst
    }
    else {
        Write-Error "Destination '$($_dst)' is not found in '$($_rt.RouteTableId)'."
        return
    }

    [System.Diagnostics.Debug]::Assert($_route -and $_route.Count -eq 1)

    # Generate a friendly display string for the Route Table.
    $_format_rt = $_rt | Get-ResourceString `
        -IdPropertyName 'RouteTableId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

    if ($PSCmdlet.ShouldProcess($_format_rt, "Remove route to $_dst"))
    {
        try {
            # Check if the gateway is a VPC Endpoint.
            $_vpce = Get-EC2VpcEndpoint -Verbose:$false -Filter @{
                Name   = 'vpc-endpoint-id'
                Values = $_route.GatewayId
            }

            # If the gateway is a VPC Endpoint, we need to remove this route using Edit-EC2VpcEndpoint.
            if ($_vpce) {
                Edit-EC2VpcEndpoint -Verbose:$false -RemoveRouteTableId $_rt.RouteTableId $_vpce.VpcEndpointId
            }
            else {
                Remove-EC2Route @_remove_route_params
            }

        } catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Re-throw caught error.
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}