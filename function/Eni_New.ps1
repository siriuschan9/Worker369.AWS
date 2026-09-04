function New-Eni
{
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'SubnetName_GroupName')]
    [Alias('eni_new')]
    param(
        [Parameter(Position = 0)]
        [string]
        $Name,

        [Parameter(ParameterSetName = 'SubnetId_GroupId', Mandatory)]
        [Parameter(ParameterSetName = 'SubnetId_GroupName', Mandatory)]
        [ValidatePattern('^subnet-[0-9a-f]{17}$', ErrorMessage = 'Invalid SubnetId.')]
        [string]
        $SubnetId,

        [Parameter(ParameterSetName = 'SubnetName_GroupId', Mandatory)]
        [Parameter(ParameterSetName = 'SubnetName_GroupName', Mandatory)]
        [string]
        $SubnetName,

        [Parameter(ParameterSetName = 'SubnetId_GroupId', Mandatory)]
        [Parameter(ParameterSetName = 'SubnetName_GroupId', Mandatory)]
        [string[]]
        $GroupId,

        [Parameter(ParameterSetName = 'SubnetId_GroupName', Mandatory)]
        [Parameter(ParameterSetName = 'SubnetName_GroupName', Mandatory)]
        [string[]]
        $GroupName,

        [string[]]
        $Ipv4Addr,

        [string[]]
        $Ipv6Addr,

        [string[]]
        $Ipv4Prefix,

        [string[]]
        $Ipv6Prefix,

        [Amazon.EC2.Model.Tag[]]
        $Tag
    )

    BEGIN
    {
        # For easy pickup.
        $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name
        $_param_set   = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_name        = $Name
        $_subnet_id   = $SubnetId
        $_subnet_name = $SubnetName
        $_ipv4_addr   = $Ipv4Address ?? @()
        $_ipv6_addr   = $Ipv6Address ?? @()
        $_ipv4_prefix = $Ipv4Prefix ?? @()
        $_ipv6_prefix = $Ipv6Prefix ?? @()
        $_group_id    = $GroupId
        $_group_name  = $GroupName
        $_tag         = $Tag

        # Configure the filter to query the Subnet.
        $_filter_name  = $_param_set -like 'SubnetId*' ? 'subnet-id' : 'tag:Name'
        $_filter_value = $_param_set -like 'SubnetId*' ? $_subnet_id : $_subnet_name

        # Query the subnet to create the ENI first.
        try {
            $_subnet_list = Get-EC2Subnet -Verbose:$false -Filter @{Name = $_filter_name; Values = $_filter_value}
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If no Subnet matched the filter value, exit early.
        if (-not $_subnet_list)
        {
            Write-Error "No Subnet was found for '$_filter_value'."
            return
        }

        # If multiple Subnet matched the filter value, exit early.
        if ($_subnet_list.Count -gt 1)
        {
            Write-Error "Multiple Subnet was found for '$_filter_value'. It must matched exactly one Subnet."
            return
        }

        # Save a reference to the filtered Subnet.
        $_subnet = $_subnet_list[0]

        # Prepare TagSpecification parameter.
        $_make_tags_with_name    = { New-TagSpecification -ResourceType subnet -Tag $_tag -Name $_name}
        $_make_tags_without_name = { New-TagSpecification -ResourceType subnet -Tag $_tag }
        $_has_name               = $PSBoundParameters.ContainsKey('Name')
        $_tag_specification      = $_has_name ? (& $_make_tags_with_name) : (& $_make_tags_without_name)

        # Find out if subnet has been allocated IPv4 & IPv6 CIDR blocks
        $_subnet_has_ipv4_cidr = $_subnet.CidrBlock -as [bool]
        $_subnet_has_ipv6_cidr = $_subnet.Ipv6CidrBlockAssociationSet -as [bool]

        # Validate IP Assignments.
        $_auto_assign_ipv4_addr = ($_ipv4_addr -match 'auto-\d{1,2}') -as [bool]
        $_auto_assign_ipv6_addr = ($_ipv6_addr -match 'auto-\d{1,2}') -as [bool]

        # Generate a friendly display string for the Subnet.
        $_format_subnet = $_subnet | Get-ResourceString `
            -IdPropertyName 'SubnetId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

        # Display What-If/Confirm prompt.
        if (-not $PSCmdlet.ShouldProcess($_format_subnet, 'Create ENI')) { return }

        try {
            # Call the API to create new subnet.
            $_new_eni = New-EC2NetworkInterface -Verbose:$false `
                -SubnetId         $_subnet.SubnetId `
                -TagSpecification $_tag_specification `

        }
        catch{
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Since no Subnet is created, exit early here.
            return
        }
    }
}

# Auto Assign IPv4 Address
# Auto Assign IPv4 Prefix
# Auto Assign IPv6 Address
# Auto Assign IPv6 Prefixes
# Manual Assign IPv4 Address
# Manual Assign IPv4 Prefixes

function Test-Parameter
{
    [OutputType([PSObject])]
    [CmdletBinding()]
    param (
        [Parameter()]
        [Amazon.EC2.Model.Subnet]
        $Subnet,

        [string[]]
        $Ipv4Addr,

        [string[]]
        $Ipv6Addr,

        [string[]]
        $Ipv4Prefix,

        [string[]]
        $Ipv6Prefix
    )

}