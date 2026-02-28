using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.Management.Automation
using namespace Worker369.Utility

function Show-VpcPeering
{
    [CmdletBinding()]
    [Alias('pcx_show')]
    param (
        [Parameter(Position = 0)]
        [ValidateSet(
            'This_Other', 'Left_Right', 'Cidr', 'Dns'
        )]
        [string]
        $View = 'This_Other',

        [Amazon.EC2.Model.Filter[]]
        $Filter,

        [ValidateSet('Other_Account', 'Other_Region', 'Other_Vpc', 'This_Vpc', $null)]
        [string]
        $GroupBy = 'Other_Account',

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
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    # For easy pickup.
    $_dim   = [PSStyle]::Instance.Dim
    $_reset = [PSStyle]::Instance.Reset

    $_fully_routed_indicator     = $_plain_text ? '✓✓' : '✓✓'
    $_partially_routed_indicator = $_plain_text ? '✓x' : "✓${_dim}✓${_reset}"
    $_non_routed_indicator       = $_plain_text ? 'xx' : "${_dim}✓✓${_reset}"
    $_unknown_routed_indicator   = $_plain_text ? '??' : "${_dim}??${_reset}"

    # Define a regex pattern to separate IPv4 and IPv6 CIDR ranges later in the select definitions.
    $_ipv4_pattern = `
        '^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}' + # 255.255.255.
        '([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])' +         # 255
        '\/([0-9]|[1-2][0-9]|3[0-2])$'                                 # /32

    $_view_definition = @{
        'This_Other' = @(
            'VpcPeeringConnectionId', 'VpcPeeringConnectionName', 'Status', 'Requester', 'Accepter', 'This_Vpc',
            'Other_Vpc', 'Other_Region', 'Other_Account'
        )
        'Status' = @(
            'VpcPeeringConnectionId', 'VpcPeeringConnectionName', 'Status', 'Expiry',
            'Left_Account', 'Left_Region', 'Left_Vpc', 'Right_Account', 'Right_Region', 'Right_Vpc'
        )
        'Cidr' = @(
            'VpcPeeringConnectionId', 'VpcPeeringConnectionName', 'Status',
            'Left_Vpc', 'Left_Cidr', 'Right_Vpc', 'Right_Cidr'
        )
        'Dns' = @(
            'VpcPeeringConnectionId', 'VpcPeeringConnectionName', 'Status',
            'Left_Vpc', 'Left_AcceptDns', 'Right_Vpc', 'Right_AcceptDns'
        )
    }

    $_select_definition = @{
        Accepter = {
            $_is_accepter = `
                $_vpc_lookup.ContainsKey($_.AccepterVpcInfo.VpcId) -and
                -not $_vpc_lookup.ContainsKey($_.RequesterVpcInfo.VpcId)

            New-Checkbox -PlainText:$_plain_text $_is_accepter
        }
        Expiry = {
            $_.ExpirationTime
        }
        Left_AcceptDns = {
            New-Checkbox -PlainText:$_plain_text $_.RequesterVpcInfo.PeeringOptions.AllowDnsResolutionFromRemoteVpc
        }
        Left_Account = {
            $_.RequesterVpcInfo.OwnerId.Insert(4, '-').Insert(9, '-')
        }
        Left_Cidr = {
            # Grab my VPC's CIDR blocks.
            $_ipv4_cidr_list = $_.RequesterVpcInfo.CidrBlockSet.Cidr      | New-Ipv4Subnet | Sort-Object
            $_ipv6_cidr_list = $_.RequesterVpcInfo.Ipv6CidrBlockSet.Value | New-Ipv6Subnet | Sort-Object

            # If the peered VPC belongs to a different account or different region,
            # we would not have its routing information here.
            if (-not $_vpc_lookup.ContainsKey($_.AccepterVpcInfo.VpcId))
            {
                foreach ($_ipv4_cidr in $_ipv4_cidr_list) {
                    "{0, -$_right_cidr_max_length} {1}" -f $_ipv4_cidr, $_unknown_routed_indicator
                }
                foreach ($_ipv6_cidr in $_ipv6_cidr_list) {
                    "{0, -$_right_cidr_max_length} {1}" -f $_ipv6_cidr, $_unknown_routed_indicator
                }
                return
            }

            # Try to get the list of routed CIDR from the peered VPC's route tables towards my VPC.
            $_routed_cidr_list = $_cidr_lookup["$($_.AccepterVpcInfo.VpcId), $($_.VpcPeeringConnectionId)"]

            # If we cannot find any CIDRs in the lookup, it means the peered VPC has not routed any CIDR to my VPC.
            if (-not $_routed_cidr_list)
            {
                foreach ($_ipv4_cidr in $_ipv4_cidr_list) {
                    "{0, -$_right_cidr_max_length} {1}" -f $_ipv4_cidr, $_non_routed_indicator
                }
                foreach ($_ipv6_cidr in $_ipv6_cidr_list) {
                    "{0, -$_right_cidr_max_length} {1}" -f $_ipv6_cidr, $_non_routed_indicator
                }
                return
            }

            # Split the routed CIDRs into two groups based on the IP version.
            $_ipv4_routed_list = @($_routed_cidr_list) -match    $_ipv4_pattern
            $_ipv6_routed_list = @($_routed_cidr_list) -notmatch $_ipv4_pattern

            # Loop through each IPv4 CIDR block in my VPC.
            foreach ($_ipv4_cidr in $_ipv4_cidr_list)
            {
                # Map all discovered routed CIDRs in the peered VPC against this CIDR.
                # We also need to materalize the mappings first to count the elements.
                $_parent_node = [IPv4CidrNode]::new($_ipv4_cidr)
                $_mappings    = $_parent_node.MapSubnets($_ipv4_routed_list) -as [Array] # Need to materalize it first.

                # Initialize the indicator for this CIDR to empty string first.
                $_indicator = ''

                if (($_mappings.IsMapped -eq $true).Length -eq $_mappings.Length) {      # All mapped.
                    $_indicator = $_fully_routed_indicator
                }
                elseif (($_mappings.IsMapped -eq $false).Length -eq $_mappings.Length) { # All unmapped.
                    $_indicator = $_non_routed_indicator
                }
                else {                                                                   # Partially mapped.
                    $_indicator = $_partially_routed_indicator
                }

                "{0, -$_right_cidr_max_length} {1}" -f $_ipv4_cidr, $_indicator
            }

            # Loop through each IPv6 CIDR block in my VPC.
            foreach ($_ipv6_cidr in $_ipv6_cidr_list)
            {
                # Map all discovered routed CIDRs in the peered VPC against this CIDR.
                # We also need to materalize the mappings first to count the elements.
                $_parent_node = [IPv6CidrNode]::new($_ipv6_cidr)
                $_mappings    = $_parent_node.MapSubnets($_ipv6_routed_list) -as [Array] # Need to materalize it first.

                # Initialize the indicator for this CIDR to empty string first.
                $_indicator = ''

                if (($_mappings.IsMapped -eq $true).Length -eq $_mappings.Length) {      # All mapped.
                    $_indicator = $_fully_routed_indicator
                }
                elseif (($_mappings.IsMapped -eq $false).Length -eq $_mappings.Length) { # All unmapped.
                    $_indicator = $_non_routed_indicator
                }
                else {                                                                   # Partially mapped.
                    $_indicator = $_partially_routed_indicator
                }

                "{0, -$_right_cidr_max_length} {1}" -f $_ipv6_cidr, $_indicator
            }
        }
        Left_Region = {
            $_.RequesterVpcInfo.Region
        }
        Left_Vpc = {
            $_.RequesterVpcInfo.VpcId
        }
        Other_Account = {
            $_is_requester_here = $_vpc_lookup.ContainsKey($_.RequesterVpcInfo.VpcId)

            if ($_is_requester_here)
                { $_other_account = $_.AccepterVpcInfo.OwnerId.Insert(4, '-').Insert(9, '-') }
            else
                { $_other_account = $_.RequesterVpcInfo.OwnerId.Insert(4, '-').Insert(9, '-') }

            return $_this_account -eq $_other_account ? '.' : $_other_account
        }
        Other_Region = {
            $_is_requester_here = $_vpc_lookup.ContainsKey($_.RequesterVpcInfo.VpcId)

            if ($_is_requester_here)
                { $_other_region = $_.AccepterVpcInfo.Region }
            else
                { $_other_region =  $_.RequesterVpcInfo.Region }

            return $_this_region -eq $_other_region ? '.' : $_other_region
        }
        Other_Vpc = {
            $_is_requester_here = $_vpc_lookup.ContainsKey($_.RequesterVpcInfo.VpcId)

            if ($_is_requester_here)
                { return $_.AccepterVpcInfo.VpcId }
            else
                { return $_.RequesterVpcInfo.VpcId }
        }
        Requester = {
            $_is_requester = $_vpc_lookup.ContainsKey($_.RequesterVpcInfo.VpcId)
            New-Checkbox -PlainText:$_plain_text $_is_requester
        }
        Right_AcceptDns = {
            New-Checkbox -PlainText:$_plain_text $_.AccepterVpcInfo.PeeringOptions.AllowDnsResolutionFromRemoteVpc
        }
        Right_Account = {
            $_.AccepterVpcInfo.OwnerId.Insert(4, '-').Insert(9, '-')
        }
        Right_Cidr = {
            $_ipv4_cidr_list = $_.AccepterVpcInfo.CidrBlockSet.Cidr      | New-IPv4Subnet | Sort-Object
            $_ipv6_cidr_list = $_.AccepterVpcInfo.Ipv6CidrBlockSet.Value | New-IPv6Subnet | Sort-Object

            # If the peered VPC belongs to a different account or different region,
            # we would have its routing information here.
            if (-not $_vpc_lookup.ContainsKey($_.RequesterVpcInfo.VpcId))
            {
                foreach ($_ipv4_cidr in $_ipv4_cidr_list) {
                    "{0, -$_left_cidr_max_length} {1}" -f $_ipv4_cidr, $_unknown_routed_indicator
                }
                foreach ($_ipv6_cidr in $_ipv6_cidr_list) {
                    "{0, -$_left_cidr_max_length} {1}" -f $_ipv6_cidr, $_unknown_routed_indicator
                }
                return
            }

            # Try to get the list of routed CIDR from the peered VPC's route tables towards my VPC.
            $_routed_cidr_list = $_cidr_lookup["$($_.RequesterVpcInfo.VpcId), $($_.VpcPeeringConnectionId)"]

            # If we cannot find any CIDRs in the lookup, it means the peered VPC has not routed any CIDR to my VPC.
            if (-not $_routed_cidr_list)
            {
                foreach ($_ipv4_cidr in $_ipv4_cidr_list) {
                    "{0, -$_left_cidr_max_length} {1}" -f $_ipv4_cidr, $_non_routed_indicator
                }
                foreach ($_ipv6_cidr in $_ipv6_cidr_list) {
                    "{0, -$_left_cidr_max_length} {1}" -f $_ipv6_cidr, $_non_routed_indicator
                }
                return
            }

            # Split the routed CIDRs into two groups based on the IP version.
            $_ipv4_routed_list = @($_routed_cidr_list) -match    $_ipv4_pattern
            $_ipv6_routed_list = @($_routed_cidr_list) -notmatch $_ipv4_pattern

            # Loop through each IPv4 CIDR block in my VPC.
            foreach ($_ipv4_cidr in $_ipv4_cidr_list)
            {
                # Map all discovered routed CIDRs in the peered VPC against this CIDR.
                # We also need to materalize the mappings first to count the elements.
                $_parent_node = [IPv4CidrNode]::new($_ipv4_cidr)
                $_mappings    = $_parent_node.MapSubnets($_ipv4_routed_list) -as [Array] # Need to materalize it first.

                # Initialize the indicator for this CIDR to empty string first.
                $_indicator = ''

                if (($_mappings.IsMapped -eq $true).Length -eq $_mappings.Length) {      # All mapped.
                    $_indicator = $_fully_routed_indicator
                }
                elseif (($_mappings.IsMapped -eq $false).Length -eq $_mappings.Length) { # All unmapped.
                    $_indicator = $_non_routed_indicator
                }
                else {                                                                   # Partially mapped.
                    $_indicator = $_partially_routed_indicator
                }

                "{0, -$_left_cidr_max_length} {1}" -f $_ipv4_cidr, $_indicator
            }

            # Loop through each IPv6 CIDR block in my VPC.
            foreach ($_ipv6_cidr in $_ipv6_cidr_list)
            {
                # Map all discovered routed CIDRs in the peered VPC against this CIDR.
                # We also need to materalize the mappings first to count the elements.
                $_parent_node = [IPv6CidrNode]::new($_ipv6_cidr)
                $_mappings    = $_parent_node.MapSubnets($_ipv6_routed_list) -as [Array] # Need to materalize it first.

                # Initialize the indicator for this CIDR to empty string first.
                $_indicator = ''

                if (($_mappings.IsMapped -eq $true).Length -eq $_mappings.Length) {      # All mapped.
                    $_indicator = $_fully_routed_indicator
                }
                elseif (($_mappings.IsMapped -eq $false).Length -eq $_mappings.Length) { # All unmapped.
                    $_indicator = $_non_routed_indicator
                }
                else {                                                                   # Partially mapped.
                    $_indicator = $_partially_routed_indicator
                }

                "{0, -$_left_cidr_max_length} {1}" -f $_ipv6_cidr, $_indicator
            }
        }
        Right_Region = {
            $_.AccepterVpcInfo.Region
        }
        Right_Vpc = {
            $_.AccepterVpcInfo.VpcId
        }
        Status = {
            $_status_code = $_.Status.Code
            New-Checkbox -PlainText:$_plain_text -Description $_status_code ($_status_code -ieq 'active')
        }
        VpcPeeringConnectionId = {
            $_.VpcPeeringConnectionId
        }
        VpcPeeringConnectionName = {
            $_.Tags | Where-Object Key -eq 'Name' | Select-Object -ExpandProperty Value
        }
        This_Vpc = {
            $_this_vpc = $_vpc_lookup[$_.RequesterVpcInfo.VpcId] ?? $_vpc_lookup[$_.AccepterVpcInfo.VpcId]
            $_this_vpc | Get-ResourceString `
                -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText:$_plain_text
        }
    }

    # Apply default sort order.
    if ($_group_by -eq 'Other_Account' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(-3, 2, 1) # => Sort by Name, VpcPeeringId
    }

    # Lookup prefix list entries by prefix list ID.
    $_pl_entries_lookup = @{}

    try {
        # Retrieve VPC Peering connections.
        Write-Verbose "Retrieving VPC Peering Connections."
        $_peering_list = Get-EC2VpcPeeringConnection -Verbose:$false -Filter $_filter

        if (-not $_peering_list) { return }

        # Save a list of interested VPC ID.
        $_vpc_id_list = @($_peering_list.AccepterVpcInfo.VpcId) + @($_peering_list.RequesterVpcInfo.VpcId) |
            Sort-Object -Unique

        # Retrieve VPCs.
        Write-Verbose "Retrieving VPCs."
        $_vpc_lookup = Get-EC2Vpc -Verbose:$false -Filter @{
            Name = 'vpc-id'
            Values = $_vpc_id_list
        } | Group-Object -AsHashTable VpcId

        # Retrieve Route Tables
        if ($_view -in @('Cidr'))
        {
            Write-Verbose "Retrieving Route Tables."

            $_rt_list = Get-EC2RouteTable -Verbose:$false -Filter @{
                Name   = 'vpc-id'
                Values = $_vpc_id_list
            }
        }

        # Retrieve prefix lists.
        if ($_view -in @('Cidr') -and $_null -ne $_rt_list)
        {
            Write-Verbose "Retrieving Prefix Lists."

            $_pl_id_list = `
                $_rt_list.Routes | Select-Object -ExpandProperty DestinationPrefixListId | Sort-Object -Unique

            $_pl_lookup = Get-EC2ManagedPrefixList -Verbose:$false -Filter @{
                Name   = 'prefix-list-id'
                Values = $_pl_id_list
            } | Group-Object -AsHashTable PrefixListId

            foreach ($_pl_id in $_pl_id_list)
            {
                $_pl_cidr_list = `
                    Get-EC2ManagedPrefixListEntry -Verbose:$false -PrefixListId $_pl_id |
                    Select-Object -ExpandProperty Cidr

                $_pl_entries_lookup.Add($_pl_id, $_pl_cidr_list)
            }
        }

        # Retrieve this Account ID and Region
        $_this_account = (Get-STSCallerIdentity -Verbose:$false).Account.Insert(4, '-').Insert(9, '-')
        $_this_region  = (Get-DefaultAWSRegion -Verbose:$false).Region
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Save a list of VPC Peering Connection ID.
    $_peering_id_list = $_peering_list.VpcPeeringConnectionId

    # Prepare a hashtable for (vpc-id, pcx-id) -> cidr-list.
    $_cidr_lookup = @{}

    # Process route tables.
    foreach ($_rt in $_rt_list)
    {
        foreach ($_route in ($_rt.Routes | Where-Object VpcPeeringConnectionId -in $_peering_id_list))
        {
            # We use "vpc-id, pcx-id" as the lookup up
            $_key = "$($_rt.VpcId), $($_route.VpcPeeringConnectionId)"

            # If the lookup have not seen this key, create a new CIDR list for this key.
            if (-not $_cidr_lookup.ContainsKey($_key))
            {
                # We use hashset to block duplicate CIDRs from being added to the list.
                $_cidr_lookup.Add($_key, [System.Collections.Generic.HashSet[Object]]::new())
            }

            # Save a reference to the list
            $_cidr_list = $_cidr_lookup[$_key]

            if ($_route.DestinationCidrBlock)
            {
                $_cidr_list.Add(($_route.DestinationCidrBlock | New-IPv4Subnet)) | Out-Null
            }
            elseif ($_route.DestinationIpv6CidrBlock)
            {
                $_cidr_list.Add(($_route.DestinationIpv6CidrBlock | New-IPv6Subnet)) | Out-Null
            }
            elseif ($_route.DestinationPrefixListId)
            {
                $_dst_pl         = $_pl_lookup[$_route.DestinationPrefixListId]
                $_dst_pl_entries = $_pl_entries_lookup[$_route.DestinationPrefixListId]

                if ($_dst_pl -and $_dst_pl.AddressFamily -eq 'IPv4' -and $_dst_pl_entries)
                {
                    $_cidr_list.AddRange(($_dst_pl_entries | New-IPv4Subnet | Sort-Object)) | Out-Null
                }

                if ($_dst_pl -and $_dst_pl.AddressFamily -eq 'IPv6' -and $_dst_pl_entries)
                {
                    $_cidr_list.AddRange(($_dst_pl_entries | New-IPv6Subnet | Sort-Object)) | Out-Null
                }
            }
        }
    }

    # Save the number of characters need for the longest CIDR to align the routed indicator later.
    $_left_cidr_max_length = `
        (
            @($_peering_list.RequesterVpcInfo.CidrBlockSet | Select-Object -ExpandProperty Cidr) +
            @($_peering_list.RequesterVpcInfo.Ipv6CidrBlockSet | Select-Object -ExpandProperty Value)
        ) |
        ForEach-Object { $_.ToString() } | Measure-Object Length -Maximum | Select-Object -ExpandProperty Maximum

    $_right_cidr_max_length = `
        (
            @($_peering_list.AccepterVpcInfo.CidrBlockSet | Select-Object -ExpandProperty Cidr) +
            @($_peering_list.AccepterVpcInfo.Ipv6CidrBlockSet | Select-Object -ExpandProperty Value)
        ) |
        ForEach-Object { $_.ToString() } | Measure-Object Length -Maximum | Select-Object -ExpandProperty Maximum

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             $_view `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    # Generate output after sorting and exclusion.
    $_output = $_peering_list | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column `
            -GroupBy $_group_by -AlignLeft Status `
            -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
    }
}