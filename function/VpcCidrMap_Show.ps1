function Show-VpcCidrMap
{
    [Alias('vpc_cidrmap_show')]
    [CmdletBinding(DefaultParameterSetName = 'VpcName')]
    param (
        [Parameter(ParameterSetName = 'VpcId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^vpc-[0-9a-f]{17}$', ErrorMessage = 'Invalid VpcId.')]
        [string]
        $VpcId,

        [Parameter(ParameterSetName = 'VpcName', Mandatory, Position = 0)]
        [string]
        $VpcName,

        [Parameter()]
        [ValidateSet('IPv4', 'IPv6', 'Both')]
        [string]
        $IPVersion = 'Both',

        [Parameter()]
        [switch]
        $PlainText,

        [Parameter()]
        [switch]
        $NoRowSeparator
    )

    BEGIN
    {
        # For easy Pickup
        $_param_set = $PSCmdlet.ParameterSetName
        $_dim       = [System.Management.Automation.PSStyle]::Instance.Dim
        $_reset     = [System.Management.Automation.PSStyle]::Instance.Reset
    }

    PROCESS
    {
        # Use snake_case.
        $_vpc_id            = $VpcId
        $_vpc_name          = $VpcName
        $_ip_version        = $IPVersion
        $_plain_text        = $PlainText.IsPresent
        $_no_rows_separator = $NoRowSeparator.IsPresent

        # Configure the filter to query the VPC.
        $_filter_name  = $_param_set -eq 'VpcId' ? 'vpc-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'VpcId' ? $_vpc_id : $_vpc_name

        # Query the list of VPC first.
        try {
            $_vpc_list    = Get-EC2Vpc -Verbose:$false -Filter @{Name = $_filter_name; Values = $_filter_value}
            $_subnet_list = Get-EC2Subnet -Verbose:$false -Filter @{Name = 'vpc-id'; Values = $_vpc_list.VpcId}
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
            Write-Error "Multiple VPC were found for '$_filter_value'."
            return
        }

        $_vpc = $_vpc_list[0]

        # Initialize a list to store the CidrNodes.
        $_results = [System.Collections.Generic.List[object]]::new()

        if ($_ip_version -in @('IPv4', 'Both'))
        {
            $_vpc.CidrBlockAssociationSet.CidrBlock | ForEach-Object {

                $_vpc_cidr = $_

                $_matched_subnets = $_subnet_list | Where-Object {
                    ($_.VpcId -eq $_vpc.VpcId) -and
                    ($_.CidrBlock) -and
                    (Test-IPv4CidrOverlap $_vpc_cidr $_.CidrBlock)
                }

                $_root_subnet = $_vpc_cidr | New-IPv4Subnet

                $_child_subnets = $_matched_subnets.Count -gt 0 `
                    ? ($_matched_subnets.CidrBlock | New-IPv4Subnet)
                    : $null

                $_root_node   = [Worker369.Utility.Ipv4CidrNode]::new($_root_subnet)
                $_child_nodes = $_root_node.MapSubnets($_child_subnets)

                $_current_results = $_child_nodes | Select-Object `
                    @{
                        Name = 'VpcCidr'
                        Expression = { $_vpc_cidr }
                    },
                    @{
                        Name = 'Allocated'
                        Expression = { New-Checkbox -PlainText:$_plain_text $_.IsMapped }
                    },
                    @{
                        Name = 'CidrBlock'
                        Expression = {
                            $_cidr = $_.CIDR
                            $_.IsMapped -or $_plain_text ? "$_cidr" : "$_dim$_cidr$_reset"
                        }
                    },
                    @{
                        Name = 'FirstIP'
                        Expression = {
                            $_ip = $_.CIDR.FirstIP
                            $_.IsMapped -or $_plain_text ? "$_ip" : "$_dim$_ip$_reset"
                        }
                    },
                    @{
                        Name = 'LastIP'
                        Expression = {
                            $_ip = $_.CIDR.LastIP
                            $_.IsMapped -or $_plain_text ? "$_ip" : "$_dim$_ip$_reset"
                        }
                    },
                    @{
                        Name = 'PrefixLength'
                        Expression = {
                            $_size = $_.CIDR.PrefixLength
                            $_.IsMapped -or $_plain_text ? "$_size" : "$_dim$_size$_reset"
                        }
                    },
                    @{
                        Name = 'Subnet'
                        Expression = {
                            $_subnet_cidr   = $_.CIDR.ToString()
                            $_subnet        = $_matched_subnets | Where-Object { $_.CidrBlock -eq $_subnet_cidr }
                            $_subnet_string = $_subnet | Get-ResourceString `
                                -IdPropertyName 'SubnetId' `
                                -TagPropertyName 'Tags' `
                                -PlainText:$_plain_text

                            $_.IsMapped -or $_plain_text `
                                ? "$($_subnet_string)"
                                : "$($_dim)$($_subnet_string)$($_reset)"
                        }
                    }

                # Add these CidrNodes to the result list.
                $_results.AddRange(@($_current_results))
            }
        }

        if ($_ip_version -in @('IPv6', 'Both'))
        {
            $_vpc.Ipv6CidrBlockAssociationSet | Where-Object { $_.Ipv6CidrBlockState.State -eq 'associated' } |
            Select-Object -ExpandProperty Ipv6CidrBlock | ForEach-Object {

                $_vpc_cidr = $_

                $_matched_subnets = $_subnet_list | Where-Object {
                    ($_.VpcId -eq $_vpc.VpcId) -and
                    ($_.Ipv6CidrBlockAssociationSet) -and
                    (Test-Ipv6CidrOverlap $_vpc_cidr $_.Ipv6CidrBlockAssociationSet.Ipv6CidrBlock)
                }

                $_root_subnet = $_vpc_cidr | New-IPv6Subnet

                $_child_subnets = $_matched_subnets.Count -gt 0 `
                    ? ($_matched_subnets.Ipv6CidrBlockAssociationSet.Ipv6CidrBlock | New-IPv6Subnet)
                    : $null

                $_root_node   = [Worker369.Utility.IPv6CidrNode]::new($_root_subnet)
                $_child_nodes = $_root_node.MapSubnets($_child_subnets)

                $_current_results = $_child_nodes | Select-Object `
                    @{
                        Name = 'VpcCidr'
                        Expression = { $_vpc_cidr }
                    },
                    @{
                        Name = 'Allocated'
                        Expression = { New-Checkbox -PlainText:$_plain_text $_.IsMapped }
                    },
                    @{
                        Name = 'CidrBlock'
                        Expression = {
                            $_cidr = $_.CIDR
                            $_.IsMapped -or $_plain_text ? "$_cidr" : "$_dim$_cidr$_reset"
                        }
                    },
                    @{
                        Name = 'FirstIP'
                        Expression = {
                            $_ip = $_.CIDR.FirstIP
                            $_.IsMapped -or $_plain_text ? "$_ip" : "$_dim$_ip$_reset"
                        }
                    },
                    @{
                        Name = 'LastIP'
                        Expression = {
                            $_ip = $_.CIDR.LastIP
                            $_.IsMapped -or $_plain_text ? "$_ip" : "$_dim$_ip$_reset"
                        }
                    },
                    @{
                        Name = 'PrefixLength'
                        Expression = {
                            $_size = $_.CIDR.PrefixLength
                            $_.IsMapped -or $_plain_text ? "$_size" : "$_dim$_size$_reset"
                        }
                    },
                    @{
                        Name = 'Subnet'
                        Expression = {
                            $_subnet_cidr = $_.CIDR.ToString()
                            $_subnet      = $_matched_subnets | Where-Object {
                                $_.Ipv6CidrBlockAssociationSet.Ipv6CidrBlock -contains $_subnet_cidr
                            }

                            $_subnet_string = $_subnet | Get-ResourceString `
                                -IdPropertyName 'SubnetId' `
                                -TagPropertyName 'Tags' `
                                -PlainText:$_plain_text

                            $_.IsMapped -or $_plain_text `
                                ? "$($_subnet_string)"
                                : "$($_dim)$($_subnet_string)$($_reset)"
                        }
                    }

                # Add these CidrNodes to the result list.
                $_results.AddRange(@($_current_results))
            }
        }

        # Print out the Cidr Maps - This is a list of Cidr Nodes grouped by the VPC CIDR block.
        $_results | Format-Column `
            -PlainText:$_plain_text `
            -NoRowSeparator:$_no_rows_separator `
            -GroupBy VpcCidr `
            -AlignLeft 'Allocated' `
            -AlignRight 'PrefixLength'
    }
}