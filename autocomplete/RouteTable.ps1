$_cmd_lookup = @{

    RouteTableId = @(
        'Show-Route', 'Add-Route', 'Remove-Route',
        'Remove-RouteTable', 'Rename-RouteTable',
        'Set-DefaultRouteTable'
    )

    RouteTableId_InVpc = @(
        'New-RouteTableAssociation'
    )

    RouteTableName = @(
        'Show-Route', 'Add-Route', 'Remove-Route',
        'Remove-RouteTable', 'Rename-RouteTable',
        'Set-DefaultRouteTable'
    )

    AssociationId = @(
        'Remove-RouteTableAssociation'
    )
}

# RouteTableId
Register-ArgumentCompleter -ParameterName 'RouteTableId' -CommandName $_cmd_lookup['RouteTableId'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_rt_list = Get-EC2RouteTable -Verbose:$false -Filter @{
        Name   = 'route-table-id'
        Values = "$_word_to_complete*"
    }

    if (-not $_rt_list) { return }

    $_align = $_rt_list.RouteTableId.Length | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    $_rt_list | Get-HintItem -IdPropertyName 'RouteTableId' -TagPropertyName 'Tags' -Align $_align |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_.ResourceId,    # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# RouteTableName
Register-ArgumentCompleter -ParameterName 'RouteTableName' -CommandName $_cmd_lookup['RouteTableName'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    Get-EC2RouteTable -Verbose:$false -Filter @{
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

# AssociationId
Register-ArgumentCompleter -ParameterName 'AssociationId' -CommandName $_cmd_lookup['AssociationId'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    # We need to apply the filter both on AWS and on local machine, because
    # AWS pick out the route table, not the specific associations that we want.
    # The route table has other associations. We still need to filter locally to pick out the association that we want.

    Get-EC2RouteTable -Verbose:$false -Filter @{
        Name   = 'association.route-table-association-id'
        Values = "$_word_to_complete*"
    } |
    Select-Object -ExpandProperty Associations | Where-Object -not Main |
    Select-Object -ExpandProperty RouteTableAssociationId |
    Where-Object { $_ -like "$_word_to_complete*" } | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}