function Show-Elb
{
    [CmdletBinding()]
    [Alias('elb_show')]
    param (
        [Parameter(Position = 0)]
        [ValidateSet('Network', 'Security')]
        [string]
        $View = 'Network',

        [ValidateSet('Vpc', 'Type', 'Scheme')]
        [string]
        $GroupBy = 'Vpc',

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
    $_view             = $View
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_where            = $Where
    $_pass_thru        = $PassThru.IsPresent
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    # For easy pick-up.
    $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name
    $_dash        = $_plain_text ? '-' : "$($PSStyle.Dim)-$($PSStyle.Reset)"

    # Each view defines an array of property names.
    $_view_definition = @{
        'Network' = @(
            'ElbName', 'Type', 'DnsName', 'AvailabilityZone', 'NetworkInterface', 'PrivateIp', 'PublicIp',
            'Ipv6Address'
        )
        'Security' = @(
            'ElbName', 'Type', 'Scheme', 'Listener', 'SecurityGroup', 'WAF', 'DeletionProtection'
        )
    }

    # Hashtable for Select-Object.
    $_select_definition = @{
        AvailabilityZone = {
            $_eni_lookup[$_.EniDescription] |
            Sort-Object AvailabilityZone, NetworkInterfaceId |
            Select-Object -ExpandProperty AvailabilityZone
        }
        DeletionProtection = {
            $_value = $_attribute_lookup[$_.LoadBalancerArn] |
            Where-Object Key -eq 'deletion_protection.enabled' |
            Select-Object -ExpandProperty Value

            $_checked     = $_value -eq 'true'
            $_description = $_checked ? 'Enabled': 'Disabled'
            New-Checkbox -PlainText:$_plain_text -Description $_description $_checked
        }
        DnsName = {
            $_.DnsName
        }
        ElbName = {
            $_.LoadBalancerName
        }
        Ipv6Address = {
            $_eni_lookup[$_.EniDescription] |
            Sort-Object AvailabilityZone, NetworkInterfaceId |
            ForEach-Object {
                $_.Ipv6Addresses `
                    ? ($_.Ipv6Addresses.Ipv6Address | New-IPv6Address) `
                    : $_dash
            }
        }
        Listener = {
            $_listener_lookup[$_.LoadBalancerArn] | ForEach-Object {
                $_has_tls = $null -ne $_.SslPolicy
                $_has_tls ? "$($_.Protocol):$($_.Port) - $($_.SslPolicy)" : "$($_.Protocol):$($_.Port)"
            }
        }
        NetworkInterface = {
            $_eni_lookup[$_.EniDescription] |
            Sort-Object AvailabilityZone, NetworkInterfaceId |
            ForEach-Object {
                $_ | Get-ResourceString -IdPropertyName NetworkInterfaceId -TagPropertyName Tags -PlainText:$_plain_text
            }
        }
        PrivateIp = {
            $_eni_lookup[$_.EniDescription] |
            Sort-Object ssAvailabilityZone, NetworkInterfaceId |
            ForEach-Object {
                $_.PrivateIpAddresses `
                    ? ($_.PrivateIpAddresses.PrivateIpAddress | New-IPv4Address) `
                    : $_dash
            }
        }
        PublicIp = {
            $_eni_lookup[$_.EniDescription] |
            Sort-Object AvailabilityZone, NetworkInterfaceId |
            ForEach-Object {
                $_.Association `
                    ? ($_.Association.PublicIp | New-IPv4Address) `
                    : $_dash
            }
        }
        Scheme = {
            $_.Scheme
        }
        SecurityGroup = {
            $_.SecurityGroups | ForEach-Object {
                $_sg_lookup[$_] |
                Get-ResourceString -IdPropertyName 'GroupId' -NamePropertyName 'GroupName' -PlainText:$_plain_text
            }
        }
        Type = {
            $_.Type
        }
        Vpc = {
            $_vpc_lookup[$_.VpcId] |
            Get-ResourceString -IdPropertyName VpcId -TagPropertyName Tags -PlainText:$_plain_text
        }
        WAF = {
            if ($_.Type -eq 'application') {
                $_waf = $_waf_lookup[$_.LoadBalancerArn] | Select-Object -ExpandProperty Name
                $_waf = $_waf ?? 'No WAF Attached'
                New-Checkbox -PlainText:$_plain_text -Description $_waf ($_waf -ne 'No WAF Attached')
            } else {
                New-Checkbox -PlainText:$_plain_text -Description 'Not Applicable' $false
            }
        }
    }

    try {
        # Fetch ELB information.
        Write-Message -Progress $_cmdlet_name 'Fetching ELB information.'
        $_elb_list = Get-ELB2LoadBalancer -Verbose:$false | ForEach-Object {
            $_part1 = $_.Type -eq 'application' ? 'ELB app' : $_.Type -eq 'network' ? 'ELB net' : 'ELB gwy'
            $_part2 = $_.LoadBalancerName
            $_part3 = $_.LoadBalancerArn -split '/' | Select-Object -Last 1
            $_ | Add-Member EniDescription "$($_part1)/$($_part2)/$($_part3)"
            $_
        }

        # Exit early if there are no target groups.
        if (-not $_elb_list) { return }

        # Fetch VPC information.
        Write-Message -Progress $_cmdlet_name 'Fetching ELB information.'
        $_vpc_lookup = `
            Get-EC2Vpc -Verbose:$false -Filter @{ Name = 'vpc-id'; Values = $_elb_list.VpcId } |
            Group-Object -AsHashTable VpcId

        # Fetch ENI information.
        Write-Message -Progress $_cmdlet_name 'Fetching ENI information.'
        $_eni_lookup = Get-EC2NetworkInterface -Verbose:$false -Filter @{
            Name   = 'description'
            Values = $_elb_list.EniDescription
        } | Group-Object -AsHashTable Description

        if ($_view -in @('Security'))
        {
            # Fetch ELB attributes.
            Write-Message -Progress $_cmdlet_name 'Fetching ELB attributes.'
            $_attribute_lookup = @{}
            $_elb_list | ForEach-Object {
                $_attribute_lookup[$_.LoadBalancerArn] = `
                    Get-ELB2LoadBalancerAttribute -Verbose:$false $_.LoadBalancerArn
            }
            # Fetch ELB Listeners.
            Write-Message -Progress $_cmdlet_name 'Fetching ELB listeners.'
            $_listener_lookup = @{}
            $_elb_list | ForEach-Object {
                $_listener_lookup[$_.LoadBalancerArn] = `
                    Get-ELB2Listener -Verbose:$false -LoadBalancerArn $_.LoadBalancerArn
            }
            # Fetch WAF.
            Write-Message -Progress $_cmdlet_name 'Fetching WAF attachments.'
            $_waf_lookup = @{}
            $_elb_list | Where-Object Type -eq 'application' | ForEach-Object {
                $_waf_lookup[$_.LoadBalancerArn] = `
                    Get-WAF2WebACLForResource -Verbose:$false $_.LoadBalancerArn
            }
            # Fetch security groups.
            Write-Message -Progress $_cmdlet_name 'Fetching security groups.'
            $_sg_lookup = Get-EC2SecurityGroup -Verbose:$false -Filter @{
                Name   = 'group-id'
                Values = $_elb_list.SecurityGroups
            } | Group-Object -AsHashTable GroupId
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
    $_output = $_elb_list `
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
    $_align_left  = @('WAF', 'DeletionProtection')
    $_align_right = @()
    $_output | Format-Column `
        -AlignLeft $_align_left `
        -AlignRight $_align_right `
        -GroupBy $_group_by `
        -PlainText:$_plain_text `
        -NoRowSeparator:$_no_row_separator
}