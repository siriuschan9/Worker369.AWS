using namespace System.Management.Automation

function Add-SecurityGroupRule
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^(sg-([0-9a-fA-F]{8}|[0-9a-fA-F]{17}))|(sg(\.[0-9a-zA-Z-]+)+(\.[0-9a-zA-Z-]+)*)$')]
        [String]
        $GroupId,

        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidatePattern('in|out;.+;.*;.+;.*')] # direction; protocol; port range; remote addresses; description
        [String]
        $RuleExpression
    )

    BEGIN
    {
        # IpProtocol = -1 means all protocols
        # FromPort = -1 means all icmp types
        # ToPort   = -1 means all icmp codes
        # For all tcp/udp ports, use 0 to 65535

        # Regular expression for port range
        # Port number is 16 bit
        # Eg. 0 - 65536 => all ports
        $REGEX_PORT_RANGE = '^([0-9]|[1-9][0-9]|[1-9][0-9]{2}|[1-9][0-9]{3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])(-([0-9]|[1-9][0-9]|[1-9][0-9]{2}|[1-9][0-9]{3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5]))?$'

        # Regular expression for ICMP expression: <type>, <code>
        # type and code are both 8-bit numbers
        # Eg. -1, -1 => All ICMP
        # Eg.  8, -1 => echo request
        # Eg.  3,  4 => destinable unreachabled, fragmentation neded but DF was set
        $REGEX_ICMP_EXPR = '^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])|\-1),(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])|\-1)$'

        # Regular expression for IPv4 prefix
        $REGEX_IPV4 = '^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\/([0-9]|[1-2][0-9]|3[0-2])$'

        # Regular expression for IPv6 prefix
        $REGEX_IPV6 = '^(([]0-9a-fA-F]{0,4}:){1,7}[]0-9a-fA-F]{0,4})\/([0-9]|[1-9][0-9]|1[0-1][0-9]|12[0-8])$'

        # Regular expression for prefix list ID
        $REGEX_PL = '^pl-([0-9a-fA-F]{8}|[0-9a-fA-F]{17})$'

        # Regular expression for prefix list name
        $REGEX_PL_NAME = '^pl(4|6)(-[0-9a-zA-Z-]+)+(-[0-9a-zA-Z-]+)*$'

        # Regular expression for security group ID
        $REGEX_SG_ID = '^sg-([0-9a-fA-F]{8}|[0-9a-fA-F]{17})$'

        # Regular expression for security group ID in local AWS account - Same as $REGEX_ID_ID
        $REGEX_SG_LOCAL = '^sg-([0-9a-fA-F]{8}|[0-9a-fA-F]{17})$'

        # Regular expression for security group ID in another AWS account
        $REGEX_SG_FOREIGN = '^\d{12}\/sg-([0-9a-fA-F]{8}|[0-9a-fA-F]{17})$'

        # Regular expression for security group name
        $REGEX_SG_NAME = '^sg(-[0-9a-zA-Z-]+)+(-[0-9a-zA-Z-]+)*$'
    }

    PROCESS
    {
        # Copy parameters to private variables
        $_group_id        = $GroupId
        $_rule_expression = $RuleExpression

        # extract field values from rule expression
        $_fields           = $_rule_expression -split ';'
        $_direction        = $_fields[0].Trim()
        $_protocol         = $_fields[1].Trim()
        $_port_range       = $_fields[2] -replace ' '
        $_remote_addresses = $_fields[3].Trim()
        $_description      = $_fields[4].Trim()

        # Create IpPermissions object
        $_ip_permission            = [Amazon.EC2.Model.IpPermission]::new()
        $_ip_permission.IpProtocol = $_protocol
        #$_ip_permission.Ipv4Ranges       = [System.Collections.Generic.List[Amazon.EC2.Model.IpRange]]::new()
        #$_ip_permission.Ipv6Ranges       = [System.Collections.Generic.List[Amazon.EC2.Model.Ipv6Range]]::new()
        #$_ip_permission.PrefixListIds    = [System.Collections.Generic.List[Amazon.EC2.Model.PrefixListId]]::new()
        #$_ip_permission.UserIdGroupPairs = [System.Collections.Generic.List[Amazon.EC2.Model.UserIdGroupPair]]::new()

        # -1 means all traffic
        if($_protocol -eq -1 -or $_protocol -eq 'all')
        {
            # force -1 on FromPort and ToPort
            $_ip_permission.FromPort = -1
            $_ip_permission.ToPort   = -1
        }
        elseif($_protocol -eq 'icmp' -or $_protocol -eq 'icmpv6')
        {
            $_icmp_expr = $_port_range
            if($_icmp_expr -notmatch $REGEX_ICMP_EXPR)
            {
                $_error_record = [ErrorRecord]::new(
                    [Exception]::new("Invalid ICMP expression: $($_icmp_expr)"),
                    'InvalidIcmpExpression', # Error ID
                    [ErrorCategory]::InvalidArgument,
                    $null)

                $PSCmdlet.ThrowTerminatingError($_error_record)
            }
            $_icmp_split             = $_icmp_expr -split ','
            $_ip_permission.FromPort = $_icmp_split[0]
            $_ip_permission.ToPort   = $_icmp_split[1]
        }
        elseif($_port_range -eq -1)
        {
            $_ip_permission.FromPort = -1
            $_ip_permission.ToPort   = -1
        }
        else
        {
            if($_port_range -notmatch $REGEX_PORT_RANGE)
            {
                $_error_record = [ErrorRecord]::new(
                    [Exception]::new("Invalid port range: $($_port_range)"),
                    'InvalidPortRange', # Error ID
                    [ErrorCategory]::InvalidArgument,
                    $null)

                $PSCmdlet.ThrowTerminatingError($_error_record)
            }
            # set ToPort same as FromPort if no range detected
            $_port_split             = $_port_range -split '-'
            $_ip_permission.FromPort = $_port_split[0]
            $_ip_permission.ToPort   = $_port_split[1] ? $_port_split[1] : $_port_split[0]
        }

        # Resolve remote addresses
        $_remote_address_array = $_remote_addresses -split ','
        foreach($_remote_address in $_remote_address_array)
        {
            if($_remote_address -match $REGEX_IPV4)
            {
                $_ip_permission.Ipv4Ranges.Add([Amazon.EC2.Model.IpRange]@{
                    CidrIp      = $_remote_address
                    Description = $_description
                })
            }
            elseif($_remote_address -match $REGEX_IPV6)
            {
                $_ip_permission.Ipv6Ranges.Add([Amazon.EC2.Model.Ipv6Range]@{
                    CidrIpv6    = $_remote_address
                    Description = $_description
                })
            }
            elseif($_remote_address -match $REGEX_PL)
            {
                $_ip_permission.PrefixListIds.Add([Amazon.EC2.Model.PrefixListId]@{
                    Id          = $_remote_address
                    Description = $_description
                })
            }
            elseif($_remote_address -match $REGEX_PL_NAME)
            {
                Write-Status -WriteProgress -Activity "[$($PSCmdlet.MyInvocation.InvocationName)]" -Message "Searching prefix list $($_remote_address)."
                $_prefix_list = Get-EC2ManagedPrefixList -Filter @{Name='prefix-list-name'; Values=$_remote_address} -Verbose:$false

                if(-not $_prefix_list)
                {
                    $_error_record = [ErrorRecord]::new(
                        [Exception]::new("Prefix list not found: $($_remote_address)"),
                        'PrefixListNotFound', # Error ID
                        [ErrorCategory]::InvalidArgument,
                        $null)

                    $PSCmdlet.ThrowTerminatingError($_error_record)
                }

                $_ip_permission.PrefixListIds.Add([Amazon.EC2.Model.PrefixListId]@{
                    Id          = $_prefix_list.PrefixListId
                    Description = $_description
                })
            }
            elseif($_remote_address -match $REGEX_SG_LOCAL)
            {
                $_ip_permission.UserIdGroupPairs.Add([Amazon.EC2.Model.UserIdGroupPair]@{
                    GroupId     = $_remote_address
                    Description = $_description
                })
            }
            elseif($_remote_address -match $REGEX_SG_FOREIGN)
            {
                $_ip_permission.UserIdGroupPairs.Add([Amazon.EC2.Model.UserIdGroupPair]@{
                    GroupId     = ($_remote_address -split '/')[1]
                    UserId      = ($_remote_address -split '/')[0]
                    Description = $_description
                })
            }
            elseif($_remote_address -match $REGEX_SG_NAME)
            {
                Write-Status -WriteProgress -Activity "[$($PSCmdlet.MyInvocation.InvocationName)]" -Message "Searching security group $($_remote_address)"
                $_security_group = Get-EC2SecurityGroup -Filter @{Name='group-name'; Values=$_remote_address} -Verbose:$false

                if(-not $_security_group)
                {
                    $_error_record = [ErrorRecord]::new(
                        [Exception]::new("Security group name not found: $($_remote_address)"),
                        'SecurityGroupNameNotFound', # Error ID
                        [ErrorCategory]::InvalidArgument,
                        $null)

                    $PSCmdlet.ThrowTerminatingError($_error_record)
                }

                $_ip_permission.UserIdGroupPairs.Add([Amazon.EC2.Model.UserIdGroupPair]@{
                    GroupId     = $_security_group.GroupId
                    Description = $_description
                })
            }
            else
            {
                $_error_record = [ErrorRecord]::new(
                    [Exception]::new("Invalid remote address: $($_remote_address)"),
                    'InvalidRemoteAddress', # Error ID
                    [ErrorCategory]::InvalidArgument,
                    $null)

                $PSCmdlet.ThrowTerminatingError($_error_record)
            }
        }

        # Check if group to modify can be found
        if($_group_id -match $REGEX_SG_ID)
        {
            if(-not ($_sg_to_modify = Get-EC2SecurityGroup -Filter @{Name = 'group-id'; Values = $_group_id} -Verbose:$false))
            {
                $_error_record = [ErrorRecord]::new(
                    [Exception]::new("No matching group ID found: $($_group_id)"),
                    'SecurityGroupNotFound', # Error ID
                    [ErrorCategory]::InvalidArgument,
                    $null)

                $PSCmdlet.ThrowTerminatingError($_error_record)
            }
        }
        else
        {
            $_group_name = $_group_id
            $_sg_to_modify_list = @(Get-EC2SecurityGroup -Filter @{Name = 'group-name'; Values = $_group_name} -Verbose:$false)

            if($_sg_to_modify_list.Length -eq 0)
            {
                $_error_record = [ErrorRecord]::new(
                    [Exception]::new("No matching group name found: $($_group_name)"),
                    'SecurityGroupNotFound', # Error ID
                    [ErrorCategory]::InvalidArgument,
                    $null)

                $PSCmdlet.ThrowTerminatingError($_error_record)
            }

            if($_sg_to_modify_list.Length -gt 1)
            {
                $_error_record = [ErrorRecord]::new(
                    [Exception]::new("Multiple matching groups found: $($_sg_to_modify_list.GroupName -join ', ')"),
                    'AmbigiousSecurityGroupName', # Error ID
                    [ErrorCategory]::InvalidArgument,
                    $null)

                $PSCmdlet.ThrowTerminatingError($_error_record)
            }

            $_sg_to_modify = $_sg_to_modify_list[0]
        }

        # Add security group rule
        try{
            Write-Status -WriteProgress -Activity "[$_rule_expression]" -Message "Adding security group rule to $($_group_id)."
            $_action = $_direction -eq 'in' ?
            {Grant-EC2SecurityGroupIngress -GroupId $_sg_to_modify.GroupId -IpPermission $_ip_permission -Verbose:$false} :
            {Grant-EC2SecurityGroupEgress  -GroupId $_sg_to_modify.GroupId -IpPermission $_ip_permission -Verbose:$false}

            $_response = Invoke-Command $_action
            $_rule_id  = $_response.SecurityGroupRules.SecurityGroupRuleId

            New-EC2Tag -Resource $_rule_id -Tag @{Key='ID'; Value=$_rule_id} -Verbose:$false | Out-Null

            Write-Status -WriteProgress -Activity "[$($PSCmdlet.MyInvocation.InvocationName)]" -Message "New security group rule $($_rule_id) added to $($_group_id) successfully."

            return $_rule_id
        }
        catch {
            # Remove caught exception emitted into $Error list.
            [ErrorUtil]::RemoveLastErrorIfEqual($_) | Out-Null

            # Re-throw caught error.
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }

    END {}
}