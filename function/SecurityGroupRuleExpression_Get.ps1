using namespace System.Management.Automation

function Get-SecurityGroupRuleExpression
{
    [Alias('sgr_expr')]
    [CmdletBinding(DefaultParameterSetName = 'SecurityGroupRuleId')]
    [OutputType([string])]

    param (
        [Parameter(
            ParameterSetName = 'SecurityGroupRuleId',
            Position = 0,
            Mandatory,
            ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('RuleId')]
        [ValidatePattern('sgr-[0-9a-f]{17}')]
        [String]
        $SecurityGroupRuleId,

        [Parameter(ParameterSetName = 'GroupId', Mandatory)]
        [ValidatePattern('sg-[0-9a-f]{17}')]
        [String]
        $GroupId
    )

    BEGIN
    {
        # For easy pick up later.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Copy parameter to private variable
        $_rule_id  = $SecurityGroupRuleId
        $_group_id = $GroupId

        $_filter_name  = $_param_set -eq 'SecurityGroupRuleId' ? 'security-group-rule-id' : 'group-id'
        $_filter_value = $_param_Set -eq 'SecurityGroupRuleId' ? $_rule_id : $_group_id

        try {
            $_rule_list = Get-EC2SecurityGroupRule -Verbose:$false -Filter @{
                Name   = $_filter_name
                Values = $_filter_value
            }
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Continue the next item in the pipeline
            return
        }

        foreach ($_rule in $_rule_list)
        {
            # 1. Direction
            $_direction = $_rule.IsEgress ? 'out' : 'in'

            # 2. Protocol
            $_protocol = $_rule.IpProtocol

            # 3. Port Range
            $_port_range =
            if($_rule.IpProtocol -eq 'icmp' -or $_rule.IpProtocol -eq 'icmpv6') {
                "$($_rule.FromPort),$($_rule.ToPort)"

            } elseif($_rule.FromPort -eq $_rule.ToPort) { # includes -1 {
                "$($_rule.FromPort)"
            }
            else {
                "$($_rule.FromPort)-$($_rule.ToPort)"
            }

            # 4. Remote Address
            $_remote_addr = $_rule.PrefixListId
            $_remote_addr = $_remote_addr ?? $_rule.ReferencedGroupInfo.GroupId
            $_remote_addr = $_remote_addr ?? $_rule.CidrIpv4
            $_remote_addr = $_remote_addr ?? $_rule.CidrIpv6

            # 5. Description
            $_description = $_rule.Description

            # Return the expression
            "$($_direction)$($PSSTyle.Dim);$($PSSTyle.Reset)" +
            "$($_protocol)$($PSSTyle.Dim);$($PSSTyle.Reset)" +
            "$($_port_range)$($PSSTyle.Dim);$($PSSTyle.Reset)" +
            "$($_remote_addr)$($PSSTyle.Dim);$($PSSTyle.Reset)" +
            "$($_description)"
        }
    }
}