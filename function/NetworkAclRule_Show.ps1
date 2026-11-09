function Show-NetworkAclRule
{
    [CmdletBinding(DefaultParameterSetName = 'NetworkAclName')]
    [Alias('naclr_show')]
    param (
        [Parameter(ParameterSetName = 'NetworkAclId')]
        [ValidatePattern('^acl-[0-9a-f]{17}$', ErrorMessage = 'Invalid NetworkAclId.')]
        [string]
        $NetworkAclId = $script:DefaultNetworkAcl,

        [Parameter(ParameterSetName = 'NetworkAclName', Position = 0)]
        [string]
        $NetworkAclName,

        [Parameter()]
        [ValidateSet('IPv4', 'IPv6', '_')]
        [string]
        $IpVersion,

        [Parameter()]
        [ValidateSet('Inbound', 'Outbound')]
        [string]
        $Direction,

        [ValidateSet('Direction')]
        [string]
        $GroupBy = 'Direction',

        [Int[]]
        $Sort,

        [Int[]]
        $Exclude,

        [ScriptBlock]
        $Where = {$true},

        [switch]
        $PassThru,

        [switch]
        $PlainText,

        [switch]
        $NoRowSeparator
    )

    # Use snake_case.
    $_nacl_id          = $NetworkAclId
    $_nacl_name        = $NetworkAclName
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_where            = $Where
    $_pass_thru        = $PassThru.IsPresent
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    $_ip_version = $IpVersion
    $_direction  = $Direction

    # For easy pick up.
    $_param_set = $PSCmdlet.ParameterSetName
    $_allow_style = $_plain_text `
        ? '■ Allow' `
        : "$($PSStyle.Foreground.BrightGreen) ■ Allow$($PSStyle.Reset)"
    $_deny_style = $_plain_text `
        ? '■ Deny' `
        : "$($PSStyle.Foreground.BrightRed) ■ Deny$($PSStyle.Reset)"

    # Configure the filter to query the Security Group.
    if (
        -not $PSBoundParameters.ContainsKey('NetworkAclId') -and
        -not $PSBoundParameters.ContainsKey('NetworkAclName')
    ) {
        $_default_nacl = Get-DefaultNetworkAcl -Raw

        if (-not $_default_nacl)
        {
            Write-Error (
                'Default Network ACL has not been set. ' +
                'You can only use this cmdlet with no parameters when ' +
                'Default Network ACL have be set using the ''Set-DefaultNetworkAcl'' cmdlet.'
            )
            return
        }
        $_filter_name  = 'network-acl-id'
        $_filter_value = $_default_nacl.NetworkAclId
    } else {
        switch ($_param_set)
        {
            'NetworkAclId' {
                $_filter_name  = 'network-acl-id'
                $_filter_value = $_nacl_id
            }
            'NetworkAclName' {
                $_filter_name  = 'tag:Name'
                $_filter_value = $_nacl_name
            }
        }
    }

    try {
        # Try to query the NACL.
        Write-Verbose "Retrieving Network ACL."
        $_nacl_list = Get-EC2NetworkAcl -Verbose:$false -Filter @{
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

    # If no NACLs matched the filter value, exit early.
    if (-not $_nacl_list)
    {
        Write-Error "No Network ACL was found for '$_filter_value'."
        return
    }

    # If multiple NACLs matched the filter value, exit early.
    if ($_sg_list.Count -gt 1)
    {
        Write-Error "Multiple Network ACL were found for '$_filter_value'. It must match one Network ACL only."
        return
    }

    # Save a reference to the filtered NACL.
    $_entries = $_nacl_list[0].Entries

    $_view_definition = @{
        Default = @(
            'Direction', 'Action', 'IpVersion', 'IpProtocol', 'FromPort', 'ToPort', 'RemoteAddress', 'RuleNumber'
        )
    }
    $_select_definition = @{
        Action = {
            $_.RuleAction -eq 'allow' ? $_allow_style : $_deny_style
        }
        Direction = {
            $_.Egress ? 'Outbound' : 'Inbound'
        }
        FromPort = {
            $_is_icmp   = $null -ne $_.IcmpTypeCode
            $_from_port = $_is_icmp ? $_.IcmpTypeCode.Type : ($_.PortRange.From ?? -1)
            [Worker369.AWS.FromPort]::new($_from_port, $_is_icmp)
        }
        IpProtocol = {
            [Worker369.AWS.IPProtocol]::FromNumber($_.Protocol)
        }
        IpVersion = {
            $_.Ipv6CidrBlock ? 'IPv6' : 'IPv4'
        }
        RuleNumber = {
            $_.RuleNumber | New-NumberInfo
        }
        RemoteAddress = {
            $_.Ipv6CidrBlock ? (New-IPv6Subnet $_.Ipv6CidrBlock) : (New-IPv4Subnet $_.CidrBlock)
        }
        ToPort = {
            $_is_icmp = $null -ne $_.IcmpTypeCode
            $_to_port = $_is_icmp ? $_.IcmpTypeCode.Code : ($_.PortRange.To ?? -1)
            [Worker369.AWS.ToPort]::new($_to_port, $_is_icmp)
        }
    }

    # Apply default sort order.
    if (
        -not $PSBoundParameters.Keys.Contains('GroupBy') -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(7) # Sort by RuleNumber
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
        $_entries = $_entries | Where-Object -not Egress
    }
    if ($_direction -eq 'Outbound') {
        $_entries = $_entries | Where-Object Egress
    }
    if ($_ip_version -eq 'IPv4') {
        $_entries = $_entries | Where-Object CidrBlock
    }
    if ($_ip_version -eq 'IPv6') {
        $_entries = $_entries | Where-Object Ipv6CidrBlock
    }

    #if ($_.CidrIpv4) { 'IPv4' }
    #if ($_.CidrIpv6) { 'IPv6' }
    #if ($_.PrefixListId) { $_pl_lookup[$_.PrefixListId].AddressFamily }
    #if ($_.ReferencedGroupInfo) { '_' }

    # Generate output after sorting and exclusion.
    $_output = $_entries `
        | Select-Object $_select_list `
        | Sort-Object   $_sort_list `
        | Select-Object $_project_list `
        | Where-Object  $_where

    # If -PassThru, put the objects in the pipeline.
    if ($_pass_thru) {$_output; return }

    # If EnableHtmlOutput is set, output html markup.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
        return
    }

    # Print out the output to the terminal.
    $_align_left  = @()
    $_align_right = @('FromPort', 'ToPort', 'RemoteAddress')
    $_output | Format-Column `
        -AlignLeft $_align_left `
        -AlignRight $_align_right `
        -GroupBy $_group_by `
        -PlainText:$_plain_text `
        -NoRowSeparator:$_no_row_separator
}