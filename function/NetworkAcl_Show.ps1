using namespace System.Collections
using namespace System.Collections.Generic
using namespace Amazon.EC2.Model

function Show-NetworkAcl
{
    [Alias('nacl_show')]
    [CmdletBinding()]
    param (
        [parameter(Position = 0)]
        [ValidateSet('Default')]
        [string]
        $View = 'Default',

        [Parameter(ParameterSetName = 'VpcId')]
        [ValidatePattern('^vpc-[0-9a-f]{17}$')]
        [string[]]
        $VpcId,

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

    $_select_definition = @{
        AssociationId = {
            $_assoc_lookup_by_nacl_id[$_.NetworkAclId].NetworkAssociationId
        }
        AssociatedSubnet = {
            $_assoc_lookup_by_nacl_id[$_.NetworkAclId].Subnet
        }
        InboundRules = {
            $_.Entries | Where-Object -not Egress | Measure-Object | Select-Object -ExpandProperty Count
        }
        IsDefault = {
            New-Checkbox -PlainText:$_plain_text $_.IsDefault
        }
        Name = {
            $_.Tags | Where-Object Key -eq 'Name' | Select-Object -ExpandProperty Value
        }
        NetworkAclId = {
            $_.NetworkAclId
        }
        OutboundRules = {
            $_.Entries | Where-Object Egress | Measure-Object | Select-Object -ExpandProperty Count
        }
        Vpc = {
            $_vpc = $_vpc_lookup[$_.VpcId]
            $_vpc | Get-ResourceString -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
    }

    $_view_definition = @{
        Default = (
            'Vpc', 'NetworkAclId', 'Name', 'IsDefault',
            'InboundRules', 'OutboundRules', 'AssociatedSubnet', 'AssociationId'
        )
    }

    # Apply default sort order.
    if (
        $_group_by -eq 'Vpc' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(2, 1) # => Sort by Name, NetworkAclId
    }

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
            $_vpc_id_filter = Get-EC2Vpc -Verbose:$false -Select Vpcs.VpcId `
                -Filter @{Name = 'tag:Name'; Values = $_vpc_name}

            # Add a vpc-id filter to the filter list.
            if ($_vpc_id_filter)
            {
                $_vpc_filter = [Amazon.EC2.Model.Filter]@{
                    Name = 'vpc-id';
                    Values = $_vpc_id_filter
                }
                $_filter_list.Add($_vpc_filter)
            }
        }

        $_nacl_list = Get-EC2NetworkAcl -Filter $($_filter_list.Count -eq 0 ? $null : $_filter_list) -Verbose:$false
        #$_nacl_lookup = $_nacl_list | Group-Object -AsHashTable NetworkAclId

        $_vpc_list   = Get-EC2Vpc -Filter @{Name = 'vpc-id'; Values = $_nacl_list.VpcId} -Verbose:$false
        $_vpc_lookup = $_vpc_list | Group-Object -AsHashTable VpcId

        $_subnet_list   = Get-EC2Subnet -Filter @{Name = 'vpc-id'; Values = $_nacl_list.VpcId} -Verbose:$false
        $_subnet_lookup = $_subnet_list | Group-Object -AsHashTable SubnetId
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Exit early if there are not NACL to show.
    if(-not $_nacl_list) { return }

    # Create association lookup by network ACL ID and sorted by associated subnet.
    $_assoc_lookup_by_nacl_id = [Dictionary[string, List[PSCustomObject]]]::new()

    # Populate the association lookup dictionary.
    foreach ($_nacl in $_nacl_list) {

        # We use a custom association object that can print out a friendly name for the subnet.
        $_my_associations = foreach ($_association in $_nacl.Associations) {
            [PSCustomObject]@{
                NetworkAssociationId = $_association.NetworkAclAssociationId
                NetworkAclId         = $_association.NetworkAclId
                Subnet               = $_subnet_lookup[$_association.SubnetId] | Get-ResourceString `
                    -IdPropertyName 'SubnetId' -TagPropertyName 'Tags' -PlainText:$_plain_text
            }
        }

        $_assoc_lookup_by_nacl_id.Add(
            $_nacl.NetworkAclId,
            ($_my_associations | Sort-Object Subnet)
        )
    }

    # Get the names of columns to display.
    $_select_names = $_VIEW_DEFINITION[$_view]

    # If Group By is not in the select names, insert it to the select names.
    if ($_group_by -and $_group_by -notin $_select_names)
    {
        $_select_names = @($_group_by) + @($_select_names)
    }

    # Initialize select list.
    $_select_list  = [List[object]]::new()

    for($_i = 0 ; $_i -lt $_select_names.Length ; $_i++)
    {
        $_select_name = $_select_names[$_i]
        $_select_list.Add(
            @{N = "$_select_name" ; E = $_SELECT_DEFINITION[$_select_name]}
        )
    }

    # Sort column list = list of @{Name = <column name>; Descending = <true|false>}
    $_sort_list = [List[object]]::new()

    # Add group to sort list.
    if($_group_by -and $_group_by -in $_select_names)
    {
        $_sort_list.Add(
            @{
                Expression = $_group_by;
                Descending = $false
            }
        )
    }

    # Remove group from the sortable names.
    $_sort_names = $_select_names | Where-Object {$_ -ne $_group_by}

    # Build the sort list.
    for($_i = 0 ; $_i -lt $_sort.Length ; $_i++)
    {
        # Column number is 1-based. Column index is 0-based
        $_sort_index = [Math]::Abs($_sort[$_i]) - 1

        # Guard against index out of bound.
        if ($_sort_index -ge $_sort_names.Length) { continue }

        # Get the column name
        $_sort_name = $_sort_names[$_sort_index]

        # Get ascending or descending
        $_descending = $($_sort[$_i] -lt 0)

        $_sort_list.Add(
            @{
                Expression = "$_sort_name"
                Descending = $_descending
            }
        )
    }

    # Remove group from the sortable names.
    $_project_names = $_select_names | Where-Object {$_ -ne $_group_by}

    # Initialize a project list.
    $_project_list = [List[object]]::new()

    # Add the group property to the project list first.
    if ($_group_by -and $_group_by -in $_select_names)
    {
        $_project_list.Add($_group_by)
    }

    # Add all properties not excluded to the project list.
    for ($_i = 0 ; $_i -lt $_project_names.Length; $_i++)
    {
        if (($_i + 1) -notin $_exclude) {
            $_project_list.Add($_project_names[$_i])
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
    $_nacl_list                  |
    Select-Object $_select_list  |
    Sort-Object   $_sort_list    |
    Select-Object $_project_list |
    Format-Column -GroupBy $_group_by -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
}