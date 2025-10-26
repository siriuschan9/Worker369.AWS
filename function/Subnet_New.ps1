using namespace System.Management.Automation
using namespace Worker369.Utility

<#
.SYNOPSIS
This cmdlet creates a new VPC. If Subnet attributes are specified, they will be applied to the new Subnet.
To generate a cmdlet template, type: "Get-Help New-Subnet -Examples"

.EXAMPLE
New-Subnet -WhatIf `
           -VpcId vpc-12345678901234567 `
           -AvailabilityZone ap-southeast-1a `
           -Ipv4Cidr 172.31.0.0/24 `
           -Ipv6Cidr 172:31::/64 `
           -EnableDns64 $true `
           -EnableARecord $true `
           -EnableAAAARecord $true `
           -HostnameType 'resource-name' `
           -EnableAutoAssignPublicIP $true `
           -EnableAutoAssignIpv6Address $true `
           -Tag @{Key = 'Environment'; Value = 'Test'} `
           'subnet-example-1'
#>
function New-Subnet
{
    [Alias('subnet_add')]
    [CmdletBinding(SupportsShouldProcess)]

    param (
        [Parameter(Position = 0)]
        [string]
        $Name,

        [Parameter(ParameterSetName = 'VpcId', Mandatory, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^vpc-[0-9a-f]{17}$', ErrorMessage = 'Invalid VpcId.')]
        [String]
        $VpcId,

        [Parameter(ParameterSetName = 'VpcName', Mandatory)]
        [string]
        $VpcName,

        [Parameter(Mandatory)]
        [String]
        $AvailabilityZone,

        [ValidatePattern(
            '^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}' + # 255.255.255.
            '([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])' +         # 255
            '\/([0-9]|[1-2][0-9]|3[0-2])$',                                # /32
            ErrorMessage = 'Invalid Ipv4Cidr block.'
        )]
        [String]
        $Ipv4Cidr,

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
        [String]
        $Ipv6Cidr,

        [switch]
        $EnableAAAARecord,

        [switch]
        $EnableARecord,

        [switch]
        $EnableDns64,

        [switch]
        $EnableAutoAssignIpv6Address,

        [switch]
        $EnableAutoAssignPublicIp,

        [Amazon.EC2.HostnameType]
        $HostnameType,

        [Amazon.EC2.Model.Tag[]]
        $Tag
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
        $_name                            = $Name
        $_vpc_id                          = $VpcId
        $_vpc_name                        = $VpcName
        $_availability_zone               = $AvailabilityZone
        $_ipv4_cidr                       = $Ipv4Cidr
        $_ipv6_cidr                       = $Ipv6Cidr
        $_enable_aaaa_record              = $EnableAAAARecord.IsPresent
        $_enable_a_record                 = $EnableARecord.IsPresent
        $_enable_dns_64                   = $EnableDns64.IsPresent
        $_enable_auto_assign_ipv6_address = $EnableAutoAssignIpv6Address.IsPresent
        $_enable_auto_assign_public_ip    = $EnableAutoAssignPublicIp.IsPresent
        $_hostname_type                   = $HostnameType
        $_tag                             = $Tag

        # At least one of IPv4 or IPv6 CIDR must be specified.
        if ([string]::IsNullOrEmpty($_ipv4_cidr) -and [string]::IsNullOrEmpty($_ipv6_cidr))
        {
            Write-Error('No CIDR block specified. Please specify at least either on IPv4 CIDR or an IPv6 CIDR.')
            return
        }

        # Configure the filter to query the VPC.
        $_filter_name  = $_param_set -eq 'VpcId' ? 'vpc-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'VpcId' ? $_vpc_id : $_vpc_name

        # Query the VPC to add the subnet first.
        try {
            $_vpc_list = Get-EC2Vpc -Verbose:$false -Filter @{Name = $_filter_name; Values = $_filter_value}
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If no VPC matched the filter value, exit early.
        if (-not $_vpc_list)
        {
            Write-Error "No VPC was found for '$_filter_value'."
            return
        }

        # If multiple VPC matched the filter value, exit early.
        if ($_vpc_list.Count -gt 1)
        {
            Write-Error "Multiple VPC was found for '$_filter_value'. It must matched exactly one VPC."
            return
        }

        # Save a reference to the filtered VPC.
        $_vpc = $_vpc_list[0]

        # Prepare TagSpecification parameter.
        $_make_tags_with_name    = { New-TagSpecification -ResourceType subnet -Tag $_tag -Name $_name}
        $_make_tags_without_name = { New-TagSpecification -ResourceType subnet -Tag $_tag }
        $_has_name               = $PSBoundParameters.ContainsKey('Name')
        $_tag_specification      = $_has_name ? (& $_make_tags_with_name) : (& $_make_tags_without_name)

        # Generate a friendly display string for the VPC.
        $_format_vpc = $_vpc | Get-ResourceString `
            -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

        # Display What-If/Confirm prompt.
        if (-not $PSCmdlet.ShouldProcess("$_format_vpc | $_availability_zone'", 'Create Subnet')) { return }

        try {
            # Call the API to create new subnet.
            $_new_subnet = New-EC2Subnet -Verbose:$false `
                -VpcId            $_vpc.VpcId `
                -AvailabilityZone $_availability_zone `
                -CidrBlock        ([string]::IsNullOrEmpty($_ipv4_cidr) ? $null : $_ipv4_cidr) `
                -Ipv6CidrBlock    ([string]::IsNullOrEmpty($_ipv6_cidr) ? $null : $_ipv6_cidr) `
                -TagSpecification $_tag_specification `
                -Ipv6Native       (-not $Ipv4Cidr)
        }
        catch{
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Since no Subnet is created, exit early here.
            return
        }

        # Save a reference to Subnet ID for easy pick up later.
        $_new_subnet_id = $_new_subnet.SubnetId

        # Return subnet ID.
        Write-Message -Output "SubnetId: $_new_subnet_id"

        # 1. Apply subnet attribute: AAAA record.
        if ($PSBoundParameters.ContainsKey('EnableAAAARecord'))
        {
            try {
                # Disply progress/verbose message for calling the API to apply the subnet attribute.
                Write-Message -Progress `
                    -Activity $_cmdlet_name `
                    -Message (
                        '|- Applying subnet attribute enable-resource-name-dns-aaaa-record-on-launch = {0}' -f
                        $_enable_aaaa_record)

                # Call the API to apply the atrribute.
                Edit-EC2SubnetAttribute $_new_subnet_id `
                    -Verbose:$false -EnableResourceNameDnsAAAARecordOnLaunch $_enable_aaaa_record
            }
            catch {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                # Report error as non-terminating.
                $PSCmdlet.WriteError($_)
            }
        }

        # 2. Apply subnet attribute: A record.
        if ($PSBoundParameters.ContainsKey('EnableARecord'))
        {
            try {
                # Disply progress/verbose message for calling the API to apply the subnet attribute.
                Write-Message -Progress `
                    -Activity $_cmdlet_name `
                    -Message (
                        '|- Applying subnet attribute enable-resource-name-dns-a-record-on-launch = {0}' -f
                        $_enable_a_record)

                # Call the API to apply the atrribute.
                Edit-EC2SubnetAttribute $_new_subnet_id `
                    -Verbose:$false -EnableResourceNameDnsARecordOnLaunch $_enable_a_record
            }
            catch {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                # Report error as non-terminating.
                $PSCmdlet.WriteError($_)
            }
        }

        # 3. Apply subnet attribute: DNS64.
        if ($PSBoundParameters.ContainsKey('EnableDns64'))
        {
            try {
                # Disply progress/verbose message for calling the API to apply the subnet attribute.
                Write-Message -Progress `
                    -Activity $_cmdlet_name `
                    -Message "|- Applying subnet attribute enable-dns64 = $($_enable_dns_64)"

                # Call the API to apply the atrribute.
                Edit-EC2SubnetAttribute -Verbose:$false -EnableDns64 $_enable_dns_64 $_new_subnet.SubnetId
            }
            catch {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                # Report error as non-terminating.
                $PSCmdlet.WriteError($_)
            }
        }

        # 4. Apply subnet attribute: Auto-assign public IP.
        if ($PSBoundParameters.ContainsKey('EnableAutoAssignPublicIp'))
        {
            try {
                # Disply progress/verbose message for calling the API to apply the subnet attribute.
                Write-Message -Progress `
                    -Activity $_cmdlet_name `
                    -Message "|- Applying subnet attribute map-public-ip-on-launch = $($_enable_auto_assign_public_ip)"

                # Call the API to apply the atrribute.
                Edit-EC2SubnetAttribute $_new_subnet_id `
                    -Verbose:$false -MapPublicIpOnLaunch $_enable_auto_assign_public_ip
            }
            catch {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                # Report error as non-terminating.
                $PSCmdlet.WriteError($_)
            }
        }

        # 5. Apply subnet attribute: Auto-assign IPv6 address.
        if ($PSBoundParameters.ContainsKey('EnableAutoAssignIpv6Address'))
        {
            try {
                # Disply progress/verbose message for calling the API to apply the subnet attribute.
                Write-Message -Progress `
                    -Activity $_cmdlet_name `
                    -Message (
                        '|- Applying subnet attribute assign-ipv6-address-on-creation = {0}' -f
                        $_enable_auto_assign_ipv6_address)

                # Call the API to apply the atrribute.
                Edit-EC2SubnetAttribute $_new_subnet_id `
                    -Verbose:$false -AssignIpv6AddressOnCreation $_enable_auto_assign_ipv6_address
            }
            catch {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                # Report error as non-terminating.
                $PSCmdlet.WriteError($_)
            }
        }

        # 6. Apply subnet attribute: Host name type.
        if ($PSBoundParameters.ContainsKey('HostnameType'))
        {
            try {
                # Disply progress/verbose message for calling the API to apply the subnet attribute.
                Write-Message -Progress `
                    -Activity $_cmdlet_name `
                    -Message "|- Applying subnet attribute private-dns-hostname-type-on-launch = $($_hostname_type)"

                # Call the API to apply the atrribute.
                Edit-EC2SubnetAttribute $_new_subnet_id `
                    -Verbose:$false -PrivateDnsHostnameTypeOnLaunch $_hostname_type
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

Register-ArgumentCompleter -CommandName 'New-Subnet' -ParameterName 'Ipv4Cidr' -ScriptBlock {
    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_vpc_id   = $_fake_bound_parameters['VpcId']
    $_vpc_name = $_fake_bound_parameters['VpcName']

    if (-not [string]::IsNullOrEmpty($_vpc_id)) {
        $_vpc = Get-EC2Vpc -Verbose:$false -Filter @{ Name = 'vpc-id'; Values = $_vpc_id }
    }
    elseif (-not [string]::IsNullOrEmpty($_vpc_name)) {
        $_vpc = Get-EC2Vpc -Verbose:$false -Filter @{ Name = 'tag:Name'; Values = $_vpc_name}
    }
    else { return }

    # If no VPC can be identified, exit early.
    if (-not $_vpc -and $_vpc.Count -gt 1) { return }

    # Get the list of IPv4 CIDR blocks in the VPC.
    $_vpc_cidr_list = $_vpc.CidrBlockAssociationSet | Select-Object -ExpandProperty CidrBlock

    # Get all assigned CIDRs in the VPC.
    $_subnet_cidr_list = Get-EC2Subnet -Verbose:$false -Filter @{
        Name   = 'vpc-id'
        Values = $_vpc.VpcId
    } | Select-Object -ExpandProperty CidrBlock

    $_dim_style   = [PSStyle]::Instance.Dim
    $_reset_style = [PSStyle]::Instance.Reset

    # Go through each VPC CIDR block
    foreach ($_vpc_cidr in $_vpc_cidr_list)
    {
        $_root = [IPv4CidrNode]::new($_vpc_cidr)

        $_root.MapSubnets($_subnet_cidr_list) | Where-Object CIDR -Like "$_word_to_complete*" | ForEach-Object {

            $_list_item = $_.IsMapped `
                ? "$_dim_style|- Allocated: $($_.CIDR)$_reset_style"
                : "|- Available: $($_.CIDR)"

            [CompletionResult]::new(
                $_.CIDR,          # completionText
                $_list_item,      # listItemText
                'ParameterValue', # resultType
                $_                # toolTip
            )
        }
    }
}

Register-ArgumentCompleter -CommandName 'New-Subnet' -ParameterName 'Ipv6Cidr' -ScriptBlock {
    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_vpc_id   = $_fake_bound_parameters['VpcId']
    $_vpc_name = $_fake_bound_parameters['VpcName']

    if (-not [string]::IsNullOrEmpty($_vpc_id)) {
        $_vpc = Get-EC2Vpc -Verbose:$false -Filter @{ Name = 'vpc-id'; Values = $_vpc_id }
    }
    elseif (-not [string]::IsNullOrEmpty($_vpc_name)) {
        $_vpc = Get-EC2Vpc -Verbose:$false -Filter @{ Name = 'tag:Name'; Values = $_vpc_name}
    }
    else { return }

    # If no VPC can be identified, exit early.
    if (-not $_vpc -and $_vpc.Count -gt 1) { return }

    # Get the list of IPv6 CIDR blocks in the VPC.
    $_vpc_cidr_list = $_vpc.Ipv6CidrBlockAssociationSet | Select-Object -ExpandProperty Ipv6CidrBlock

    # Get all assigned CIDRs in the VPC.
    $_subnet_cidr_list = Get-EC2Subnet -Verbose:$false -Filter @{
        Name   = 'vpc-id'
        Values = $_vpc.VpcId
    } | Select-Object -ExpandProperty Ipv6CidrBlockAssociationSet | Select-Object -ExpandProperty Ipv6CidrBlock

    $_dim_style   = [PSStyle]::Instance.Dim
    $_reset_style = [PSStyle]::Instance.Reset

    # Go through each VPC CIDR block
    foreach ($_vpc_cidr in $_vpc_cidr_list)
    {
        $_root = [IPv6CidrNode]::new($_vpc_cidr)

        $_root.MapSubnets($_subnet_cidr_list) | Where-Object CIDR -Like "$_word_to_complete*" | ForEach-Object {

            $_list_item = $_.IsMapped `
                ? "$_dim_style|- Allocated: $($_.CIDR)$_reset_style"
                : "|- Available: $($_.CIDR)"

            [CompletionResult]::new(
                $_.CIDR,          # completionText
                $_list_item,      # listItemText
                'ParameterValue', # resultType
                $_                # toolTip
            )
        }
    }
}