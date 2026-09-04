using namespace System.Collections.Generic
using namespace Amazon.EC2.Model
using namespace Worker369.Utility

function Show-Eni
{
    [CmdletBinding(DefaultParameterSetName = 'None')]
    [Alias('eni_show')]
    param (
        [Parameter(Position = 0)]
        [ValidateSet('Attachment', 'IpAddresses', 'Network', 'Status', 'Security')]
        [string]
        $View = 'Status',

        [Parameter(ParameterSetName = 'VpcId')]
        [ValidatePattern('^vpc-[0-9a-f]{17}$')]
        [string[]]
        $VpcId,

        [Parameter(ParameterSetName = 'VpcName')]
        [string[]]
        $VpcName,

        [Amazon.EC2.Model.Filter[]]
        $Filter,

        [ValidateSet('Vpc', 'Subnet', 'AvailabilityZone', 'InterfaceType', $null)]
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
        Attachment = @(
            'NetworkInterfaceId', 'AttachmentId', 'InterfaceType',
            'DeviceIndex' ,'DeleteOnTermination', 'Description'
        )
        Network = @(
            'NetworkInterfaceId', 'Subnet', 'AvailabilityZone',
            'PrivateIp', 'PublicIp', 'Ipv6Address', 'MacAddress'
        )
        IpAddresses = @(
            'NetworkInterfaceId', 'PrivateIp', 'PublicIp', 'Ipv6Address', 'Ipv4Prefix', 'Ipv6Prefix'
        )
        Security = @(
            'NetworkInterfaceId', 'Status', 'SecurityGroups', 'SourceDestCheck', 'TcpEstablishedTimeout', 'UdpStreamTimeout', 'UdpTimeout'
        )
        Status = @(
            'NetworkInterfaceId', 'Status', 'InterfaceType', 'PrivateIp', 'PublicIp', 'Ipv6Address',
            'Description'
        )
    }

    $_select_definition = @{
        AvailabilityZone = {
            $_.AvailabilityZone
        }
        AttachmentId = {
            $_.Attachment.AttachmentId
        }
        DeleteOnTermination = {
            New-Checkbox -PlainText:$_plain_text $_.Attachment.DeleteOnTermination
        }
        Description = {
            $_.Description
        }
        DeviceIndex = {
            $_.Attachment.DeviceIndex
        }
        InterfaceType = {
            $_.InterfaceType
        }
        Ipv6Address = {
            $_sort_expr = {$_.Ipv6Address | New-IPv6Address}
            $_map_expr  = {$_.IsPrimaryIpv6 ? "[ P ] $($_.Ipv6Address)" : "[   ] $($_.Ipv6Address)"}

            $_.Ipv6Addresses | Sort-Object @{Expression = $_sort_expr} | ForEach-Object $_map_expr
        }
        Ipv4Prefix = {
            $_.Ipv4Prefixes | Select-Object -ExpandProperty IPv4Prefix | New-IPv4Subnet | Sort-Object
        }
        Ipv6Prefix = {
            $_.Ipv6Prefixes | Select-Object -ExpandProperty IPv6Prefix | New-IPv6Subnet | Sort-Object
        }
        MacAddress = {
            $_.MacAddress
        }
        Name = {
            $_.TagSet | Where-Object Key -eq 'Name' | Select-Object -ExpandProperty Value
        }
        NetworkInterfaceId = {
            $_.NetworkInterfaceId
        }
        PrivateIp = {
            $_sort_expr = {$_.PrivateIpAddress | New-IPv4Address}
            $_map_expr  = {$_.Primary ? "[ P ] $($_.PrivateIpAddress)" : "[   ] $($_.PrivateIpAddress)"}

            $_.PrivateIpAddresses | Sort-Object @{Expression = $_sort_expr} | ForEach-Object $_map_expr
        }
        PublicIp = {
            $_dash      = $_plain_text ? '-' : "$($PSStyle.Dim)-$($PSStyle.Reset)"
            $_sort_expr = {$_.PrivateIpAddress | New-IPv4Address}
            $_map_expr  = {$_.Primary `
                ? "[ P ] $($_eip_lookup[$_.PrivateIpAddress].PublicIp ?? $_dash)" `
                : "[   ] $($_eip_lookup[$_.PrivateIpAddress].PublicIp ?? $_dash)"
            }
            $_.PrivateIpAddresses | Sort-Object @{Expression = $_sort_expr} | ForEach-Object $_map_expr
        }
        SecurityGroups = {
            $_.Groups | ForEach-Object {
                $_sg_lookup[$_.GroupId] |
                Get-ResourceString -IdPropertyName 'GroupId' -NamePropertyName 'GroupName' -PlainText:$_plain_text
            }
        }
        SourceDestCheck = {
            New-Checkbox -PlainText:$_plain_text $_.SourceDestCheck
        }
        Status = {
            $_status = $_.Status.Value
            New-Checkbox -PlainText:$_plain_text -Description $_status ($_status -eq 'in-use')
        }
        Subnet = {
            $_subnet_lookup[$_.SubnetId] | Get-ResourceString `
                -IdPropertyName 'SubnetId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
        TcpEstablishedTimeout = {
            $_value   = $_.ConnectionTrackingConfiguration.TcpEstablishedTimeout
            $_default = $_plain_text ? 'Default' : "$($PSStyle.Dim)Default$($PSStyle.Reset)"
            $_value   ? (New-NumberInfo $_value) : $_default
        }
        UdpStreamTimeout = {
            $_value   = $_.ConnectionTrackingConfiguration.UdpStreamTimeout
            $_default = $_plain_text ? 'Default' : "$($PSStyle.Dim)Default$($PSStyle.Reset)"
            $_value   ? (New-NumberInfo $_value) : $_default
        }
        UdpTimeout = {
            $_value   = $_.ConnectionTrackingConfiguration.UdpTimeout
            $_default = $_plain_text ? 'Default' : "$($PSStyle.Dim)Default$($PSStyle.Reset)"
            $_value   ? (New-NumberInfo $_value) : $_default
        }
        Vpc = {
            $_vpc_lookup[$_.VpcId] | Get-ResourceString `
                -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -PlainText:$_plain_text
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

        # Query ENIs.
        $_eni_list = `
            Get-EC2NetworkInterface -Verbose:$false -Filter $($_filter_list.Count -eq 0 ? $null : $_filter_list)

        # Exit early if there are no ENIs to show.
        if (-not $_eni_list) { return }

        # Query VPCs.
        $_vpc_id_list = $_eni_list | Select-Object -Unique -ExpandProperty VpcId
        $_vpc_lookup  = `
            Get-EC2Vpc -Verbose:$false -Filter @{ Name = 'vpc-id'; Values = $_vpc_id_list} |
            Group-Object -AsHashTable VpcId

        # Query Subnets.
        $_subnet_id_list = $_eni_list | Select-Object -Unique -ExpandProperty SubnetId
        $_subnet_lookup  = `
            Get-EC2Subnet -Verbose:$false -Filter @{ Name = 'subnet-id'; Values = $_subnet_id_list } |
            Group-Object -AsHashTable SubnetId

        # Query Security Groups.
        $_sg_id_list = $_eni_list | Select-Object -ExpandProperty Groups | Select-Object -Unique -ExpandProperty GroupId
        $_sg_lookup  = `
            Get-EC2SecurityGroup -Verbose:$false -Filter @{ Name = 'group-id'; Values = $_sg_id_list } |
            Group-Object -AsHashTable GroupId

        # Query EIPs.
        $_eip_lookup = Get-EC2Address -Verbose:$false | Group-Object -AsHashTable PrivateIpAddress
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Apply default sort order.
    if ($_group_by -eq 'Vpc' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(2) # => Sort by Name
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
    $_output = $_eni_list | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column `
            -GroupBy $_group_by `
            -PlainText:$_plain_text `
            -NoRowSeparator:$_no_row_separator `
            -AlignLeft Status `
            -AlignRight TcpEstablishedTimeout, UdpStreamTimeout, UdpTimeout
    }
}