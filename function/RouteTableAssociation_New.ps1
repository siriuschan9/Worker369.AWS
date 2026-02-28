using namespace System.Management.Automation
using namespace System.Collections.Generic
using namespace Amazon.EC2.Model

function New-RouteTableAssociation
{
    [Alias('rt_assoc_add')]
    [CmdletBinding(DefaultParameterSetName = 'Name',SupportsShouldProcess)]
    param (
        [Parameter(ParameterSetName = 'Name', Mandatory, Position = 0)]
        [string]
        $RouteTableName,

        [Parameter(ParameterSetName = 'Name', Mandatory, Position = 1)]
        [string[]]
        $SubnetName,

        [Parameter(ParameterSetName = 'Id', Mandatory, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^rtb-[0-9a-f]{17}$', ErrorMessage = 'Invalid RouteTableId.')]
        [string]
        $RouteTableId,

        [Parameter(ParameterSetName = 'Id', Mandatory)]
        [ValidatePattern('^subnet-[0-9a-f]{17}$', ErrorMessage = 'Invalid SubnetId.')]
        [string[]]
        $SubnetId
    )

    BEGIN
    {
        # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Id parameter set.
        $_rt_id            = $RouteTableId
        $_subnet_id_list   = $SubnetId

        # Name parameter set.
        $_rt_name          = $RouteTableName
        $_subnet_name_list = $SubnetName

        # Configure the filter to query the Route Tables.
        $_rt_filter = $_param_set -eq 'Name' `
            ? @{Name = 'tag:Name'; Values = $_rt_name}
            : @{Name = 'route-table-id'; Values = $_rt_id}

        # Configure the filter to query the Subnets.
        $_subnet_filter = $_param_set -eq 'Name' `
            ? @{Name = 'tag:Name'; Values = $_subnet_name_list}
            : @{Name = 'subnet-id' ; Values = $_subnet_id_list}

        try {
            $_rt_list     = Get-EC2RouteTable -Verbose:$false -Filter $_rt_filter
            $_subnet_list = Get-EC2Subnet     -Verbose:$false -Filter $_subnet_filter
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If no Route Tables matched the filter value, exit early.
        if (-not $_rt_list)
        {
            Write-Error (
                'No Route Table was found for ''{0}''.' -f
                $_param_set -eq 'Name' ? $_rt_name : $_rt_id
            )
            return
        }

        # If multiple Route Tables matched the filter value, fail early.
        if ($_rt_list.Count -gt 1)
        {
            Write-Error (
                'Multiple Route Tables were found for ''{0}''. It must match only one Route Table.' -f
                $_param_set -eq 'Name' ? $_rt_name : $_rt_id
            )
            return
        }

        # If no Subnets matched the filter value, exit early.
        if (-not $_subnet_list)
        {
            Write-Error (
                'No Subnet was found for ''{0}''.' -f
                $_param_set -eq 'Name' ? $_subnet_name_list -join ',' : $_subnet_id_list -join ','
            )
            return
        }

        # Save a reference to the filtered Route Table.
        $_rt = $_rt_list[0]

        # Generate a friendly display string for the Route Table.
        $_format_rt = $_rt | Get-ResourceString -IdPropertyName 'RouteTableId' -TagPropertyName 'Tags' -PlainText

        $_subnet_list | ForEach-Object {

            # Save a reference to this subnet.
            $_this_subnet   = $_

            # Generate a friendly display string for this subnet.
            $_format_subnet = $_this_subnet | Get-ResourceString `
                -IdPropertyName 'SubnetId' -TagPropertyName 'Tags' -PlainText

            # Action and Target for What-If/Confirmation prompt
            $_target = "Route Table: $($_format_rt) | Subnet: $($_format_subnet)"
            $_action = 'Create New Route Table Association'

            if ($PSCmdlet.ShouldProcess($_target, $_action))
            {
                try {
                    # Check if there is an existing association for this Subnet.
                    $_old_assoc_id = Get-EC2RouteTable -Verbose:$false -Filter @{
                        Name   = 'association.subnet-id'
                        Values = $_this_subnet.SubnetId
                    } | Where-Object {
                        $_.Associations.SubnetId -contains $_this_subnet.SubnetId
                    } | Select-Object -ExpandProperty Associations | Where-Object {
                        $_.SubnetId -eq $_this_subnet.SubnetId
                    } | Select-Object -ExpandProperty RouteTableAssociationId

                    # Deregister the existing association if one exist.
                    if ($_old_assoc_id)
                    {
                        Write-Verbose (
                            "  - Found existing Association for $_format_subnet. " +
                            "Deregistering existing Association $_old_assoc_id."
                        )

                        Unregister-EC2RouteTable -Verbose:$false $_old_assoc_id
                    }

                    # Only verbose this registering mesage when there was a deregeistration. See previous step.
                    # Else, it will appear to be showing the same message as the What-If/Confirmation prompt.
                    if ($_old_assoc_id)
                    {
                        Write-Verbose "  - Registering new Route Table Association."
                    }

                    # Register the association.
                    $_assoc_id = Register-EC2RouteTable -Verbose:$false $_rt.RouteTableId $_this_subnet.SubnetId

                    # Return the Association ID to the caller.
                    Write-Message -Output "  - RouteTableAssociationId: $_assoc_id"
                }
                catch {
                    # Remove caught exception emitted into $Error list.
                    Pop-ErrorRecord $_

                    # Report error as non-terminating.
                    $PSCmdlet.WriteError($_)
                }
            }
        }
    }
}

# RouteTableId
Register-ArgumentCompleter -ParameterName 'RouteTableId' -CommandName 'New-RouteTableAssociation' -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    # If the -SubnetId parameter is specified, we try to match only the route table IDs in the Subnet's VPC.
    $_subnet_id = $_fake_bound_parameters['SubnetId']

    if (-not [string]::IsNullOrEmpty($_subnet_id)) {
        $_vpc_id = Get-EC2Subnet -Verbose:$false -Select Subnets.VpcId -Filter @{Name='subnet-id'; Values = $_subnet_id}
    }

    # Do the filter on the server side.
    $_rt_list = Get-EC2RouteTable -Verbose:$false -Filter @{
        Name = 'route-table-id'; Values = "$_word_to_complete*"
    }, @{
        Name = 'vpc-id'; Values = "$_vpc_id*"
    }

    # If there are no matched route tables, exit early.
    if (-not $_rt_list) { return }

    # Align the name portion of the autocomplete items.
    $_align = $_rt_list.RouteTableId.Length | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    # Generate the autocomplete items.
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

# SubnetId
Register-ArgumentCompleter -ParameterName 'SubnetId' -CommandName 'New-RouteTableAssociation' -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    # Bug: Filter for Get-EC2Subnet 'subnet-id' does not honour wildcard *
    # Hence, for this function, we do the filtering locally.

    # Download all Subnets and do the filtering locally.
    $_subnet_list = Get-EC2Subnet -Verbose:$false

    # If the -RouteTableId parameter is specified, we try to match only the subnet IDs in the Route Table's VPC.
    $_route_table_id = $_fake_bound_parameters['RouteTableId']

    if (-not [string]::IsNullOrEmpty($_route_table_id))
    {
        $_vpc_id = Get-EC2RouteTable -Verbose:$false -Filter @{
            Name = 'route-table-id'; Values = $_route_table_id
        }
    }

    # Filter out subnets in the Route Table's VPC
    if ($_vpc_id -and $_vpc_id.Count -eq 1) {
        $_subnet_list = $_subnet_list | Where-Object {$_.VpcId -eq $_vpc_id }
    }

    # If there are no matched subnets, exit early.
    if (-not $_subnet_list) { return }

    # Align the name portion of the autocomplete items.
    $_align = $_subnet_list.SubnetId.Length | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    # Generate the autocomplete items.
    $_subnet_list | Get-HintItem -IdPropertyName 'SubnetId' -TagPropertyName 'Tags' -Align $_align |
    Sort-Object | Where-Object { $_ -like "$_word_to_complete*" } | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_.ResourceId,    # completionText
            $_ ,              # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# RouteTableName
Register-ArgumentCompleter -ParameterName 'RouteTableName' -CommandName 'New-RouteTableAssociation' -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    # If the -SubnetName parameter is specified, we try to match only the route table names in the Subnet's VPC.
    $_subnet_name = $_fake_bound_parameters['SubnetName']

    if (-not [string]::IsNullOrEmpty($_subnet_name)) {

        $_vpc_id = Get-EC2Subnet -Verbose:$false -Select Subnets.VpcId -Filter @{
            Name='tag:Name'; Values = $_subnet_name
        }

        # If more the one VPC matched the -SubnetName, exit early.
        if ($_vpc_id.Count -gt 1) { return }
    }

    # Do the filtering on the server side.
    Get-EC2RouteTable -Verbose:$false -Filter @{
        Name = 'tag:Name'; Values = "$_word_to_complete*"
    }, @{
        Name = 'vpc-id'; Values = "$_vpc_id*"
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

# SubnetName
Register-ArgumentCompleter -ParameterName 'SubnetName' -CommandName 'New-RouteTableAssociation' -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    # Bug: Filter for Get-EC2Subnet 'vpc-id' does not honour wildcard *
    # Hence, for this function, we do the filtering locally.

    # Perform Name filtering on the server side.
    $_subnet_list = Get-EC2Subnet -Verbose:$false -Filter @{
        Name = 'tag:Name' ; Values = "$_word_to_complete*"
    }

    # If the -RouteTableName parameter is specified, we try to match only the subnet names in the Route Table's VPC.
    $_route_table_name = $_fake_bound_parameters['RouteTableName']

    if (-not [string]::IsNullOrEmpty($_route_table_name))
    {
        $_vpc_id = Get-EC2RouteTable -Verbose:$false -Select RouteTables.VpcId -Filter @{
            Name   = 'tag:Name'
            Values = $_route_table_name
        }

        # If more than one VPC matched the route table filter, exit early.
        if ($_vpc_id -and $_vpc_id.Count -gt 1) {return }

        # Filter out those subnets in this VPC.
        $_subnet_list = $_subnet_list | Where-Object VpcId -eq $_vpc_id
    }

    # Generate the autocomplete items.
    $_subnet_list | Select-Object -ExpandProperty Tags | Where-Object Key -eq 'Name' |
    Select-Object -Unique -ExpandProperty Value | Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}