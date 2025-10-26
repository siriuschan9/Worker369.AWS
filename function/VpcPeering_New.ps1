<#
.SYNOPSIS
This cmdlet initiates a new VPC Peering Connection request.
A new VPC Peering Connection will be created with 'pending-acceptance' status.
The owner of the peered VPC must accept the peering request for the peering to be activated.
You can specify the peering using either:
    -ThisVpcId, -OtherVpcId
    or
    -ThisVpcName, -OtherVpcName

.PARAMETER ThisVpcId
The VPC ID of the requester.

.PARAMETER OtherVpcId
The VPC ID of the accepter.

.PARAMETER ThisVpcName
The Name of the requester. This name must be unique so that it can resolve to exactly one VPC.
This parameter set can only be used when both VPC are in the same account and same region.

.PARAMETER OtherVpcName
The Name of the accepter. This name must be unique so that it can resolve to exactly one VPC.
This parameter set can only be used when both VPC are in the same account and same region.

.PARAMETER OtherAccountId
The account ID of the accepter.

.PARAMETER OtherRegion
The region of the accepter

.PARAMETER Name
The -Name Parameter assigns a Name to this VPC Peering Connection.
If the -Tag Parameter includes a 'Name' Tag, it will be overwritten by the -Name Paramater.

.PARAMETER Tag
The -Tag Parameter specifies the Tags to add to the VPC.

.EXAMPLE
New-VpcPeering -ThisVpcId vpc-12345678901234567 -OtherVpcId vpc-abcedfabcdefabcde pcx-example-1

This example creates a new same-account-same-region VPC Peering request
from 'vpc-12345678901234567' to 'vpc-abcedfabcdefabcde', and names the connection 'pcx-example-1'.

.EXAMPLE
New-VpcPeering vpc-1 vpc-2 example-2

This example creates a new same-account-same-region VPC Peering request
from the VPC named 'vpc-1' to 'vpc-2', and names the connection 'pcx-example-2'.

.EXAMPLE
New-VpcPeering `
    -ThisVpcId    vpc-12345678901234567 `
    -OtherVpcId   vpc-abcedfabcdefabcde `
    -OtherRegion  ap-southeast-2 `
    -OtherAccount 333366669999 `
    -Tag          @{Name = 'Environment'; Value= 'Test'} `
    pcx-example-3

This example creates a new VPC Peering request from 'vpc-12345678901234567' to 'vpc-abcedfabcdefabcde'
from a different account and region, and names the connection 'pcx-example-3'.
It also tags the connection with 'Environment: Test'.
#>
function New-VpcPeering
{
    [CmdletBinding(DefaultParameterSetName = 'VpcName' ,SupportsShouldProcess)]
    [Alias('pcx_add')]
    param (
        [Parameter(ParameterSetName = 'VpcId', Mandatory)]
        [ValidatePattern('^vpc-[0-9a-f]{17}$', ErrorMessage = 'Invalid VpcId.')]
        [string]
        $ThisVpcId,

        [Parameter(ParameterSetName = 'VpcId', Mandatory)]
        [ValidatePattern('^vpc-[0-9a-f]{17}$', ErrorMessage = 'Invalid VpcId.')]
        [string]
        $OtherVpcId,

        [Parameter(ParameterSetName = 'VpcName', Position = 0, Mandatory)]
        [string]
        $ThisVpcName,

        [Parameter(ParameterSetName = 'VpcName', Position = 1, Mandatory)]
        [string]
        $OtherVpcName,

        [Parameter(ParameterSetName = 'VpcId')]
        [string]
        $OtherAccountId,

        [Parameter(ParameterSetName = 'VpcId')]
        [string]
        $OtherRegion,

        [Parameter(ParameterSetName = 'VpcId', Position = 0)]
        [Parameter(ParameterSetName = 'VpcName', Position = 2)]
        [string]
        $Name,

        [Amazon.EC2.Model.Tag[]]
        $Tag
    )

    # For easy pick up.
    $_param_set = $PSCmdlet.ParameterSetName

    # Use snake_case.
    $_this_vpc_id    = $ThisVpcId
    $_this_vpc_name  = $ThisVpcName
    $_other_vpc_id   = $OtherVpcId
    $_other_vpc_name = $OtherVpcName
    $_other_acct_id  = $OtherAccountId
    $_other_region   = $OtherRegion
    $_name           = $Name
    $_tag            = $Tag

    try{
        $_this_acct_id = (Get-STSCallerIdentity -Verbose:$false).Account
        $_this_region  = (Get-DefaultAWSRegion -Verbose:$false).Region

        if ($_param_set -eq 'VpcName')
        {
            [System.Diagnostics.Debug]::Assert([string]::IsNullOrEmpty($_other_acct_id))
            [System.Diagnostics.Debug]::Assert([string]::IsNullOrEmpty($_other_region))

            $_other_acct_id = $_this_acct_id
            $_other_region  = $_this_region
        }
        else
        {
            [System.Diagnostics.Debug]::Assert($_param_set -eq 'VpcId')

            if ([string]::IsNullOrEmpty($_other_acct_id)) {
                $_other_acct_id = $_this_acct_id
            }
            if ([string]::IsNullOrEmpty($_other_region)) {
                $_other_region = $_this_region
            }
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught error.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Configure the filter to query the VPC.
    if ($_param_set -eq 'VpcName')
    {
        $_this_vpc_filter  = [Amazon.EC2.Model.Filter]@{ Name = 'tag:Name'; Values = $_this_vpc_name }
        $_other_vpc_filter = [Amazon.EC2.Model.Filter]@{ Name = 'tag:Name'; Values = $_other_vpc_name }
    }
    else
    {
        $_this_vpc_filter  = [Amazon.EC2.Model.Filter]@{ Name = 'vpc-id'; Values = $_this_vpc_id }
        $_other_vpc_filter = [Amazon.EC2.Model.Filter]@{ Name = 'vpc-id'; Values = $_other_vpc_id }
    }

    # Query the VPC first.
    try {
        $_this_vpc = Get-EC2Vpc -Verbose:$false -Filter $_this_vpc_filter

        if ($_other_acct_id -eq $_this_acct_id)
        {
             $_other_vpc = Get-EC2Vpc -Verbose:$false -Region $_other_region -Filter $_other_vpc_filter
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught error.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # If no requester VPC matched the filter value, exit early.
    if (-not $_this_vpc)
    {
        Write-Error "No VPC was found for '$($_this_vpc_filter.Values)'."
        return
    }

    # If no accepter VPC matched the filter value, exit early.
    if ($_other_acct_id -eq $_this_acct_id -and -not $_other_vpc)
    {
        Write-Error "No VPC was found for '$($_other_vpc_filter.Values)'."
        return
    }

    # Prepare TagSpecification parameter.
    $_make_tags_with_name    = { New-TagSpecification -ResourceType vpc-peering-connection -Tag $_tag -Name $_name }
    $_make_tags_without_name = { New-TagSpecification -ResourceType vpc-peering-connection -Tag $_tag }
    $_has_name               = $PSBoundParameters.ContainsKey('Name')
    $_tag_specification      = $_has_name ? (& $_make_tags_with_name) : (& $_make_tags_without_name)

    [System.Diagnostics.Debug]::Assert(
        $null -ne $_other_vpc -or
        -not [string]::IsNullOrEmpty($_other_vpc_id)
    )

    # Generate a friendly display string for the requester.
    $_format_this_vpc = $_this_vpc | Get-ResourceString `
        -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

    # Generate a friendly display string for the accepter.
    $_format_other_vpc = $_other_vpc `
        ? ($_other_vpc | Get-ResourceString `
            -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText)
        : $_other_vpc_id

    # Prepare content for What-If/Confirm prompt.
    $_action = 'Create VPC Peering Connection.'
    $_target = 'Requester: {0} | Accepter: {1}' -f $_format_this_vpc, $_format_other_vpc

    # Display What-If/Confirm prompt.
    if (-not $PSCmdlet.ShouldProcess($_target, $_action)) { return }

    # Call the API to initiate the peering request.
    try {
        $_new_pcx = New-EC2VpcPeeringConnection -Verbose:$false `
            -VpcId $_this_vpc.VpcId `
            -PeerVpcId ($_other_vpc ? $_other_vpc.VpcId : $_other_vpc_id) `
            -PeerRegion $_other_region `
            -PeerOwnerId $_other_acct_id `
            -TagSpecification $_tag_specification

        # Output Peering ID.
        Write-Message `
            -Output "|- VpcPeeringConnectionId: $($_new_pcx.VpcPeeringConnectionId) => $($_new_pcx.Status.Code)"
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught error.
        $PSCmdlet.ThrowTerminatingError($_)
    }
}