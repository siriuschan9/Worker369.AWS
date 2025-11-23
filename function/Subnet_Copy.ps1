<#
.SYNOPSIS
Copies a subnet to a target AZ with the same settings.

.DESCRIPTION
Creates a new subnet in the target AZ as specified by the -AvailabilityZone parameter.
Subnet settings will be copied from the source subnet as specified by the -SubnetId parameter.

.EXAMPLE
Copy-Subnet subnet-src subnet-dst ap-southeast-1a.

This example creates a new Subnet named "subnet-dst" in the Availability Zone "ap-southeast-1a",
and copies the subnet attributes and associations from the source subnet named "subnet-src".

.PARAMETER SubnetId
Source subnet ID.

.PARAMETER SubnetName
Source subnet Name.

.PARAMETER AvailabilityZone
Target AZ.

.PARAMETER Ipv4Cidr
You can specify the IPv4 CIDR block using the -Ipv4Cidr parameter.
If unspecified, it will be the next adjacent range from the source subnet's CIDR.
For example, if the source CIDR is 192.168.1.0/24, the destination CIDR will be 192.168.2.0/24.

.PARAMETER Ipv6CidrBlock
You can specify the IPv6 CIDR block using the -IPv6Cidr parameter.
If unspecified, it will be the next adjacent range from the source subnet's IPv6 CIDR.
For example, if the source CIDR is 2:2:2:1::/64, the destination CIDR will be 2:2:2:2:/64.

.PARAMETER DestinationName
The -DestinationName Tag is a convenient parameter to specify the Name tag.
It will take precedence over both caller-specified and copied tags.

.PARAMETER DoNotCopyTags
By default, tags will be copied. To disable this behaviour, specify the -DoNotCopyTag parameter.

.PARAMETER Tag
Tags that are specified using the -Tag parameter will take precedence over copied tags.
#>

function Copy-Subnet
{
    [CmdletBinding(DefaultParameterSetName = 'SubnetName',SupportsShouldProcess)]
    [Alias("subnet_cp")]
    param (
        [Parameter(ParameterSetName = 'SubnetId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]
        $SubnetId,

        [Parameter(ParameterSetName = 'SubnetName', Mandatory, Position = 0)]
        [string]
        $SubnetName,

        [Parameter(ParameterSetName = 'SubnetId')]
        [Parameter(ParameterSetName = 'SubnetName', Position = 1)]
        [string]
        $DestinationName,

        [string]
        $AvailabilityZone,

        [Parameter()]
        [ValidatePattern(
            '^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}' + # 255.255.255.
            '([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])' +         # 255
            '\/([0-9]|[1-2][0-9]|3[0-2])$',                                # /32
            ErrorMessage = 'Invalid Ipv4Cidr block.'
        )]
        [string]
        $Ipv4Cidr,

        [Parameter()]
        [ValidateScript(
            {
                $_prefix_pattern = "[0-9]|[1-9][0-9]|1[0-1][0-9]|12[0-8]";
                $_hex_pattern    = "[0-9a-fA-F]";
                $_hextet_pattern = "$($_hex_pattern){1,4}";

                $_ipv6_0 = "($($_hextet_pattern):){7}$($_hextet_pattern)";
                $_ipv6_1 = "($($_hextet_pattern):){1,7}:";
                $_ipv6_2 = "($($_hextet_pattern):){1,6}(:$($_hextet_pattern)){1,1}";
                $_ipv6_3 = "($($_hextet_pattern):){1,5}(:$($_hextet_pattern)){1,2}";
                $_ipv6_4 = "($($_hextet_pattern):){1,4}(:$($_hextet_pattern)){1,3}";
                $_ipv6_5 = "($($_hextet_pattern):){1,3}(:$($_hextet_pattern)){1,4}";
                $_ipv6_6 = "($($_hextet_pattern):){1,2}(:$($_hextet_pattern)){1,5}";
                $_ipv6_7 = "($($_hextet_pattern):){1,1}(:$($_hextet_pattern)){1,6}";
                $_ipv6_8 = ":(:$($_hextet_pattern)){1,7}";
                $_ipv6_9 = "::";

                $_ip_pattern = '^(' +
                    $_ipv6_0 + '|' + $_ipv6_1 + '|' + $_ipv6_2 + '|' + $_ipv6_3 + '|' + $_ipv6_4 + '|' +
                    $_ipv6_5 + '|' + $_ipv6_6 + '|' + $_ipv6_7 + '|' + $_ipv6_8 + '|' + $_ipv6_9 + ')$'

                $_cidr_pattern = $_ip_pattern.TrimEnd('$') + "\/($($_prefix_pattern))$";

                if ($_ -match $_cidr_pattern) { $true }
                else {
                    throw [System.Management.Automation.ValidationMetadataException]::new("Invalid Ipv6Cidr.")
                }
            }
        )]
        [string]
        $Ipv6Cidr,

        [Parameter()]
        [Amazon.EC2.Model.Tag[]]
        $Tag,

        [Parameter()]
        [switch]
        $DoNotCopyTags
    )

    BEGIN
    {
        # For easy pickup.
        $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name
        $_param_set   = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_subnet_id         = $SubnetId
        $_subnet_name       = $SubnetName
        $_dst_name          = $DestinationName
        $_availability_zone = $AvailabilityZone
        $_ipv4_cidr         = $Ipv4Cidr
        $_ipv6_cidr         = $Ipv6Cidr
        $_tag               = $Tag
        $_copy_tags         = -not $DoNotCopyTags.IsPresent

        # Configure the filter to query the Subnet.
        $_filter_name  = $_param_set -eq 'SubnetId' ? 'subnet-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'SubnetId' ? $_subnet_id : $_subnet_name

        # Query the Subnet to copy first.
        try {
            $_subnet_list = Get-EC2Subnet -Verbose:$false -Filter @{Name = $_filter_name; Values = $_filter_value}
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If no subnet matched the filter value, exit early.
        if (-not $_subnet_list)
        {
            Write-Error "No Subnet was found for '$_filter_value'."
            return
        }

         # If multiple Subnets matched the filter value, exit early.
        if ($_subnet_list.Count -gt 1) {
            Write-Error "Multiple Subnets were found for '$_filter_value'. It must match only one Subnet."
            return
        }

        # Save a referece to the source Subnet.
        $_src_subnet = $_subnet_list[0]

        # For easy pickup.
        $_src_subnet_id                            = $_src_subnet.SubnetId
        $_src_ipv4_cidr                            = $_src_subnet.CidrBlock
        $_src_ipv6_cidr                            = $_src_subnet.Ipv6CidrBlockAssociationSet.Ipv6CidrBlock
        $_src_availability_zone                    = $_src_subnet.AvailabilityZone
        $_src_enable_resource_name_dns_aaaa_record = $_src_subnet.PrivateDnsNameOptionsOnLaunch.EnableResourceNameDnsAAAARecord
        $_src_enable_resource_name_dns_a_record    = $_src_subnet.PrivateDnsNameOptionsOnLaunch.EnableResourceNameDnsARecord
        $_src_enable_dns_64                        = $_src_subnet.EnableDns64
        $_src_hostname_type                        = $_src_subnet.PrivateDnsNameOptionsOnLaunch.HostnameType
        $_src_map_public_ip_on_launch              = $_src_subnet.MapPublicIpOnLaunch
        $_src_assign_ipv6_address_on_creation      = $_src_subnet.AssignIpv6AddressOnCreation

        # Query the source Subnet's Route Table and  Network ACL
        try {
            $_src_route_table = Get-EC2RouteTable -Verbose:$false -Filter @{
                Name   = 'association.subnet-id'
                Values = $_src_subnet_id
            }

            $_src_nacl = Get-EC2NetworkAcl -Verbose:$false -Filter @{
                Name   = 'association.subnet-id'
                Values = $_src_subnet_id
            }

            if ($_src_route_table)
            {
                $_src_route_table_id   = $_src_route_table.RouteTableId
                $_src_route_table_name = $_src_route_table.Tags |
                    Where-Object Key -eq 'Name' | Select-Object -ExpandProperty Value
            }

            if ($_src_nacl)
            {
                $_src_nacl_id   = $_src_nacl.NetworkAclId
                $_src_nacl_name = $_src_nacl.Tags | Where-Object Key -eq 'Name' | Select-Object -ExpandProperty Value
            }
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-Error $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # Generate a friendly display string for the source subnet.
        $_format_src_csubnet = $_src_subnet | Get-ResourceString `
            -IdPropertyName 'SubnetId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

        # Work out the destination Availability Zone.
        $_dst_availability_zone = [string]::IsNullOrEmpty($_availability_zone) `
            ? $_src_availability_zone : $_availability_zone

        # Work out the destination IPv4 CIDR block.
        if ($PSBoundParameters.ContainsKey('IPv4Cidr'))
        {
            $_dst_ipv4_cidr = [string]::IsNullOrEmpty($_ipv4_cidr) `
                ? $null
                : $_ipv4_cidr
        }
        else
        {
            $_dst_ipv4_cidr = [string]::IsNullOrEmpty($_src_ipv4_cidr) `
                ? $null
                : ((New-IPv4Subnet $_src_ipv4_cidr).Next() | Select-Object -First 1)?.ToString()
        }

        # Work out the destination IPv6 CIDR block.
        if ($PSBoundParameters.ContainsKey('IPv6Cidr'))
        {
            $_dst_ipv6_cidr = [string]::IsNullOrEmpty($_ipv6_cidr) `
                ? $null
                : $_ipv6_cidr
        }
        else
        {
            $_dst_ipv6_cidr = [string]::IsNullOrEmpty($_src_ipv6_cidr) `
                ? $null
                : ((New-IPv6Subnet $_src_ipv6_cidr).Next() | Select-Object -First 1).ToString()
        }

        # If there are no specified/available subnets to assign to the destination subnet, fail early here.
        if (-not $_dst_ipv4_cidr -and -not $_dst_ipv6_cidr) {

            Write-Error `
                'Unable to work out CIDR assignment for the destination subnet.' +
                'At least an IPv4 or an IPv6 CIDR block must be assigned to the destination subnet.'
            return
        }

        # Prepare TagSpecification parameter.
        $_make_tags_with_name    = { New-TagSpecification -ResourceType subnet -Tag $_tag -Name $_dst_name}
        $_make_tags_without_name = { New-TagSpecification -ResourceType subnet -Tag $_tag }
        $_has_name               = $PSBoundParameters.ContainsKey('DestinationName')
        $_tag_specification      = $_has_name ? (& $_make_tags_with_name) : (& $_make_tags_without_name)

        # If caller did not specified -Tag and -Name, create a new TagSpecification using the source Subnet's Tags.
        if (-not $_tag_specification -and $_copy_tags)
        {
            $_tag_specification = New-TagSpecification -Tag $_src_subnet.Tags
        }

        # If caller specified -Tag or -Name, we copy only the delta Tags.
        if ($_tag_specification -and $_copy_tags)
        {
            $_dst_keys   = $_tag_specification.Tags | Select-Object -ExpandProperty Key
            $_delta_tags = $_src_subnet.Tags | Where-Object Key -notin $_dst_keys

            if ($_delta_tags.Count -gt 0)
            {
                $_tag_specification.Tags.AddRange([Amazon.EC2.Model.Tag[]]$_delta_tags)
            }
        }

        # Display What-If/Confirm prompt.
        if (-not $PSCmdlet.ShouldProcess($_format_src_csubnet, "Copy Subnet")) { return }

        # 1. Create the destination Subnet.
        try {
            # Prepare parameters for New-EC2Subnet cmdlet to be invoked.
            $_new_params = @{
                VpcId            = $_src_subnet.VpcId
                AvailabilityZone = $_dst_availability_zone
                CidrBlock        = $_dst_ipv4_cidr
                Ipv6CidrBlock    = $_dst_ipv6_cidr
                Ipv6Native       = (-not $_dst_ipv4_cidr)
                TagSpecification = $_tag_specification
            }

            # Create the the destination Subnet.
            $_dst_subnet = New-EC2Subnet @_new_params -Verbose:$false

            # Save a reference to the destination Subnet's Subnet ID for easy pick up later.
            $_dst_subnet_id = $_dst_subnet.SubnetId

            # Return the destination Subnet's Subnet ID.
            Write-Message -Output "|- Destination SubnetId:    $_dst_subnet_id"
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Since no subnet is created, exit early here and continue the pipeline.
            return
        }

        # 2. Copy subnet attribute: AAAA record.
        try {
            # Disply progress/verbose message for calling the API to apply the subnet attribute.
            Write-Message -Progress `
                -Activity $_cmdlet_name `
                -Message (
                    '|- Applying subnet attribute enable-resource-name-dns-aaaa-record-on-launch = {0}' -f
                    $_src_enable_resource_name_dns_aaaa_record)

            # Call the API to apply the atrribute.
            Edit-EC2SubnetAttribute $_dst_subnet_id -Verbose:$false `
                -EnableResourceNameDnsAAAARecordOnLaunch $_src_enable_resource_name_dns_aaaa_record `

        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)
        }

        # 3. Copy subnet attribute: A record.
        try {
            # Disply progress/verbose message for calling the API to apply the subnet attribute.
            Write-Message -Progress `
                -Activity $_cmdlet_name `
                -Message (
                    '|- Applying subnet attribute enable-resource-name-dns-a-record-on-launch = {0}' -f
                    $_src_enable_resource_name_dns_a_record)

            # Call the API to apply the atrribute.
            Edit-EC2SubnetAttribute $_dst_subnet_id -Verbose:$false `
                -EnableResourceNameDnsARecordOnLaunch $_src_enable_resource_name_dns_a_record `
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)
        }

        # 4. Copy subnet attribute: DNS64.
        try {
            # Disply progress/verbose message for calling the API to apply the subnet attribute.
            Write-Message -Progress `
                -Activity $_cmdlet_name `
                -Message "|- Applying subnet attribute enable-dns64 = $($_src_enable_dns_64)"

            # Call the API to apply the atrribute.
            Edit-EC2SubnetAttribute $_dst_subnet_id -EnableDns64 $_src_enable_dns_64 -Verbose:$false
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)
        }

        # 5. Copy subnet attribute: Auto-assign public IP.
        try {
            # Disply progress/verbose message for calling the API to apply the subnet attribute.
            Write-Message -Progress `
                -Activity $_cmdlet_name `
                -Message "|- Applying subnet attribute map-public-ip-on-launch = $($_src_map_public_ip_on_launch)"

            # Call the API to apply the atrribute.
            Edit-EC2SubnetAttribute $_dst_subnet_id -MapPublicIpOnLaunch $_src_map_public_ip_on_launch -Verbose:$false
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)
        }

        # 6. Copy subnet attribute: Auto-assign IPv6 address.
        try {
            # Disply progress/verbose message for calling the API to apply the subnet attribute.
            Write-Message -Progress `
                -Activity $_cmdlet_name `
                -Message (
                    '|- Applying subnet attribute assign-ipv6-address-on-creation = {0}' -f
                    $_src_assign_ipv6_address_on_creation)

            # Call the API to apply the atrribute.
            Edit-EC2SubnetAttribute $_dst_subnet_id -Verbose:$false `
                -AssignIpv6AddressOnCreation $_src_assign_ipv6_address_on_creation
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)
        }

        # 7. Copy subnet attribute: Hostname type
        try {
            # Disply progress/verbose message for calling the API to apply the subnet attribute.
            Write-Message -Progress `
                -Activity $_cmdlet_name `
                -Message "|- Applying subnet attribute private-dns-hostname-type-on-launch = $($_src_hostname_type)"

            # Call the API to apply the atrribute.
            Edit-EC2SubnetAttribute $_dst_subnet_id -PrivateDnsHostnameTypeOnLaunch $_src_hostname_type -Verbose:$false
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)
        }

        # 8. Copy route table association.
        try {
            if ($_src_route_table)
            {
                $_dst_route_table_id   = $_src_route_table_id
                $_dst_route_table_name = [string]::IsNullOrEmpty($_src_route_table_name) `
                    ? '' : "[$_src_route_table_name]"

                Write-Message -Progress `
                    -Activity $_cmdlet_name `
                    -Message "|- Associating route table $_dst_route_table_id $_dst_route_table_name"

                $_dst_roubte_table_assoc_id = Register-EC2RouteTable -Verbose:$false `
                    $_dst_route_table_id $_dst_subnet_id

                # Return destination Subnet's Route Table Association ID to the caller.
                Write-Message -Output "|- RouteTableAssociationId: $_dst_roubte_table_assoc_id"
            }
            else {
                Write-Message `
                    -Output '|- RouteTableAssociationId: Source subnet has no explicit route association to copy'
            }
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)
        }

        # 9. Copy network ACL association.
        try {
            if ($_src_nacl -and -not $_src_nacl.IsDefault) {

                $_dst_nacl_id   = $_src_nacl_id
                $_dst_nacl_name = [string]::IsNullOrEmpty($_src_nacl_name) ? '' : "[$_src_nacl_name]"

                Write-Message -Progress `
                    -Activity $_cmdlet_name `
                    -Message "|- Associating network ACL $_dst_nacl_id $_dst_nacl_name."

                # When destination subnet is created, it is automatically associated with the default network ACL
                # We need to retrive that association ID.
                $_default_nacl_assoc_id = Get-EC2NetworkAcl -Verbose:$false -Filter @{
                    Name   = 'association.subnet-id'
                    Values = $_dst_subnet_id
                } |
                Select-Object -ExpandProperty Associations | Where-Object SubnetId -eq $_dst_subnet_id |
                Select-Object -ExpandProperty NetworkAclAssociationId

                # A new association ID will be returned when we set the association to a different newtwork ACL.
                $_dst_nacl_assoc_id = Set-EC2NetworkAclAssociation -Verbose:$false $_default_nacl_assoc_id $_src_nacl_id
            }
            else {
                Write-Message -Progress `
                    -Activity $_cmdlet_name `
                    -Message (
                        '|- Source subnet has no explicit network ACL association - ' +
                        'Retrieving the default network ACL association for the destination subnet.'
                    )

                # Since we don't need to associate a non-default network ACL,
                # we can just grab the default network ACL association ID to return to the caller.
                $_dst_nacl_assoc_id = Get-EC2NetworkAcl -Verbose:$false -Filter @{
                    Name   = 'association.subnet-id'
                    Values = $_dst_subnet_id
                } |
                Select-Object -ExpandProperty Associations | Where-Object SubnetId -eq $_dst_subnet_id |
                Select-Object -ExpandProperty NetworkAclAssociationId
            }

            # Return destination Subnet's Network ACL Association ID to the caller.
            Write-Message -Output "|- NetworkAclAssociationId: $_dst_nacl_assoc_id"
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)
        }
    }
}