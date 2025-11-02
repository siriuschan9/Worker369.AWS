. $PSScriptRoot/Vpc.ps1

$_cmd_lookup = @{
    VpcPeeringConnectionId = @(
        'Rename-VpcPeering'
    )
    VpcPeeringConnectionId_Active = @(
        'Remove-VpcPeering', 'Enable-VpcPeeringDns', 'Disable-VpcPeeringDns'
    )
    VpcPeeringConnectionId_PendingAcceptance = @(
        'Approve-VpcPeering', 'Deny-VpcPeering'
    )
    VpcPeeringConnectionName = @(
        'Rename-VpcPeering'
    )
    VpcPeeringConnectionName_Active = @(
        'Remove-VpcPeering', 'Enable-VpcPeeringDns', 'Disable-VpcPeeringDns'
    )
    VpcPeeringConnectionName_PendingAcceptance = @(
        'Approve-VpcPeering', 'Deny-VpcPeering'
    )
    ThisVpcId = @(
        'New-VpcPeering'
    )
    OtherVpcId = @(
        'New-VpcPeering'
    )
    ThisVpcName = @(
        'New-VpcPeering'
    )
    OtherVpcName = @(
        'New-VpcPeering'
    )
}

$_script_lookup = @{

    # VpcPeeringConnectionId
    VpcPeeringConnectionId = {
        param(
            $_command_name,
            $_parameter_name,
            $_word_to_complete,
            $_command_ast,
            $_fake_bound_parameters
        )

        $_pcx_list = Get-EC2VpcPeeringConnection -Verbose:$false -Filter @{
            Name   = 'vpc-peering-connection-id'
            Values = "$_word_to_complete*"
        }

        if (-not $_pcx_list) { return }

        $_align = `
            $_pcx_list.VpcId | Select-Object -ExpandProperty Length |
            Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

        $_pcx_list | Get-HintItem -IdPropertyName 'VpcPeeringConnectionId' -TagPropertyName 'Tags' -Align $_align |
        Sort-Object | ForEach-Object {

            [System.Management.Automation.CompletionResult]::new(
                $_.ResourceId,    # completionText
                $_ ,              # listItemText
                'ParameterValue', # resultType
                $_                # toolTip
            )
        }
    }

    # VpcPeeringConnectionId - Filter out those with pending-acceptance status
    VpcPeeringConnectionId_Active = {
        param(
            $_command_name,
            $_parameter_name,
            $_word_to_complete,
            $_command_ast,
            $_fake_bound_parameters
        )

        $_pcx_list = Get-EC2VpcPeeringConnection -Verbose:$false -Filter @{
            Name   = 'status-code'
            Values = 'active'
        }, @{
            Name   = 'vpc-peering-connection-id'
            Values = "$_word_to_complete*"
        }

        if (-not $_pcx_list) { return }

        $_align = $_pcx_list.VpcId.Length | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

        $_pcx_list | Get-HintItem -IdPropertyName 'VpcPeeringConnectionId' -TagPropertyName 'Tags' -Align $_align |
        Sort-Object | ForEach-Object {

            [System.Management.Automation.CompletionResult]::new(
                $_.ResourceId,    # completionText
                $_ ,              # listItemText
                'ParameterValue', # resultType
                $_                # toolTip
            )
        }
    }

    # VpcPeeringConnectionId - Filter out those with pending-acceptance status
    VpcPeeringConnectionId_PendingAcceptance = {
        param(
            $_command_name,
            $_parameter_name,
            $_word_to_complete,
            $_command_ast,
            $_fake_bound_parameters
        )

        $_pcx_list = Get-EC2VpcPeeringConnection -Verbose:$false -Filter @{
            Name   = 'status-code'
            Values = 'pending-acceptance'
        }, @{
            Name   = 'vpc-peering-connection-id'
            Values = "$_word_to_complete*"
        }

        if (-not $_pcx_list) { return }

        $_align = $_pcx_list.VpcId.Length | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

        $_pcx_list | Get-HintItem -IdPropertyName 'VpcPeeringConnectionId' -TagPropertyName 'Tags' -Align $_align |
        Sort-Object | ForEach-Object {

            [System.Management.Automation.CompletionResult]::new(
                $_.ResourceId,    # completionText
                $_ ,              # listItemText
                'ParameterValue', # resultType
                $_                # toolTip
            )
        }
    }

    # VpcPeeringConnectionName
    VpcPeeringConnectionName = {
        param(
            $_command_name,
            $_parameter_name,
            $_word_to_complete,
            $_command_ast,
            $_fake_bound_parameters
        )

        Get-EC2VpcPeeringConnection -Verbose:$false -Filter @{
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

    # VpcPeeringConnectionName - Filter out those with pending-acceptance status
    VpcPeeringConnectionName_Active = {
        param(
            $_command_name,
            $_parameter_name,
            $_word_to_complete,
            $_command_ast,
            $_fake_bound_parameters
        )

        Get-EC2VpcPeeringConnection -Verbose:$false -Filter @{
            Name   = 'status-code'
            Values = 'active'
        }, @{
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

    # VpcPeeringConnectionName - Filter out those with pending-acceptance status
    VpcPeeringConnectionName_PendingAcceptance = {
        param(
            $_command_name,
            $_parameter_name,
            $_word_to_complete,
            $_command_ast,
            $_fake_bound_parameters
        )

        Get-EC2VpcPeeringConnection -Verbose:$false -Filter @{
            Name   = 'status-code'
            Values = 'pending-acceptance'
        }, @{
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

    # ThisVpcId
    ThisVpcId = {
        param(
            $_command_name,
            $_parameter_name,
            $_word_to_complete,
            $_command_ast,
            $_fake_bound_parameters
        )

        $_other = $_fake_bound_parameters['OtherVpcId']

        $_vpc_list = Get-EC2Vpc -Verbose:$false -Filter @{
            Name = 'vpc-id'
            Values = "$_word_to_complete*"
        } | Where-Object VpcId -ne $_other

        if (-not $_vpc_list) { return }

        $_align = $_vpc_list.VpcId.Length | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

        $_vpc_list | Get-HintItem -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -Align $_align |
        Sort-Object | ForEach-Object {

            [System.Management.Automation.CompletionResult]::new(
                $_.ResourceId,    # completionText
                $_ ,              # listItemText
                'ParameterValue', # resultType
                $_                # toolTip
            )
        }
    }

    # OtherVpcId
    OtherVpcId = {
        param(
            $_command_name,
            $_parameter_name,
            $_word_to_complete,
            $_command_ast,
            $_fake_bound_parameters
        )

        $_this = $_fake_bound_parameters['ThisVpcId']

        $_vpc_list = Get-EC2Vpc -Verbose:$false -Filter @{
            Name   = 'vpc-id'
            Values = "$_word_to_complete*"
        } | Where-Object VpcId -ne $_this

        if (-not $_vpc_list) { return }

        $_align = $_vpc_list.VpcId.Length | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

        $_vpc_list | Get-HintItem -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -Align $_align |
        Sort-Object | ForEach-Object {

            [System.Management.Automation.CompletionResult]::new(
                $_.ResourceId,    # completionText
                $_ ,              # listItemText
                'ParameterValue', # resultType
                $_                # toolTip
            )
        }
    }

    # ThisVpcName
    ThisVpcName = {
        param(
            $_command_name,
            $_parameter_name,
            $_word_to_complete,
            $_command_ast,
            $_fake_bound_parameters
        )

        $_other = $_fake_bound_parameters['OtherVpcName']

        Get-EC2Vpc -Verbose:$false -Filter @{
            Name   = 'tag:Name'
            Values = "$_word_to_complete*"
        } |
        Select-Object -ExpandProperty Tags | Where-Object Key -eq 'Name' |
        Select-Object -Unique -ExpandProperty Value | Where-Object { $_ -ne $_other} |
        Sort-Object | ForEach-Object {

            [System.Management.Automation.CompletionResult]::new(
                $_,               # completionText
                $_,               # listItemText
                'ParameterValue', # resultType
                $_                # toolTip
            )
        }
    }

    # OtherVpcName
    OtherVpcName = {
        param(
            $_command_name,
            $_parameter_name,
            $_word_to_complete,
            $_command_ast,
            $_fake_bound_parameters
        )

        $_this = $_fake_bound_parameters['ThisVpcName']

        Get-EC2Vpc -Verbose:$false -Filter @{
            Name   = 'tag:Name'
            Values = "$_word_to_complete*"
        } |
        Select-Object -ExpandProperty Tags | Where-Object Key -eq 'Name' |
        Select-Object -Unique -ExpandProperty Value | Where-Object { $_ -ne $_this} |
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

# VpcId
Register-ArgumentCompleter `
    -CommandName $_cmd_lookup['ThisVpcId'] `
    -ParameterName 'ThisVpcId' `
    -ScriptBlock $_script_lookup['ThisVpcId']

Register-ArgumentCompleter `
    -CommandName $_cmd_lookup['OtherVpcId'] `
    -ParameterName 'OtherVpcId' `
    -ScriptBlock $_script_lookup['OtherVpcId']

# VpcName
Register-ArgumentCompleter `
    -CommandName $_cmd_lookup['ThisVpcName'] `
    -ParameterName 'ThisVpcName' `
    -ScriptBlock $_script_lookup['ThisVpcName']

Register-ArgumentCompleter `
    -CommandName $_cmd_lookup['OtherVpcName'] `
    -ParameterName 'OtherVpcName' `
    -ScriptBlock $_script_lookup['OtherVpcName']

# VpcPeeringConnectionId
Register-ArgumentCompleter `
    -CommandName $_cmd_lookup['VpcPeeringConnectionId'] `
    -ParameterName 'VpcPeeringConnectionId' `
    -ScriptBlock $_script_lookup['VpcPeeringConnectionId']

Register-ArgumentCompleter `
    -CommandName $_cmd_lookup['VpcPeeringConnectionId_Active'] `
    -ParameterName 'VpcPeeringConnectionId' `
    -ScriptBlock $_script_lookup['VpcPeeringConnectionId_Active']

Register-ArgumentCompleter `
    -CommandName $_cmd_lookup['VpcPeeringConnectionId_PendingAcceptance'] `
    -ParameterName 'VpcPeeringConnectionId' `
    -ScriptBlock $_script_lookup['VpcPeeringConnectionId_PendingAcceptance']

# VpcPeeringConnectionName
Register-ArgumentCompleter `
    -CommandName $_cmd_lookup['VpcPeeringConnectionName'] `
    -ParameterName 'VpcPeeringConnectionName' `
    -ScriptBlock $_script_lookup['VpcPeeringConnectionName']

Register-ArgumentCompleter `
    -CommandName $_cmd_lookup['VpcPeeringConnectionName_Active'] `
    -ParameterName 'VpcPeeringConnectionName' `
    -ScriptBlock $_script_lookup['VpcPeeringConnectionName_Active']

Register-ArgumentCompleter `
    -CommandName $_cmd_lookup['VpcPeeringConnectionName_PendingAcceptance'] `
    -ParameterName 'VpcPeeringConnectionName' `
    -ScriptBlock $_script_lookup['VpcPeeringConnectionName_PendingAcceptance']

# pending-acceptance | failed | expired | provisioning | active | deleting | deleted | rejected