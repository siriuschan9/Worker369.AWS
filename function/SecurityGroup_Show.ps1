using namespace System.Collections.Generic
using namespace Amazon.EC2.Model
using namespace Worker369.Utility

function Show-SecurityGroup
{
    [CmdletBinding(DefaultParameterSetName = 'None')]
    [Alias('sg_show')]
    param (
        [Parameter(Position = 0)]
        [ValidateSet('Default', 'ENI', 'Quota')]
        [string]
        $View = 'Default',

        [Parameter(ParameterSetName = 'VpcId')]
        [ValidatePattern('^vpc-[0-9a-f]{17}$')]
        [string[]]
        $VpcId,

        [Parameter(ParameterSetName = 'VpcName')]
        [string[]]
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
    $_vpc_id           = $VpcId
    $_vpc_name         = $VpcName
    $_filter           = $Filter
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    $_view_definition = @{
        Default = @(
            'Vpc', 'GroupId', 'GroupName', 'Tag:Name', 'InboundRules', 'OutboundRules', 'Attachments', 'Description'
        )
        ENI = @(
            'Vpc', 'GroupId', 'GroupName', 'Tag:Name', 'InboundRules', 'OutboundRules', 'Description', 'ENI'
        )
        Quota = @(
            'Vpc', 'GroupId', 'GroupName', 'Tag:Name',
            'InboundIpv4', 'InboundIpv6', 'OutboundIpv4', 'OutboundIpv6'
        )
    }

    $_select_definition = @{
        Attachments = {
            $_my_group_id = $_.GroupId

            $_num_style       = $_plain_text ? $_counter_plain : $_counter_style
            $_num_attachments = $_eni_list | Where-Object {
                $_.Groups.GroupId -contains $_my_group_id
            } | Measure-Object | Select-Object -ExpandProperty Count

            New-NumberInfo -FormatSettings $_num_style $_num_attachments
        }
        Description = {
            $_.Description
        }
        ENI = {
            $_my_group_id = $_.GroupId
            $_eni_list | Where-Object {$_.Groups.GroupId -contains $_my_group_id} | Get-ResourceString `
                -IdPropertyName 'NetworkInterfaceId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
        GroupId = {
            $_.GroupId
        }
        GroupName = {
            $_.GroupName
        }
        InboundIpv4 = {
            $_num_value = $_inbound_ipv4_lookup[$_.GroupId]
            $_num_style = $_plain_text ? $_quota_plain : $_quota_style

            New-NumberInfo -FormatSettings $_num_style $_num_value
        }
        InboundIpv6 = {
            $_num_value = $_inbound_ipv6_lookup[$_.GroupId]
            $_num_style = $_plain_text ? $_quota_plain : $_quota_style

            New-NumberInfo -FormatSettings $_num_style $_num_value
        }
        InboundRules = {
            $_num_inbound_rules = $_.IpPermissions.Count
            $_num_style         = $_plain_text ? $_counter_style : $_counter_plain

            New-NumberInfo -FormatSettings $_num_style $_num_inbound_rules
        }
        OutboundIpv4 = {
            $_num_value = $_outbound_ipv4_lookup[$_.GroupId]
            $_num_style = $_plain_text ? $_quota_plain : $_quota_style

            New-NumberInfo -FormatSettings $_num_style $_num_value
        }
        OutboundIpv6 = {
            $_num_value = $_outbound_ipv6_lookup[$_.GroupId]
            $_num_style = $_plain_text ? $_quota_plain : $_quota_style

            New-NumberInfo -FormatSettings $_num_style $_num_value
        }
        OutboundRules = {
            $_num_outbound_rules = $_outbound_rules_lookup[$_.GroupId]
            $_num_style          = $_plain_text ? $_counter_style : $_counter_plain

            New-NumberInfo -FormatSettings $_num_style $_num_outbound_rules
        }
        Vpc = {
            $_vpc_lookup[$_.VpcId] | Get-ResourceString `
                -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
        'Tag:Name' = {
            $_.Tags | Where-Object Key -eq 'Name' | Select-Object -ExpandProperty Value
        }
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
            $_vpc_id_filter = Get-EC2Vpc -Verbose:$false `
                -Select Vpcs.VpcId -Filter @{Name = 'tag:Name'; Values = $_vpc_name}

            # Add a vpc-id filter to the filter list.
            if ($_vpc_id_filter)
            {
                $_vpc_filter = [Filter]@{
                    Name   = 'vpc-id'
                    Values = $_vpc_id_filter
                }
                $_filter_list.Add($_vpc_filter)
            }
        }

        # Query Security Groups.
        $_sg_list = Get-EC2SecurityGroup -Verbose:$false -Filter $($_filter_list.Count -eq 0 ? $null : $_filter_list)

        # Exit early if there are no Security Groups to show.
        if (-not $_sg_list) { return }

        # Query VPCs.
        $_vpc_list = Get-EC2Vpc -Verbose:$false -Filter @{ Name = 'vpc-id'; Values = $_sg_list.VpcId }

        # Query AWS Region.
        $_region = (Get-DefaultAWSRegion -Verbose:$false).Region

        # Query Prefix Lists.
        $_pl_list = Get-EC2ManagedPrefixList -Verbose:$false -Filter @{
            Name = 'prefix-list-id'
            Values = (
                @($_sg_list.IpPermissions?.PrefixListIds?.Id) +
                @($_sg_list.IpPermissionsEgress?.PrefixListIds?.Id)
            ) | Select-Object -Unique
        }

        # Query ENIs.
        $_eni_list = Get-EC2NetworkInterface -Verbose:$false -Filter @{ Name = 'vpc-id'; Values = $_sg_list.VpcId }

        # Query Service Quota
        $_quota = Get-SQServiceQuota -Verbose:$false -ServiceCode vpc -QuotaCode L-0EA8095F -Select Quota.Value
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Display a dimmed dash for zero - used for Default view.
    $_counter_style = [NumberInfoSettings]::Make()
    $_counter_style.Format.Unscaled = "#,###;#,###;`e[2m-`e[0m"

    # Display an unstyled dash for zero - used for Default view.
    $_counter_plain = [NumberInfoSettings]::Make()
    $_counter_plain.Format.Unscaled = '#,###;#,###;-'

    # Display styled <Consumed> / <Quota> - used for Quota view.
    $_quota_style = [NumberInfoSettings]::Make()
    $_quota_style.Format.Unscaled = "#,##0 `e[2m/ $($_quota -replace '0', '\0')`e[\0m" # Escape '0'.

    # Display plain <Consumed> / <Quota> - used for Quota view.
    $_quota_plain = [NumberInfoSettings]::Make()
    $_quota_plain.Format.Unscaled = "#,##0 / $($_quota -replace '0', '\0')"            # Escape '0'.

    # Prepare Prefix list weight lookup.
    $_weight_lookup = @{
        'com.amazonaws.global.cloudfront.origin-facing'      = 55
        'com.amazonaws.global.ipv6.cloudfront.origin-facing' = 55
        "com.amazonaws.$_region.dynamodb"                    = 1
        "com.amazonaws.$_region.ec2-instance-connect"        = 2
        "com.amazonaws.$_region.ipv6.ec2-instance-connect" 	 = 2
        "com.amazonaws.global.groundstation"	             = 5
        "com.amazonaws.$_region.ipv6.route53-healthchecks"   = 25
        "com.amazonaws.$_region.route53-healthchecks"        = 25
        "com.amazonaws.$_region.s3"                          = 1
        "com.amazonaws.$_region.s3express" 	                 = 6
        "com.amazonaws.$_region.vpc-lattice"                 = 10
        "com.amazonaws.$_region.ipv6.vpc-lattic"             = 10
    }

    # Dictionaries for VPC, Prefix List and ENI lookup - by Security Group ID.
    $_vpc_lookup               = [Dictionary[string, Vpc]]::new()
    $_pl_lookup                = [Dictionary[string, ManagedPrefixList]]::new()

    # Dictionaries to lookup quota statistics by Security Group ID.
    $_inbound_ipv4_lookup  = [Dictionary[string, int]]::new()
    $_inbound_ipv6_lookup  = [Dictionary[string, int]]::new()
    $_outbound_ipv4_lookup = [Dictionary[string, int]]::new()
    $_outbound_ipv6_lookup = [Dictionary[string, int]]::new()

    # Dictionaries to lookup rules count by Security Group ID.
    $_inbound_rules_lookup  = [Dictionary[string, int]]::new()
    $_outbound_rules_lookup = [Dictionary[string, int]]::new()

    # PUt VPC in Dictionary
    foreach ($_vpc in $_vpc_list)
    {
        $_vpc_lookup[$_vpc.VpcId] = $_vpc
    }

    # Put Prefix List in Dictionary
    foreach ($_pl in $_pl_list)
    {
        # Fill up the MaxEntries of AWS-Managed Prefix List using their documented weights.
        if ($null -eq $_pl.MaxEntries) {
            $_pl.MaxEntries = $_weight_lookup[$_pl.PrefixListName]
        }

        $_pl_lookup[$_pl.PrefixListId] = $_pl
    }

    # Populate rules count lookup and quota lookups.
    foreach ($_sg in $_sg_list)
    {
        $_inbound_rules  = $_sg.IpPermissions
        $_outbound_rules = $_sg.IpPermissionsEgress

        $_ingress_ipv4 = $_inbound_rules.Ipv4Ranges.CidrIp.Count
        $_ingress_ipv6 = $_inbound_rules.Ipv6Ranges.CidrIpv6.Count
        $_ingress_sg   = $_inbound_rules.UserIdGroupPairs.GroupId.Count
        $_ingress_pl   = $_inbound_rules.PrefixListIds.Id.Count

        $_ingress_pl4   = $_inbound_rules.PrefixListIds.Id | Where-Object { $null -ne $_ } | ForEach-Object {
            $_pl_lookup[$_]
        } |
        Where-Object AddressFamily -eq 'IPv4' | Select-Object -ExpandProperty MaxEntries |
        Measure-Object -Sum | Select-Object -ExpandProperty Sum

        $_ingress_pl6   = $_inbound_rules.PrefixListIds.Id | Where-Object { $null -ne $_ } | ForEach-Object {
            $_pl_lookup[$_]
        } |
        Where-Object AddressFamily -eq 'IPv6' | Select-Object -ExpandProperty MaxEntries |
        Measure-Object -Sum | Select-Object -ExpandProperty Sum

        $_egress_ipv4 = $_outbound_rules.Ipv4Ranges.CidrIp.Count
        $_egress_ipv6 = $_outbound_rules.Ipv6Ranges.CidrIpv6.Count
        $_egress_sg   = $_outbound_rules.UserIdGroupPairs.GroupId.Count
        $_egress_pl   = $_outbound_rules.PrefixListIds.Id.Count

        $_egress_pl4   = $_outbound_rules.PrefixListIds.Id | Where-Object { $null -ne $_ } | ForEach-Object {
            $_pl_lookup[$_]
        } |
        Where-Object AddressFamily -eq 'IPv4' | Select-Object -ExpandProperty MaxEntries |
        Measure-Object -Sum | Select-Object -ExpandProperty Sum

        $_egress_pl6   = $_outbound_rules.PrefixListIds.Id | Where-Object { $null -ne $_ } | ForEach-Object {
            $_pl_lookup[$_]
        } |
        Where-Object AddressFamily -eq 'IPv6' | Select-Object -ExpandProperty MaxEntries |
        Measure-Object -Sum | Select-Object -ExpandProperty Sum

        $_inbound_ipv4_lookup[$_sg.GroupId]  = $_ingress_ipv4 + $_ingress_sg + $_ingress_pl4
        $_inbound_ipv6_lookup[$_sg.GroupId]  = $_ingress_ipv6 + $_ingress_sg + $_ingress_pl6
        $_outbound_ipv4_lookup[$_sg.GroupId] = $_egress_ipv4  + $_egress_sg  + $_egress_pl4
        $_outbound_ipv6_lookup[$_sg.GroupId] = $_egress_ipv6  + $_egress_sg  + $_egress_pl6

        $_inbound_rules_lookup[$_sg.GroupId]  = `
            $_ingress_ipv4 + $_ingress_ipv6 + $_ingress_sg + $_ingress_pl

        $_outbound_rules_lookup[$_sg.GroupId] = `
            $_egress_ipv4  + $_egress_ipv6  + $_egress_sg  + $_egress_pl
    }

    # Apply default sort order.
    if ($_group_by -eq 'Vpc' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(3, 1) # => Sort by Tag:Name, GroupId
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
    $_output = $_sg_list | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column -GroupBy $_group_by -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
    }
}

<#
Vpc :

  GroupId              GroupName         Tag:Name          InboundIPv4 InboundIPv6 OutboundIPv4 OutboundIPv6
  -------------------- ----------------- ----------------- ----------- ----------- ------------ ------------
  sg-12345678901234567 example-3-linux   example-3-linux       34 / 60
  sg-76543210987654321 example-3-windows example-3-windows
#>