using namespace System.Collections
using namespace Systemm.Collections.Generic
using namespace Amazon.EC2.Model
using namespace Worker369.Utility

function Show-RouteTable
{
    [Alias('rt_show')]
    [CmdletBinding(DefaultParameterSetName = 'None')]
    param (
        [parameter(Position = 0)]
        [ValidateSet('Default')]
        [string]
        $View = 'Default',

        [Parameter(ParameterSetName = 'VpcId')]
        [ValidatePattern('^vpc-[0-9a-f]{17}$')]
        [string[]]
        $VpcId,

        [Parameter(ParameterSetName = 'VpcName')]
        [string]
        $VpcName,

        [Amazon.EC2.Model.Filter[]]
        $Filter,

        [ValidateSet('Vpc', $null)]
        [string]
        $GroupBy = 'Vpc',

        [Int[]]
        $Sort,

        [Int[]]
        $Exclude,

        [switch]
        $PlainText,

        [switch]
        $NoRowSeparator
    )

    # Use snake_case.
    $_view             = $View
    $_filter           = $Filter
    $_vpc_id           = $VpcId
    $_vpc_name         = $VpcName
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    # Display a dimmed dash for zero.
    $_style_number_settings = [NumberInfoSettings]::Make()
    $_style_number_settings.Format.Unscaled = "#,###;#,###;`e[2m-`e[0m"

    # Display an unstyled dash for zero.
    $_plain_number_settings = [NumberInfoSettings]::Make()
    $_plain_number_settings.Format.Unscaled = '#,###;#,###;-'

    $_select_definition = @{
        AssociationId = {
            # We need to sort by Subnet to align with the items with the AssociatedSubnet column
            $_assoc_list = $_assoc_lookup_by_rt_id[$_.RouteTableId] | Sort-Object Subnet
            $_assoc_list.RouteTableAssociationId ?? ($_plain_text ? '-' : "`e[2m-`e[0m")
        }
        AssociatedSubnet = {
            # We need to sort by Subnet to align with the items with the AssociatedId column
            $_assoc_list = $_assoc_lookup_by_rt_id[$_.RouteTableId] | Sort-Object Subnet
            $_assoc_list.Subnet ?? ($_plain_text ? '-' : "`e[2m-`e[0m")
        }
        Blackhole = {
            $_num_blackhole = ($_.Routes | Where-Object state -eq 'blackhole').Count
            $_num_settings = $_plain_text ? $_plain_number_settings : $_style_number_settings

            New-NumberInfo -FormatSettings $_num_settings $_num_blackhole
        }
        IsMain = {
            $_is_main = $_.Associations.Main -contains $true
            New-Checkbox -PlainText:$_plain_text $_is_main
        }
        Name = {
            $_.Tags | Where-Object Key -eq 'Name' | Select-Object -ExpandProperty Value
        }
        Propagated = {
            $_num_propagated = ($_.Routes | Where-Object Origin -eq 'EnableVgwRoutePropagation').Count
            $_num_settings = $_plain_text ? $_plain_number_settings : $_style_number_settings

            New-NumberInfo -FormatSettings $_num_settings $_num_propagated
        }
        RouteTableId = {
            $_.RouteTableId
        }
        Routes ={
            $_num_routes = $_.Routes.Count
            $_num_settings = $_plain_text ? $_plain_number_settings : $_style_number_settings

            New-NumberInfo -FormatSettings $_num_settings $_num_routes
        }
        Vpc = {
            $_vpc = $_vpc_lookup[$_.VpcId]
            $_vpc | Get-ResourceString -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
    }

    $_view_definition= @{
        Default = @(
            'Vpc', 'RouteTableId', 'Name', 'IsMain', 'Routes', 'Propagated', 'Blackhole',
            'AssociatedSubnet', 'AssociationId'
        )
    }

    # Apply default sort order.
    if (
        $_group_by -eq 'Vpc' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(2, 1) # => Sort by Name, RouteTableId
    }

    # This try block invokes all AWS APIs necessary to print out the route table listing.
    try {
        # Initialize a filter list.
        $_filter_list = [List[Filter]]::new()

        # Add elements in the -Filter parameter to the filter list.
        $_filter.ForEach({
            $_filter_list.Add($_)
        })

        # Add the -VpcId parameter to the filter list.
        if (-not [string]::IsNullOrEmpty($_vpc_id))
        {
            $_filter_list.Add([Filter]@{
                Name   = 'vpc-id'
                Values = $_vpc_id
            })
        }

        # Find out the VPC ID from the -VpcName parameter.
        if (-not [string]::IsNullOrEmpty($_vpc_name))
        {
            $_vpc_id_filter = Get-EC2Vpc -Verbose:$false `
                -Select Vpcs.VpcId -Filter @{Name = 'tag:Name'; Values = $_vpc_name}

            # Add a vpc-id filter to the filter list.
            if ($_vpc_id_filter)
            {
                $_vpc_filter = [Filter]@{
                    Name   = 'vpc-id';
                    Values = $_vpc_id_filter
                }
                $_filter_list.Add($_vpc_filter)
            }
        }

        # Query Route Tables. Save to list and hashtable.
        $_rt_list   = Get-EC2RouteTable -Verbose:$false -Filter $($_filter_list.Count -eq 0 ? $null : $_filter_list)
        $_rt_lookup = ($_rt_list | Group-Object -AsHashTable RouteTableId) ?? @{}

        # Query VPC. Save to list and hashtable.
        $_vpc_list   = Get-EC2Vpc -Verbose:$false -Filter @{Name = 'vpc-id'; Values = $_rt_list.VpcId}
        $_vpc_lookup = ($_vpc_list | Group-Object -AsHashTable VpcId) ?? @{}

        # Query Subnets. Save to list and hashtable.
        $_subnet_list   = Get-EC2Subnet -Verbose:$false -Filter @{Name = 'vpc-id'; Values = $_rt_list.VpcId}
        $_subnet_lookup = ($_subnet_list | Group-Object -AsHashTable SubnetId) ?? @{}
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Exit early if there are no route tebles to show.
    if (-not $_rt_list) { return }

    # Subnets in VPC that are not explicitly associated.
    $_unassoc_subnet_id_list_lookup_by_vpc_id = [Dictionary[string, string[]]]::new()

    # Create association lookup by route table ID and >> sorted by subnet >> later.
    $_assoc_lookup_by_rt_id = [Dictionary[string, List[pscustomobject]]]::new()

    # Populate $_unassoc_subnet_id_list_lookup_by_vpc_id
    foreach ($_this_vpc in $_vpc_list)
    {
        $_this_vpc_id = $_this_vpc.VpcId

        # All subnets in this VPC.
        $_this_vpc_subnet_id_list = $_subnet_list |
            Where-Object VpcId -eq $_this_vpc_id |
            Select-Object -ExpandProperty SubnetId

        # All subnets in this VPC that are explicitly associated with a route table.
        $_this_vpc_assoc_subnet_id_list = $_rt_list |
            Where-Object VpcId -eq $_this_vpc_id |
            Select-Object -ExpandProperty Associations |
            Select-Object -ExpandProperty SubnetId

        # All subnets in this VPC that are not explicitly associated with a route table
        $_this_vpc_unassoc_subnet_id_list = $_this_vpc_subnet_id_list |
            Where-Object { $_ -notin $_this_vpc_assoc_subnet_id_list }

        # Save the list in a hashtable - to look up using VpcId.
        $_unassoc_subnet_id_list_lookup_by_vpc_id.Add(
            $_this_vpc_id,
            [string[]]$_this_vpc_unassoc_subnet_id_list
        )
    }

    # Populate $_assoc_lookup_by_rt_id
    # Where-Object guard against ForEach-Object invoking one time when input is null
    foreach ($_assoc in $_rt_list.Associations)
    {
        if (-not $_assoc_lookup_by_rt_id.ContainsKey($_assoc.RouteTableId))
        {
            $_assoc_lookup_by_rt_id.Add(
                $_assoc.RouteTableId,
                [List[pscustomobject]]::new()
            )
        }

        # An explicit association has exactly one subnet ID.
        if ($_assoc.SubnetId)
        {
            $_assoc_subnet = $null
            $_assoc_subnet = $_subnet_lookup[$_assoc.SubnetId]

            $_format_assoc_subnet = $_assoc_subnet | `
                Get-ResourceString -IdPropertyName 'SubnetId' -TagPropertyName 'Tags' -PlainText:$_plain_text

            $_assoc_lookup_by_rt_id[$_assoc.RouteTableId].Add(
                [PSCustomObject]@{
                    RouteTableAssociationId = $_assoc.RouteTableAssociationId
                    RouteTableId            = $_assoc.RouteTableId
                    Subnet                  = $_format_assoc_subnet
                }
            )
        }

        # An implicit association can have multiple subnet IDs.
        # Each VPC has one implicit association that can contain multiple subnets (not explicitly associated).
        if ($_assoc.Main)
        {
            $_assoc_rt = $_rt_lookup[$_assoc.RouteTableId]

            $_assoc_subnet_id_list = $_unassoc_subnet_id_list_lookup_by_vpc_id[$_assoc_rt.VpcId]

            # Where-Object guard against ForEach-Object invoking one time when input is null
            foreach ($_assoc_subnet_id in $_assoc_subnet_id_list)
            {
                $_assoc_subnet = $null
                $_assoc_subnet = $_subnet_lookup[$_assoc_subnet_id]

                $_format_assoc_subnet = $_assoc_subnet | `
                    Get-ResourceString -IdPropertyName 'SubnetId' -TagPropertyName 'Tags' -PlainText:$_plain_text

                # Although an implicit association with main route table has an association ID,
                # We use a blank association ID to indicate the subnet is not explicitly associated.
                $_assoc_lookup_by_rt_id[$_assoc_rt.RouteTableId].Add(
                    [PSCustomObject]@{
                        RouteTableAssociationId = $null
                        RouteTableId            = $_assoc_rt.RouteTableId
                        Subnet                  = $_format_assoc_subnet
                    }
                )
            }
        }
    }

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             $_view `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    # Print out the summary table.
    $_data = `
        $_rt_list                    |
        Select-Object $_select_list  |
        Sort-Object   $_sort_list    |
        Select-Object $_project_list

    if ($global:EnableHtmlOutput) {
        $_data | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_data | Format-Column -GroupBy $_group_by -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
    }
}