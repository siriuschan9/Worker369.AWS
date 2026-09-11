$_cmd_lookup = @{
    TransitGatewayId = @(
        'Show-TransitGatewayRouteTable'
    )
    TransitGatewayName = @(
        'Show-TransitGatewayRouteTable'
    )
    TransitGatewayRouteTableId = @(
        'Show-TransitGatewayRoute'
    )
    TransitGatewayRouteTableName = @(
        'Show-TransitGatewayRoute'
    )
}

# TransitGatewayId
Register-ArgumentCompleter -ParameterName 'TransitGatewayId' -CommandName $_cmd_lookup['TransitGatewayId'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_tgw_list = Get-EC2TransitGateway -Verbose:$false -Filter @{
        Name   = 'transit-gateway-id'
        Values = "$_word_to_complete*"
    }

    if (-not $_tgw_list) { return }

    $_align = `
        $_tgw_list.RouteTableId | Select-Object -ExpandProperty Length |
        Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    $_tgw_list | Get-HintItem -IdPropertyName 'TransitGatewayId' -TagPropertyName 'Tags' -Align $_align |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_.ResourceId,    # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# TransitGatewayName
Register-ArgumentCompleter -ParameterName 'TransitGatewayName' -CommandName $_cmd_lookup['TransitGatewayName'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_tgw_list = Get-EC2TransitGateway -Verbose:$false -Filter @{
        Name   = 'tag:Name'
        Values = "$_word_to_complete*"
    }

    if (-not $_tgw_list) { return }

    $_align = `
        $_tgw_list.TransitGatewayId | Select-Object -ExpandProperty Length |
        Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    $_tgw_list | Get-HintItem -IdPropertyName 'TransitGatewayId' -TagPropertyName 'Tags' -Align $_align |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_.ResourceId,    # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# TransitGatewayRouteTableId
Register-ArgumentCompleter -ParameterName 'TransitGatewayRouteTableId' -CommandName $_cmd_lookup['TransitGatewayRouteTableId'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_tgw_rt_list = Get-EC2TransitGatewayRouteTable -Verbose:$false -Filter @{
        Name   = 'transit-gateway-route-table-id'
        Values = "$_word_to_complete*"
    }

    if (-not $_tgw_rt_list) { return }

    $_align = `
        $_tgw_rt_list.RouteTableId | Select-Object -ExpandProperty Length |
        Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    $_tgw_rt_list | Get-HintItem -IdPropertyName 'TransitGatewayRouteTableId' -TagPropertyName 'Tags' -Align $_align |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_.ResourceId,    # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# TransitGatewayRouteTableName
Register-ArgumentCompleter -ParameterName 'TransitGatewayRouteTableName' -CommandName $_cmd_lookup['TransitGatewayRouteTableName'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    Get-EC2TransitGatewayRouteTable -Verbose:$false -Filter @{
        Name = 'tag:Name'
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