using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.Management.Automation
using namespace Amazon.EC2.Model
using namespace Worker369.AWS

function Show-SecurityGroupRule
{
    [CmdletBinding(DefaultParameterSetName = 'TagName')]
    [Alias('sgr_show')]
    param (
        [Parameter(ParameterSetName = 'GroupId')]
        [ValidatePattern('^sg-[0-9a-f]{17}$', ErrorMessage = 'Invalid GroupId.')]
        [string]
        $GroupId = $script:DefaultSecurityGroup,

        [Parameter(ParameterSetName = 'TagName', Position = 0)]
        [string]
        $TagName,

        [Parameter()]
        [ValidateSet('IPv4', 'IPv6', '_')]
        [string]
        $IpVersion,

        [Parameter()]
        [ValidateSet('Inbound', 'Outbound')]
        [string]
        $Direction,

        [ValidateSet('Direction', 'RemoteAddress', 'IpVersion', $null)]
        [string]
        $GroupBy = 'Direction',

        [Int[]]
        $Sort,

        [Int[]]
        $Exclude,

        [switch]
        $PlainText,

        [switch]
        $NoRowSeparator
    )

    # For easy pick up.
    $_param_set = $PSCmdlet.ParameterSetName

    # Use snake_case.
    $_sg_id             = $GroupId
    $_tag_name          = $TagName
    $_group_by          = $GroupBy
    $_sort              = $Sort
    $_exclude           = $Exclude
    $_plain_text        = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    $_ip_version = $IpVersion
    $_direction  = $Direction

    # Configure the filter to query the Security Group.
    if (
        -not $PSBoundParameters.ContainsKey('GroupId') -and
        -not $PSBoundParameters.ContainsKey('TagName')
    ) {
        $_default_sg = Get-DefaultSecurityGroup -Raw

        if (-not $_default_sg)
        {
            Write-Error (
                'Default Security Group has not been set. ' +
                'You can only use this cmdlet with no parameters when ' +
                'Default Security Group can be set using the ''Set-DefaultSecurityGroup'' cmdlet.'
            )
            return
        }
        $_filter_name  = 'group-id'
        $_filter_value = $_default_sg.GroupId
    }
    else
    {
        $_filter_name  = $_param_set -eq 'GroupId' ? 'group-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'GroupId' ? $_sg_id    : $_tag_name
    }

    try {
        # Try to query the Security Group.
        Write-Verbose "Retrieving Security Group."
        $_sg_list = Get-EC2SecurityGroup -Verbose:$false -Filter @{
            Name   = $_filter_name
            Values = $_filter_value
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # If no Security Groups matched the filter value, exit early.
    if (-not $_sg_list)
    {
        Write-Error "No Security Groups were found for '$_filter_value'."
        return
    }

    # If multiple Security Groups matched the filter value, exit early.
    if ($_sg_list.Count -gt 1)
    {
        Write-Error "Multiple Security Groups were found for '$_filter_value'. It must match one Security Group only."
        return
    }

    # Save a reference to the filtered Security Group.
    $_sg = $_sg_list[0]

    try {
        # Try to query the Security Group Rules.
        $_sgr_list = Get-EC2SecurityGroupRule -Verbose:$false -Filter @{ Name = 'group-id'; Values = $_sg.GroupId }

        # If there are no rules to show, exit early.
        if (-not $_sgr_list) { return }

        # Query referenced security groups and attached ENIs
        if ($_ref_group_id_list = $_sgr_list.ReferencedGroupInfo.GroupId)
        {
            $_ref_sg_lookup = `
                Get-EC2SecurityGroup -Verbose:$false -Filter @{Name = 'group-id'; Values = $_ref_group_id_list} |
                Group-Object -AsHashTable GroupId

            $_eni_list = Get-EC2NetworkInterface -Verbose:$false -Filter @{
                Name = 'group-id'; Values = $_ref_group_id_list
            }

            $_eni_lookup = [hashtable]::new()
            foreach ($_eni in $_eni_list)
            {
                foreach ($_eni_sg in $_eni.Groups)
                {
                    if (-not $_eni_lookup[$_eni_sg.GroupId]) {
                        $_eni_lookup[$_eni_sg.GroupId] = [List[NetworkInterface]]::new()
                    }
                    $_eni_lookup[$_eni_sg.GroupId].Add($_eni)
                }
            }
        }

        # Query prefix lists.
        $_pl_lookup = Get-EC2ManagedPrefixList -Verbose:$false -Filter @{
            Name = 'prefix-list-id'
            Values = $_sgr_list.PrefixListId ?? @()
        } | Group-Object -AsHashTable PrefixListId

        # CIDR list lookup for prefix lists.
        $_pl_entries_lookup = [Hashtable]::new()

        foreach ($_pl_id in $_pl_lookup.Keys)
        {
            $_pl_cidr_list = `
                Get-EC2ManagedPrefixListEntry -Verbose:$false -PrefixListId $_pl_id |
                Select-Object -ExpandProperty Cidr

            $_pl_entries_lookup.Add($_pl_id, $_pl_cidr_list)
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    $_select_definition = @{
        Description = {
            $_.Description
        }
        Direction = {
            $_.IsEgress ? 'Outbound' : 'Inbound'
        }
        FromPort = {
            [FromPort]::new($_.FromPort, $_.IpProtocol -in @('icmp', 'icmpv6'))
        }
        IpVersion = {
            if ($_.CidrIpv4) { 'IPv4' }
            if ($_.CidrIpv6) { 'IPv6' }
            if ($_.PrefixListId) { $_pl_lookup[$_.PrefixListId].AddressFamily }
            if ($_.ReferencedGroupInfo) { '_' }
        }
        IpProtocol = {
            [IPProtocol]::FromString($_.IpProtocol)
        }
        RemoteAddress = {
            if ($_.CidrIpv4) {
                $_.CidrIpv4
            }
            if ($_.CidrIpv6) {
               $_.CidrIpv6
            }
            if ($_.PrefixListId) {
                $_pl = $_pl_lookup[$_.PrefixListId]
                $_pl | Get-ResourceString `
                    -IdPropertyName 'PrefixListId' -NamePropertyName 'PrefixListName' -PlainText:$_plain_text
            }
            if ($_ref_group_info = $_.ReferencedGroupInfo) {
                $_ref_sg = $_ref_sg_lookup[$_ref_group_info.GroupId]
                $_ref_sg | Get-ResourceString `
                    -IdPropertyName 'GroupId' -NamePropertyName 'GroupName' -PlainText:$_plain_text
            }
        }
        ResolvedAddress = {
            if ($_.CidrIpv4) {
                New-IPv4Subnet $_.CidrIpv4
            }
            if ($_.CidrIpv6) {
                New-IPv6Subnet $_.CidrIpv6
            }
            if ($_.PrefixListId) {
                $_pl         = $_pl_lookup[$_.PrefixListId]
                $_pl_entries = $_pl_entries_lookup[$_.PrefixListId]

                if ($_pl.AddressFamily -eq 'IPv4') {
                    $_pl_entries | New-IPv4Subnet | Sort-Object
                }
                else {
                    $_pl_entries | New-IPv6Subnet | Sort-Object
                }

            }
            if ($_ref_group_info = $_.ReferencedGroupInfo) {
                $_ref_eni_list = $_eni_lookup[$_ref_group_info.GroupId]
                $_ref_eni_list.PrivateIpAddresses.PrivateIpAddress | New-IPv4Address | Sort-Object
                $_ref_eni_list.Ipv6Addresses.Ipv6Address | New-IPv6Address | Sort-Object
            }
        }
        SecurityGroupRuleId = {
            $_.SecurityGroupRuleId
        }
        ToPort = {
            [ToPort]::new($_.ToPort, $_.IpProtocol -in @('icmp', 'icmpv6'))
        }
    }

    $_view_definition = @{
        Default = @(
            'Direction', 'SecurityGroupRuleId', 'IpVersion', 'IpProtocol',
            'FromPort', 'ToPort', 'RemoteAddress', 'ResolvedAddress', 'Description'
        )
    }

    # Apply default sort order.
    if (
        -not $PSBoundParameters.Keys.Contains('GroupBy') -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(5, 2, 3, 4)      # Sort by RemoteAddress, IpProtocol, FromPort, ToPort
    }

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             'Default' `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    # Filter $_sgr_list.
    if ($_direction -eq 'Inbound') {
        $_sgr_list = $_sgr_list | Where-Object -not IsEgress
    }
    if ($_direction -eq 'Outbound') {
        $_sgr_list = $_sgr_list | Where-Object IsEgress
    }
    if ($_ip_version -eq 'IPv4') {
        $_sgr_list = $_sgr_list | Where-Object {
            ($_.CidrIpv4 -as [bool]) -or
            ($_.PrefixListId -as [bool] -and $_pl_lookup[$_.PrefixListId].AddressFamily -eq 'IPv4')
        }
    }
    if ($_ip_version -eq 'IPv6') {
        $_sgr_list = $_sgr_list | Where-Object {
            ($_.CidrIpv4 -as [bool]) -or
            ($_.PrefixListId -as [bool] -and $_pl_lookup[$_.PrefixListId].AddressFamily -eq 'IPv6')
        }
    }
    if ($_ip_version -eq '_') {
        $_sgr_list = $_sgr_list | Where-Object ReferencedGroupInfo
    }

    #if ($_.CidrIpv4) { 'IPv4' }
    #if ($_.CidrIpv6) { 'IPv6' }
    #if ($_.PrefixListId) { $_pl_lookup[$_.PrefixListId].AddressFamily }
    #if ($_.ReferencedGroupInfo) { '_' }

    # Generate output after sorting and exclusion.
    $_output = $_sgr_list | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column -GroupBy $_group_by -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
    }
}

<#>

SecurityGroupRuleId   IpProtocol    FromPort   ToPort        RemoteAddress ResolvedAddress
--------------------- ------------- ---------- ------------- -------------
sgr-12345678901234567                               17 (UDP)   3389          3389




Gets and sets the property IpProtocol.
The IP protocol name (tcp, udp, icmp, icmpv6) or number (see Protocol Numbers).
Use -1 to specify all protocols.

Gets and sets the property FromPort.
If the protocol is TCP or UDP, this is the start of the port range.
If the protocol is ICMP or ICMPv6, this is the ICMP type or -1 (all ICMP types).

Gets and sets the property ToPort.
If the protocol is TCP or UDP, this is the end of the port range.
If the protocol is ICMP or ICMPv6, this is the ICMP code or -1 (all ICMP codes).
If the start port is -1 (all ICMP types), then the end port must be -1 (all ICMP codes).

#>