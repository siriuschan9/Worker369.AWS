$_cmd_lookup = @{

    InternetGatewayId = @(
        'Rename-InternetGateway', 'Remove-InternetGateway', 'Mount-InternetGateway', 'Dismount-InternetGateway'
    )

    InternetGatewayName = @(
        'Rename-InternetGateway', 'Remove-InternetGateway', 'Mount-InternetGateway', 'Dismount-InternetGateway'
    )
}

# InternetGatewayId
Register-ArgumentCompleter `
    -ParameterName 'InternetGatewayId' -CommandName $_cmd_lookup['InternetGatewayId'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_igw_list = Get-EC2InternetGateway -Verbose:$false -Filter @{
        Name   = 'internet-gateway-id'
        Values = "$_word_to_complete*"
    }

    if (-not $_igw_list) { return }

    $_align = `
        $_igw_list.InternetGatewayId | Select-Object -ExpandProperty Length |
        Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    $_igw_list | Get-HintItem -IdPropertyName 'InternetGatewayId' -TagPropertyName 'Tags' -Align $_align |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_.ResourceId,    # completionText
            $_ ,              # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# InternetGatewayName
Register-ArgumentCompleter `
    -ParameterName 'InternetGatewayName' -CommandName $_cmd_lookup['InternetGatewayName'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    Get-EC2InternetGateway -Verbose:$false -Filter @{
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