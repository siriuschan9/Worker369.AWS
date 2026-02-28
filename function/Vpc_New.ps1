<#
.SYNOPSIS
This cmdlet creates a new VPC. If VPC attributes are specified, they will be applied to the new VPC.

.PARAMETER Name
The -Name Parameter specifies the Name of the VPC.
If the -Tag Parameter includes a 'Name' Tag, it will be overwritten by the -Name Paramater.

.PARAMETER Tenancy
The valid values for the -Tenancy Parameter are 'dedicated', 'default', 'host'.
If unspecified, the default value is 'default'.

.PARAMETER Ipv4Cidr
An IPv4 CIDR block is mandatory for a new VPC.

.PARAMETER AssignIpv6Cidr
Setting the -AssignIpv6Cidr Parameter to "true" assigns an Amazon-Provided IPv6 CIDR block to the VPC.

.PARAMETER EnableDnsResolution
DNS resolution support is enabled by default for new VPCs.
To disable DNS resolution support, you must specify -EnableDnsResolution:$false.

.PARAMETER EnableDnsHostnames
DNS hostnames is disabled by default for new VPCs.
To enable DNS hostnames, specify -EnableDnsHostnames.

.PARAMETER EnableNauMetrics
NAU metrics is disabled by default for new VPCs.
To enable NAU metrics, specify -EnableNauMetrics.

.PARAMETER Tag
The -Tag Parameter specifies the Tags to add to the VPC.

.EXAMPLE
New-Vpc -Ipv4Cidr 10.20.30.0/24 vpc-example-1

This example creates a new VPC with CIDR block 10.20.30.0/24 and assign a Name tag of value 'vpc-example-1'.

.EXAMPLE
New-Vpc -Ipv4Cidr 10.20.30.0/24 -AssignIpv6Cidr vpc-example-2

This example creates a new VPC with IPv4 and IPv6 CIDR blocks.

.EXAMPLE
New-Vpc -Ipv4Cidr 10.20.30.0/24 -AssignIpv6Cidr -EnableDnsHostnames -EnableNauMetrics vpc-example-3

This example creates a new VPC with IPv4 and IPv6 CIDR blocks and enables all the available attributes. -EnableDnsResolution is enabled by default.

.EXAMPLE
New-Vpc -Ipv4Cidr 10.20.30.0/24 -EnableDnsResolution:$false vpc-example-4

This example creates a new VPC with no DNS resolution support.
#>

function New-Vpc
{
    [Alias('vpc_add')]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Position = 0)]
        [string]
        $Name,

        [Parameter()]
        [Amazon.EC2.Tenancy]
        $Tenancy,

        [Parameter(Mandatory)]
        [ValidatePattern(
            '^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}' + # 255.255.255.
            '([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])' +         # 255
            '\/([0-9]|[1-2][0-9]|3[0-2])$',                                # /32
            ErrorMessage = 'Invalid Ipv4Cidr block.'
        )]
        [string]
        $Ipv4Cidr,

        [Parameter()]
        [switch]
        $AssignIpv6Cidr,

        [Parameter()]
        [switch]
        $EnableDnsResolution,

        [Parameter()]
        [switch]
        $EnableDnsHostnames,

        [Parameter()]
        [switch]
        $EnableNauMetrics,

        [Parameter()]
        [Amazon.EC2.Model.Tag[]]
        $Tag
    )

    BEGIN
    {
        # Check if the default AWS Region is set in the caller's shell.
        if (-not ($_region = Get-DefaultAWSRegion))
        {
            $_error = New-ErrorRecord `
                -ErrorMessage "Default AWS region not set. Use Set-DefaultAWSRegion to set the default AWS region." `
                -ErrorId 'DefaultAWSRegionNotSet' `
                -ErrorCategory NotSpecified

            $PSCmdlet.ThrowTerminatingError($_error)
        }
    }

    PROCESS
    {
        # Use snake_case.
        $_name                  = $Name
        $_tenancy               = $Tenancy
        $_ipv4_cidr             = $Ipv4Cidr
        $_assign_ipv6_cidr      = $AssignIpv6Cidr.IsPresent
        $_enable_dns_resolution = $EnableDnsResolution.IsPresent
        $_enable_dns_hostnames  = $EnableDnsHostnames.IsPresent
        $_enable_nau_metrics    = $EnableNauMetrics.IsPresent
        $_tag                   = $Tag

        # Prepare TagSpecification parameter.
        $_make_tags_with_name    = { New-TagSpecification -ResourceType vpc -Tag $_tag -Name $_name }
        $_make_tags_without_name = { New-TagSpecification -ResourceType vpc -Tag $_tag }
        $_has_name               = $PSBoundParameters.ContainsKey('Name')
        $_tag_specification      = $_has_name ? (& $_make_tags_with_name) : (& $_make_tags_without_name)

        # Display What-If/Confirm prompt.
        if (-not $PSCmdlet.ShouldProcess("Region: $_region", "Create New VPC")) { return }

        # 1. Create the VPC.
        Write-Verbose 'Creating VPC.'
        try {
            $_new_vpc = New-EC2Vpc -Verbose:$false `
                -InstanceTenancy             $_tenancy `
                -CidrBlock                   $_ipv4_cidr `
                -AmazonProvidedIpv6CidrBlock $_assign_ipv6_cidr `
                -TagSpecification            $_tag_specification
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Since no VPC is created, exit early here.
            return
        }

        # Save a reference to VPC ID for easy pick up later.
        $_new_vpc_id = $_new_vpc.VpcId

        # Output VPC ID.
        Write-Message -Output "VpcId: $_new_vpc_id"

        # 2. Set VPC attribute - DNS Support
        if ($PSBoundParameters.ContainsKey('EnableDnsResolution'))
        {
            $_action = $_enable_dns_resolution ? 'Enabling' : 'Disabling'
            Write-Verbose "$_action DNS resolution support."

            try{
                Edit-EC2VpcAttribute -Verbose:$false -EnableDnsSupport $_enable_dns_resolution $_new_vpc_id
            }
            catch {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                # Report error as non-terminating as that the rest of the code can continue.
                $PSCmdlet.WriteError($_)
            }
        }

        # 3. Set VPC attribute: DNS Hostnames
        if($PSBoundParameters.ContainsKey('EnableDnsHostnames'))
        {
            $_action = $_enable_dns_hostnames ? 'Enabling' : 'Disabling'
            Write-Verbose "$_action DNS hostnames."

            try{
                Edit-EC2VpcAttribute -Verbose:$false -EnableDnsHostname $_enable_dns_hostnames $_new_vpc_id
            }
            catch {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                # Report error as non-terminating as that the rest of the code can continue.
                $PSCmdlet.WriteError($_)
            }
        }

        # 4. Set VPC attribute: NAU Metrics
        if($PSBoundParameters.ContainsKey('EnableNauMetrics'))
        {
            $_action = $_enable_nau_metrics ? 'Enabling' : 'Disabling'
            Write-Verbose "$_action NAU metrics."

            $_cli_action = $_enable_nau_metrics `
                ? '--enable-network-address-usage-metrics'
                : '--no-enable-network-address-usage-metrics'

            try{
                aws ec2 modify-vpc-attribute $_cli_action `
                    --vpc-id $_new_vpc_id `
                    --profile $StoredAWSCredentials `
                    --region $StoredAWSRegion
            }
            catch {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                # Report error as non-terminating as that the rest of the code can continue.
                $PSCmdlet.WriteError($_)
            }
        }
    }
}