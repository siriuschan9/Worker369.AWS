function Set-SubnetHostnameType
{
    [Alias('subnet_host')]
    [CmdletBinding(DefaultParameterSetName = 'SubnetName', SupportsShouldProcess)]
    param (
        [Parameter(ParameterSetName = 'SubnetId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]
        $SubnetId,

        [Parameter(ParameterSetName = 'SubnetName', Mandatory, Position = 0)]
        [string[]]
        $SubnetName,

        [Parameter(ParameterSetName = 'SubnetId', Mandatory)]
        [Parameter(ParameterSetName = 'SubnetName', Mandatory, Position = 1)]
        [Amazon.EC2.HostnameType]
        $HostnameType
    )

    BEGIN
    {
        # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_subnet_id   = $SubnetId
        $_subnet_name = $SubnetName
        $_hostname_type = $HostnameType

        # Configure the filter to query the Subnet.
        $_filter_name  = $_param_set -eq 'SubnetId' ? 'subnet-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'SubnetId' ? $_subnet_id : $_subnet_name

        # Query the list of Subnet first.
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

        # Loop through each Subnet to edit the attribute.
        $_subnet_list | ForEach-Object {

            # Generate a friendly display string for this Subnet.
            $_format_subnet = $_ | Get-ResourceString `
                -IdPropertyName 'SubnetId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            # Display What-If/Confirm prompt.
            if ($PSCmdlet.ShouldProcess($_format_subnet, 'Set DNS Hostname Type on Launch'))
            {
                # Edit the subnet's attribute.
                try {
                    Edit-EC2SubnetAttribute -Verbose:$false -PrivateDnsHostnameTypeOnLaunch $_hostname_type $_.SubnetId
                }
                catch {
                    # Remove caught exception emitted into $Error list.
                    Pop-ErrorRecord $_

                    # Report error as non-terminating.
                    $PSCmdlet.WriteError($_)
                }
            }
        }
    }
}