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

    # Try to query the Security Group.
    try {
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

    # Try to query the Security Group Rules.
    try {
        $_sgr_list = Get-EC2SecurityGroupRule -Verbose:$false -Filter @{ Name = 'group-id'; Values = $_sg.GroupId }

        # If there are no rules to show, exit early.
        if (-not $_sgr_list) { return }

        # Query Prefix List.
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
            if ($_.ReferencedGroupInfo) { '' }
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
            if ($_.ReferencedGroupInfo) {

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
            if ($_.ReferencedGroupInfo) {

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

    # Print out the summary table.
    $_sgr_list                   |
    Select-Object $_select_list  |
    Sort-Object   $_sort_list    |
    Select-Object $_project_list |
    Format-Column `
        -GroupBy $_group_by `
        -PlainText:$_plain_text `
        -NoRowSeparator:$_no_row_separator
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