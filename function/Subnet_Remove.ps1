<#
.SYNOPSIS
This cmdlet removes one or more Subnet(s).
You can specify the Subnet(s) using either the -SubnetName or -SubnetId Parameter.

.PARAMETER SubnetId
The -SubnetId Parameter specifies the Subnet ID.
You can also pass in an array of Subnet IDs.
This parameter supports pipeline inputs.
See example 1.

.PARAMETER SubnetName
The -SubnetName Parameter specifies the Subnet's Name.
You can use glob wildcards to match multiple Subnets.
You can also pass in an array of Names.
See example 2.

.EXAMPLE
Remove-Subnet -SubnetId subnet-1234567890abcdef0

This example removes the Subnet subnet-1234567890abcdef0.

.EXAMPLE
Remove-Subnet -SubnetName example-*

This example removes all Subnets with Name that starts with "example-".

#>
function Remove-Subnet
{
    [Alias("subnet_rm")]
    [CmdletBinding(DefaultParameterSetName = 'SubnetName', SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(ParameterSetName = 'SubnetId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^subnet-[0-9a-f]{17}$', ErrorMessage = 'Invalid SubnetId.')]
        [string[]]
        $SubnetId,

        [Parameter(ParameterSetName = 'SubnetName', Mandatory, Position = 0)]
        [string[]]
        $SubnetName
    )

    BEGIN
    {
        # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_subnet_name = $SubnetName
        $_subnet_id   = $SubnetId

        # Configure the filter to query the Subnet.
        $_filter_name  = $_param_set -eq 'SubnetId' ? 'subnet-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'SubnetId' ? $_subnet_id : $_subnet_name

        # Query the list of Subnet to remove first.
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

        # If no subnet matched the filter value, exit early.
        if (-not $_subnet_list)
        {
            Write-Error "No Subnet was found for '$_filter_value'."
            return
        }

        # Loop through each subnet to perform the deletion.
        $_subnet_list | ForEach-Object {

            # Generate a friendly display string for the subnet.
            $_format_subnet = $_ | Get-ResourceString -IdPropertyName 'SubnetId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            # Display What-If/Confirm prompt.
            if ($PSCmdlet.ShouldProcess($_format_subnet, "Remove Subnet"))
            {
                # Remove the subnet.
                try {
                    Remove-EC2Subnet -Verbose:$false -Confirm:$false $_.SubnetId
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