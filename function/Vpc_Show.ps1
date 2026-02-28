using namespace System.Collections
using namespace System.Collections.Generic
using namespace Worker369.Utility

function Show-Vpc
{
    [CmdletBinding()]
    [Alias('vpc_show')]
    param (
        [Parameter(Position = 0)]
        [ValidateSet('BlockPublicAccess', 'Default', 'DhcpOptions', 'Dependencies',  'FlowLogs', 'Network')]
        [string]
        $View = 'Default',

        [Amazon.EC2.Model.Filter[]]
        $Filter,

        [ValidateSet('OwnerId', $null)]
        [string]
        $GroupBy = 'OwnerId',

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

    # Display a dimmed dash for zero - used for Dependencies view.
    $_style_number_settings = [NumberInfoSettings]::Make()
    $_style_number_settings.Format.Unscaled = "#,###;#,###;`e[2m-`e[0m"

    # Display an unstyled dash for zero - used for Dependencies view.
    $_plain_number_settings = [NumberInfoSettings]::Make()
    $_plain_number_settings.Format.Unscaled = '#,###;#,###;-'

    # Each view defines an array of property names.
    $_view_definition = @{
        Default = @(
            'VpcId', 'Name', 'State', 'Tenancy', 'Ipv4Cidr', 'Ipv6Cidr', 'IsDefault', 'DnsResolution' ,
            'DnsHostnames', 'NauMetrics', 'BlockPublicAccess'
        )
        Network = @(
            'VpcId', 'Name', 'Ipv4Cidr', 'Ipv6Cidr', 'InternetGateway', 'MainRouteTable', 'DefaultNetworkAcl'
        )
        Flowlogs = @(
            'VpcId', 'Name', 'CloudWatchLogs', 'KinesisDataFirehose', 'S3'
        )
        DhcpOptions = @(
            'VpcId', 'Name', 'DhcpOptionSet', 'DomainName', 'DnsServer', 'NtpServer', 'Ipv6LeaseTime'
        )
        Dependencies = @(
            'VpcId', 'Name', 'InternetGateways', 'NatGateways', 'RouteTables', 'NetworkAcls', 'Subnets',
            'SecurityGroups', 'ENIs', 'VpcPeering'
        )
        BlockPublicAccess = @(
            'VpcId', 'Name', 'ExclusionId', 'ExclusionMode', 'BlockResult','Ipv4Cidr', 'Ipv6Cidr'
        )
    }

    # Hashtable for Select-Object.
    $_select_definition = @{
        BlockPublicAccess = {
            $_.BlockPublicAccessStates.InternetGatewayBlockMode
        }
        BlockResult = {
            $_.BlockPublicAccessStates.InternetGatewayBlockMode
        }
        CloudWatchLogs = {
            $_has_flow_logs_in_cloudwatch = $_flow_logs_lookup.ContainsKey("$($_.VpcId), cloud-watch-logs")

            New-Checkbox -PlainText:$_plain_text $_has_flow_logs_in_cloudwatch
        }
        DefaultNetworkAcl = {
            $_network_acl_lookup[$_.VpcId] | Where-Object IsDefault |
            Get-ResourceString -IdPropertyName 'NetworkAclId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
        DhcpOptionSet = {
            $_dhcp_option_set_lookup[$_.VpcId] |
            Get-ResourceString -IdPropertyName 'DhcpOptionsId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
        DnsServer = {
            $_dhcp_option_set_lookup[$_.VpcId].DhcpConfigurations |
            Where-Object Key -eq 'domain-name-servers' | Select-Object -ExpandProperty Values
        }
        DomainName = {
            $_dhcp_option_set_lookup[$_.VpcId].DhcpConfigurations |
            Where-Object Key -eq 'domain-name' | Select-Object -ExpandProperty Values
        }
        DnsHostnames = {
            New-Checkbox -PlainText:$_plain_text $_dns_hostnames_lookup[$_.VpcId]
        }
        DnsResolution = {
            New-Checkbox -PlainText:$_plain_text $_dns_resolution_lookup[$_.VpcId]
        }
        ExclusionMode = {
            $_bpa_excl_lookup[$_.VpcId].InternetGatewayExclusionMode
        }
        ExclusionId = {
            $_bpa_excl_lookup[$_.VpcId].ExclusionId
        }
        ENIs = {
            $_num_eni      = $_eni_lookup ? $_eni_lookup[$_.VpcId].Count : 0
            $_num_settings = $_plain_text ? $_plain_number_settings : $_style_number_settings

            New-NumberInfo -FormatSettings $_num_settings $_num_eni
        }
        InternetGateway = {
            $_igw_lookup[$_.VpcId] | Get-ResourceString `
                -IdPropertyName 'InternetGatewayId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
        InternetGateways = {
            $_num_igw      = $_igw_lookup ? $_igw_lookup[$_.VpcId].Count : 0
            $_num_settings = $_plain_text ? $_plain_number_settings : $_style_number_settings

            New-NumberInfo -FormatSettings $_num_settings $_num_igw
        }
        Ipv4Cidr = {
            $_cidr_blocks = $_.CidrBlockAssociationSet |
                Where-Object { $_.CidrBlockState[0].State -eq 'associated' } |
                Select-Object -ExpandProperty CidrBlock

            $_cidr_blocks | ForEach-Object { New-IPv4Subnet $_ }
        }
        Ipv6Cidr = {
            $_ipv6_cidr_blocks = $_.Ipv6CidrBlockAssociationSet |
                Where-Object { $_.Ipv6CidrBlockState[0].State -eq 'associated' } |
                Select-Object -ExpandProperty Ipv6CidrBlock

            $_ipv6_cidr_blocks | ForEach-Object { New-IPv6Subnet $_ }
        }
        Ipv6LeaseTime = {
            $_dhcp_option_set_lookup[$_.VpcId].DhcpConfigurations |
            Where-Object Key -eq 'ipv6-address-preferred-lease-time' |
            Select-Object -ExpandProperty Values
        }
        IsDefault = {
            New-Checkbox -PlainText:$_plain_text $_.IsDefault
        }
        KinesisDataFirehose = {
            $_has_flow_logs_in_firehose = $_flow_logs_lookup.ContainsKey("$($_.VpcId), kinesis-data-firehose")

            New-Checkbox -PlainText:$_plain_text $_has_flow_logs_in_firehose
        }
        MainRouteTable = {
            $_route_table_lookup[$_.VpcId] | Where-Object {$_.Associations.Main -contains $true} |
            Get-ResourceString -IdPropertyName 'RouteTableId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
        Name = {
            $_.Tags | Where-Object Key -eq 'Name' | Select-Object -ExpandProperty Value
        }
        NatGateways = {
            $_num_ngw      = $_nat_lookup ? $_nat_lookup[$_.VpcId].Count : 0
            $_num_settings = $_plain_text ? $_plain_number_settings : $_style_number_settings

            New-NumberInfo -FormatSettings $_num_settings $_num_ngw
        }
        NauMetrics = {
            New-Checkbox -PlainText:$_plain_text $_nau_metrics_lookup[$_.VpcId]
        }
        NetworkAcls = {
            $_num_nacl     = $_network_acl_lookup[$_.VpcId].Count - 1
            $_num_settings = $_plain_text ? $_plain_number_settings : $_style_number_settings

            New-NumberInfo -FormatSettings $_num_settings $_num_nacl
        }
        NtpServer = {
            $_dhcp_option_set_lookup[$_.VpcId].DhcpConfigurations |
            Where-Object Key -eq 'ntp-servers' | Select-Object -ExpandProperty Values
        }
        OwnerId = {
            $_.OwnerId.ToString().Insert(4, '-').Insert(9, '-')
        }
        RouteTables = {
            $_num_rt       = $_route_table_lookup[$_.VpcId].Count - 1
            $_num_settings = $_plain_text ? $_plain_number_settings : $_style_number_settings

            New-NumberInfo -FormatSettings $_num_settings $_num_rt
        }
        S3 = {
            $_has_flow_logs_in_s3 = $_flow_logs_lookup.ContainsKey("$($_.VpcId), s3")

            New-Checkbox -PlainText:$_plain_text $_has_flow_logs_in_s3
        }
        SecurityGroups = {
            $_num_sg       = $_sg_lookup[$_.VpcId].Count - 1
            $_num_settings = $_plain_text ? $_plain_number_settings : $_style_number_settings

            New-NumberInfo -FormatSettings $_num_settings $_num_sg
        }
        State = {
            $_.State
        }
        Subnets = {
            $_num_subnet   = $_subnets_lookup ? $_subnets_lookup[$_.VpcId].Count : 0
            $_num_settings = $_plain_text ? $_plain_number_settings : $_style_number_settings

            New-NumberInfo -FormatSettings $_num_settings $_num_subnet
        }
        Tenancy = {
            $_.InstanceTenancy
        }
        VpcId = {
            $_.VpcId
        }
        VpcPeering = {
            $_num_accepter  = $_accepter_lookup  ? $_accepter_lookup[$_.VpcId].Count  : 0
            $_num_requester = $_requester_lookup ? $_requester_lookup[$_.VpcId].Count : 0

            $_num_settings  = $_plain_text ? $_plain_number_settings : $_style_number_settings

            New-NumberInfo -FormatSettings $_num_settings ($_num_accepter + $_num_requester)
        }
    }

    # Apply default sort order.
    if ($_group_by -eq 'OwnerId' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(2, 1) # => Sort by Name, VpcId
    }

    try {
        # Retrieve VPC.
        Write-Verbose "Retrieving VPCs."
        $_vpc_list = Get-EC2Vpc -Verbose:$false -Filter $_filter

        # Exit cmdlet if there are no VPCs returned.
        if (-not $_vpc_list) { return }

        # Retrieve DHCP option sets.
        if ($_view -in @('DhcpOptions'))
        {
            Write-Verbose  "Retrieving DHCP option sets."

            $_dhcp_option_sets = Get-EC2DhcpOption -Verbose:$false -Filter @{
                Name   = 'dhcp-options-id'
                Values = $_vpc_list.DhcpOptionsId
            } | Group-Object -AsHashTable DhcpOptionsId

            $_dhcp_option_set_lookup = [Hashtable]::new()

            foreach ($_vpc in $_vpc_list)
            {
                $_dhcp_option_set_lookup.Add(
                    $_vpc.VpcId,
                    $_dhcp_option_sets[$_vpc.DhcpOptionsId]
                )
            }
        }

        # Retrieve internet gateways.
        if ($_view -in @('Network', 'Dependencies'))
        {
            Write-Verbose "Retrieving Internet Gateways."
            $_igw_lookup = Get-EC2InternetGateway -Verbose:$false -Filter @{
                Name   = 'attachment.vpc-id'
                Values = $_vpc_list.VpcId
            } | Group-Object -AsHashTable @{Expression = {$_.Attachments.VpcId}}
        }

        # Retrieve route tables.
        if ($_view -in @('Network', 'Dependencies'))
        {
            Write-Verbose "Retrieving main Route Tables."
            $_route_table_lookup = Get-EC2RouteTable -Verbose:$false -Filter @{
                Name   = 'vpc-id'
                Values = $_vpc_list.VpcId
            } | Group-Object -AsHashTable VpcId
        }

        # Retrieve network ACLs.
        if ($_view -in @('Network', 'Dependencies'))
        {
            Write-Verbose "Retrieving default Network ACLs."
            $_network_acl_lookup = Get-EC2NetworkAcl -Verbose:$false -Filter @{
                Name   = 'vpc-id'
                Values = $_vpc_list.VpcId
            } | Group-Object -AsHashTable VpcId
        }

        # Retrieve NAT gateways.
        if ($_view -in @('Dependencies'))
        {
            Write-Verbose "Retrieving NAT Gateways."
            $_nat_lookup = Get-EC2NatGateway -Verbose:$false -Filter @{
                Name   = 'vpc-id'
                Values = $_vpc_list.VpcId
            } | Group-Object -AsHashTable VpcId
        }

        # Retrieve subnets.
        if ($_view -in @('Dependencies'))
        {
            Write-Verbose "Retrieving Subnets."
            $_subnets_lookup = Get-EC2Subnet -Verbose:$false -Filter @{
                Name   = 'vpc-id'
                Values = $_vpc_list.VpcId
            } | Group-Object -AsHashTable VpcId
        }

        # Retrieve security groups.
        if ($_view -in @('Dependencies'))
        {
            Write-Verbose "Retrieving Security Groups."
            $_sg_lookup = Get-EC2SecurityGroup -Verbose:$false -Filter @{
                Name   = 'vpc-id'
                Values = $_vpc_list.VpcId
            } | Group-Object -AsHashTable VpcId
        }

        # Retrieve ENIs.
        if ($_view -in @('Dependencies'))
        {
            Write-Verbose "Retrieving ENIs."
            $_eni_lookup = Get-EC2NetworkInterface -Verbose:$false -Filter @{
                Name   = 'vpc-id'
                Values = $_vpc_list.VpcId
            } | Group-Object -AsHashTable VpcId
        }

        # Retrieve VPC Peering connections.
        if ($_view -in @('Dependencies'))
        {
            Write-Verbose "Retrieving VPC Peering Connections."

            $_accepter_lookup = Get-EC2VpcPeeringConnection -Verbose:$false -Filter @{
                Name   = 'accepter-vpc-info.vpc-id'
                Values = $_vpc_list.VpcId
            } | Group-Object -AsHashTable @{
                Expression = { $_.AccepterVpcInfo.VpcId }
            }

            $_requester_lookup = Get-EC2VpcPeeringConnection -Verbose:$false -Filter @{
                Name   = 'requester-vpc-info.vpc-id'
                Values = $_vpc_list.VpcId
            } | Group-Object -AsHashTable @{
                Expression = { $_.RequesterVpcInfo.VpcId }
            }
        }

        # Retrieve VPC flow logs.
        if ($_view -in @('Flowlogs'))
        {
            Write-Verbose "Retrieving VPC Flow Logs."
            $_flow_logs_lookup = `
                Get-EC2FlowLogs -Verbose:$false |
                Group-Object -AsHashTable -AsString ResourceId, LogDestinationType
        }

        # Retrieve VPC Block Public Access.
        if ($_view -in @('BlockPublicAccess'))
        {
            Write-Verbose "Retrieving VPC Block Public Access settings."

            $_bpa_excl_lookup = Get-EC2VpcBlockPublicAccessExclusion -Verbose:$false -MaxResult 1000 -Filter @{
                Name   = 'state'
                Values = @('create-complete', 'update-complete')
            } |
            Where-Object ResourceArn -match 'vpc-[0-9a-f]{17}$' |
            Group-Object -AsHashTable -Property @{
                Expression = {$_.ResourceArn -replace '^arn:aws:ec2:[0-9a-z-]+:\d{12}:vpc\/'}
            }
        }

        # Retrieve VPC attributes.
        if ($_view -in @('Default'))
        {
            # Initialize lookup hashtables for VPC attributes.
            $_dns_hostnames_lookup  = [Hashtable]::new()
            $_dns_resolution_lookup = [Hashtable]::new()
            $_nau_metrics_lookup    = [Hashtable]::new()

            Write-Verbose "Retrieving VPC attributes."
            foreach ($_vpc in $_vpc_list) {

                $_vpc_id = $_vpc.VpcId

                $_dns_hostnames_lookup[$_vpc_id] = Get-EC2VpcAttribute $_vpc_id enableDnsHostnames `
                    -Verbose:$false | Select-Object -ExpandProperty EnableDnsHostnames

                $_dns_resolution_lookup[$_vpc_id] = Get-EC2VpcAttribute $_vpc_id enableDnsSupport `
                    -Verbose:$false | Select-Object -ExpandProperty EnableDnsSupport

                $_nau_metrics_lookup[$_vpc_id] = Get-EC2VpcAttribute $_vpc_id enableNetworkAddressUsageMetrics `
                    -Verbose:$false | Select-Object -ExpandProperty EnableNetworkAddressUsageMetrics
            }
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             $_view `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    # Generate output after sorting and exclusion.
    $_output = $_vpc_list | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column -GroupBy $_group_by -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
    }
}