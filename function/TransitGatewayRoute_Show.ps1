function Show-TransitGatewayRoute
{
    [CmdletBinding(DefaultParameterSetName = 'TransitGatewayRouteTableName')]
    [Alias('tgw_route_show')]
    param (
        [Parameter(ParameterSetName = 'TransitGatewayRouteTableId')]
        [string]
        $TransitGatewayRouteTableId,

        [Parameter(ParameterSetName = 'TransitGatewayRouteTableName', Position = 0)]
        [string]
        $TransitGatewayRouteTableName,

        [ValidateSet('IPv4', 'IPv6', 'Both')]
        [string]
        $IPVersion = 'Both',

        [ValidateSet('IPVersion', 'NextHop', 'State', 'Type', 'Destination', $null)]
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
    $_trt_id           = $TransitGatewayRouteTableId
    $_trt_name         = $TransitGatewayRouteTableName
    $_show_ip_version  = $IPVersion
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    $_view = 'Default'

    # Apply default sort order.
    if (
        -not $PSBoundParameters.Keys.Contains('GroupBy') -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(-1, 5, 4)      # Sort by State, Gateway, Destination
    }

    $_select_definition = @{
        IPVersion = {
            switch ($_.DestinationCidrBlock)
            {
                {Test-IsValidIPv4 $_} { 'IPv4' }
                {Test-IsValidIPv6 $_} { 'IPv6' }
                default               { ''     }
            }
        }
        State = {
            $_state = $_.State
            New-Checkbox -PlainText:$_plain_text -Descriptio $_state ($_state -eq 'active')
        }
        Type = {
            $_.Type
        }
        Destination = {
            switch ($_.DestinationCidrBlock)
            {
                {Test-IsValidIPv4 $_} { New-IPv4Subnet $_ }
                {Test-IsValidIPv6 $_} { New-IPv6Subnet $_ }
                default               { $null             }
            }
        }
        NextHop = {
            $_.TransitGatewayAttachments.ResourceId
        }
    }

    $_view_definition = @{
        Default = @(
            'IPVersion', 'State', 'Type', 'Destination', 'NextHop'
        )
    }

    # Configure the filter to query the Transit Gatwway Route Table.
    if (
        -not $PSBoundParameters.ContainsKey('TransitGatewayRouteTableId') -and
        -not $PSBoundParameters.ContainsKey('TransitGatewayRouteTableName')
    ) {
        # $_default_trt = Get-DefaultRouteTable -Raw

        # if (-not $_default_trt)
        # {
        #     Write-Error (
        #         'Default Transit Gateway Route Table has not been set. ' +
        #         'You can only use this cmdlet with no parameters when ' +
        #         'Default Route Table can be set using the ''Set-DefaultTgwRouteTable'' cmdlet.'
        #     )
        #     return
        # }
        # $_filter_name  = 'transit-gateway-route-table-id'
        # $_filter_value = $_default_trt.TransitGatewayRouteTableId
    }
    else
    {
        $_filter_name  = $_param_set -eq 'TransitGatewayRouteTableId' ? 'transit-gateway-route-table-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'TransitGatewayRouteTableId' ? $_trt_id : $_trt_name
    }

    # Try to query the route table.
    try {
        Write-Verbose "Retrieving Transit Gateway Route Table."
        $_trt_list = Get-EC2TransitGatewayRouteTable -Verbose:$false -Filter @{
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
    if (-not $_trt_list)
    {
        Write-Error "No Transit Gateway Route Tables were found for '$_filter_value'."
        return
    }

    # If multiple route tables matched the filter value, exit early.
    if ($_trt_list.Count -gt 1)
    {
        Write-Error (
            "Multiple Transit Gateway Route Tables were found for '$_filter_value'." + 
            "It must match exactly one Route Table."
        )
        return
    }

    # Save a reference to the filtered route table.
    $_trt = $_trt_list[0]
    
    # Fetch the routes in this route table.
    try {
        $_route_list = `
            Search-EC2TransitGatewayRoute -Verbose:$false -Filter @{Name='type';Values=@('propagated', 'static')} -TransitGatewayRouteTableId $_trt.TransitGatewayRouteTableId | 
            Select-Object -ExpandProperty Routes
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_) 
    }

    # If there are no routes to show, exit early.
    if (-not $_route_list) { return }

    # Define Where-Object predicate to filter routes on IP version.
    switch ($_show_ip_version)
    {
        'Both'  { $_ip_version_filter = { $true } }
        'IPv4'  { $_ip_version_filter = { $_.IPVersion -eq 'IPv4' } }
        'IPv6'  { $_ip_version_filter = { $_.IPVersion -eq 'IPv6' } }
        default { $_ip_version_filter = { $true } }
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
    $_output = $_route_list `
        | Select-Object $_select_list `
        | Where-Object $_ip_version_filter `
        | Sort-Object $_sort_list `
        | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column `
            -GroupBy $_group_by `
            -PlainText:$_plain_text `
            -NoRowSeparator:$_no_row_separator `
            -AlignLeft State
    }
}