$_cmd_lookup = @{
    GroupId = @(
        'New-Eni.ps1'
    )
    GroupName = @(
        'New-Eni.ps1'
    )
    SubnetId = @(
        'New-Eni.ps1'
    )
    SubnetName = @(
        'New-Eni.ps1'
    )
}

# TargetVersion
Register-ArgumentCompleter -ParameterName 'SubnetId' -CommandName $_cmd_lookup['SubnetId'] -ScriptBlock {
    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_group_id   = $_fake_bound_parameters['GroupId']
    $_group_name = $_fake_bound_parameters['GroupName']

    if (-not [string]::IsNullOrEmpty($_group_id))
    {
        $_sg_list = Get-EC2SecurityGroup -Verbose:$false -Filter @{
            name = 'group-id'; Values = $_group_id
        }
    }
    elseif (-not [string]::IsNullOrEmpty($_group_name))
    {
        $_sg_list = Get-EC2SecurityGroup -Verbose:$false -Filter @{
            name = 'group-name'; Values = $_group_name
        }
    }

    $_filter  = @()
    $_filter += @{Name = 'subnet-id'; Values = "$($_word_to_complete)*"}

    if ($_sg_list) {
        $_filter += @{Name = 'vpc-id'; Values = $_sg_list.VpcId}
    }

    $_subnet_list = Get-EC2Subnet -Verbose:$false -Filter $_filter

    if (-not $_subnet_list) { return }

    $_align = `
        $_subnet_list.SubnetId | Select-Object -ExpandProperty Length |
        Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    $_subnet_list | Get-HintItem -IdPropertyName 'SubnetId' -TagPropertyName 'Tags' -Align $_align |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_.ResourceId,    # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}