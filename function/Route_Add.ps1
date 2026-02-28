using namespace Worker369.Utility

function Add-Route
{
    [CmdletBinding(DefaultParameterSetName = 'DefaultRouteTable', SupportsShouldProcess)]
    [Alias('route_add')]
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
        $Destination,

        [Parameter(Mandatory, Position = 1)]
        [string]
        $Gateway
    )

    # For easy pick up.
    $_param_set = $PSCmdlet.ParameterSetName

    # Use snake_case.
    $_rt_id   = $RouteTableId
    $_rt_name = $RouteTableName
    $_dst     = $Destination
    $_gw      = $Gateway

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

    # Prepare params for New-EC2Route.
    $_add_route_params = @{
        Verbose      = $false
        RouteTableId = $_rt.RouteTableId
    }

    # Declare output parameters first.
    $_ipv4_cidr = $null
    $_ipv6_cidr = $null

    # Add the relevant Destination parameter to the params.
    if ([IPv4Subnet]::TryParse($_dst, [ref]$_ipv4_cidr))
    {
        $_add_route_params.Add('DestinationCidrBlock', $_ipv4_cidr)
    }
    elseif ([IPv6Subnet]::TryParse($_dst, [ref]$_ipv6_cidr))
    {
        $_add_route_params.Add('DestinationIpv6CidrBlock', $_ipv6_cidr)
    }
    elseif ($_dst -match '^pl-([0-9a-f]{8}|[0-9-a-f]{17})$')
    {
        $_add_route_params.Add('DestinationPrefixListId', $_dst)
    }

    # Add the relevant Gateway parameter to the params, and
    # Generate a friendly string for the Gateway.
    try{
        switch -Regex ($_gw)
        {
            # Internet Gateway
            '^igw-[0-9-a-f]{17}$' {
                $_add_route_params.Add('GatewayId', $_gw)
                $_format_gw = Get-EC2InternetGateway -Verbose:$false $_gw | Get-ResourceString `
                    -IdPropertyName 'InternetGatewayId' `
                    -TagPropertyName 'Tags' `
                    -StringFormat IdAndName -PlainText
            }
            # Virtual Private Gateway
            '^vgw-[0-9-a-f]{17}$' {
                $_add_route_params.Add('GatewayId', $_gw)
                $_format_gw = Get-EC2VpnGateway -Verbose:$false $_gw | Get-ResourceString `
                    -IdPropertyName 'VpnGatewayId' `
                    -TagPropertyName 'Tags' `
                    -StringFormat IdAndName -PlainText
            }
            # VPC Peering Connection
            '^pcx-[0-9-a-f]{17}$' {
                $_add_route_params.Add('VpcPeeringConnectionId', $_gw)
                $_format_gw = Get-EC2VpcPeeringConnection -Verbose:$false $_gw| Get-ResourceString `
                    -IdPropertyName 'VpcPeeringConnectionId' `
                    -TagPropertyName 'Tags' `
                    -StringFormat IdAndName -PlainText
            }
            # NAT Gateway
            '^nat-[0-9-a-f]{17}$' {
                $_add_route_params.Add('NatGatewayId', $_gw)
                $_format_gw = Get-EC2NatGateway -Verbose:$false $_gw | Get-ResourceString `
                    -IdPropertyName 'NatGatewayId' `
                    -TagPropertyName 'Tags' `
                    -StringFormat IdAndName -PlainText
            }
            # Transit Gateway
            '^tgw-[0-9-a-f]{17}$' {
                $_add_route_params.Add('TransitGatewayId', $_gw)
                $_format_gw = Get-EC2TransitGateway -Verbose:$false -TransitGatewayId $_gw | Get-ResourceString `
                    -IdPropertyName 'TransitGatewayId' `
                    -TagPropertyName 'Tags' `
                    -StringFormat IdAndName -PlainText
            }
            # Network Interface
            '^eni-[0-9-a-f]{17}$' {
                $_add_route_params.Add('NetworkInterfaceId', $_gw)
                $_format_gw = Get-EC2NetworkInterface -Verbose:$false $_gw | Get-ResourceString `
                    -IdPropertyName 'NetworkInterfaceId' `
                    -TagPropertyName 'Tags' `
                    -StringFormat IdAndName -PlainText
            }
            # EC2 Instance
            '^i-[0-9-a-f]{17}$' {
                $_add_route_params.Add('InstanceId', $_gw)
                $_format_gw = Get-EC2Internce -Select Reservations.Instances -Verbose:$false $_gw | Get-ResourceString `
                    -IdPropertyName 'InstanceId' `
                    -TagPropertyName 'Tags' `
                    -StringFormat IdAndName -PlainText
            }
            # VPC Endpoint
            '^vpce-[0-9-a-f]{17}$' {
                $_add_route_params.Add('VpcEndpointId', $_gw)
                $_format_gw = Get-EC2VpcEndpoint -Verbose:$false $_gw | Get-ResourceString `
                    -IdPropertyName 'VpcEndpointId' `
                    -TagPropertyName 'Tags' `
                    -StringFormat IdAndName -PlainText
            }
            default {
                $_error_record = New-ErrorRecord `
                    -ErrorMessage 'Invalid Gateway.' `
                    -ErrorId 'InvalidGateway' `
                    -ErrorCategory InvalidArgument
                $PSCmdlet.ThrowTerminatingError($_error_record)
            }
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught error.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Generate a friendly display string for the Route Table.
    $_format_rt = $_rt | Get-ResourceString `
        -IdPropertyName 'RouteTableId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

    if ($PSCmdlet.ShouldProcess($_format_rt, "Add route to $_dst via $_format_gw"))
    {
        try {
            $_is_s3_vpce = Get-EC2VpcEndpoint -Verbose:$false -Filter @{
                Name = 'vpc-endpoint-id'; Values = $_gw
            }, @{
                Name = 'service-name'; Values = "com.amazonaws.$(Get-DefaultAWSRegion).s3"
            }

            $_is_dynamodb_vpce = Get-EC2VpcEndpoint -Verbose:$false -Filter @{
                Name = 'vpc-endpoint-id'; Values = $_gw
            }, @{
                Name = 'service-name'; Values = "com.amazonaws.$(Get-DefaultAWSRegion).dynamodb"
            }

            if ($_is_s3_vpce) {
                Edit-EC2VpcEndpoint -Verbose:$false -AddRouteTableId $_rt.RouteTableId $_is_s3_vpce.VpcEndpointId
            }
            elseif ($_is_dynamodb_vpce) {
                Edit-EC2VpcEndpoint -Verbose:$false -AddRouteTableId $_rt.RouteTableId $_is_dynamodb_vpce.VpcEndpointId
            }
            else {
                $_result = New-EC2Route @_add_route_params

                if ($_result) { Write-Message -Output "|- $_dst via $_format_gw on $_format_rt." }
            }
        } catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Re-throw caught error.
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}