<#
.SYNOPSIS
This cmdlet renames one or more Subnet(s).
You can specify the Subnet(s) using either the -SubnetName or -SubnetId Parameter.

.PARAMETER SubnetId
The -SubnetId Parameter specifies the Subnet ID.
This parameter supports pipeline inputs.
See example 1.

.PARAMETER SubnetName
The -SubnetName Parameter specifies the Subnet's Name.
You can use glob wildcards to match multiple Subnets.
See example 2.

.PARAMETER NewName
The -NewName Parameter specifies the new Name.

.EXAMPLE
Rename-Subnet -SubnetId subnet-12345678901234560 -NewName 'example-1-new '

This example renames the Subnet subnet-12345678901234560 to "example-1-new".

.EXAMPLE
Rename-Subnet -SubnetName example-2 -NewName example-2-new

This example renames the Subnet(s) named "example-2" to "example-2-new".

#>

function Rename-Subnet
{
    [Alias("subnet_rn")]
    [CmdletBinding(DefaultParameterSetName = 'SubnetName', SupportsShouldProcess)]
    param (
        [Parameter(ParameterSetName = 'SubnetId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]
        $SubnetId,

        [Parameter(ParameterSetName = 'SubnetName', Mandatory, Position = 0)]
        [string]
        $SubnetName,

        [Parameter(Mandatory, Position = 1)]
        [string]
        $NewName
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
        $_new_name    = $NewName

        # Configure the filter to query the Subnet.
        $_filter_name  = $_param_set -eq 'SubnetId' ? 'subnet-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'SubnetId' ? $_subnet_id : $_subnet_name

        # Query the list of Subnet to rename first.
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

        # If no Subnets matched the filter value, exit early.
        if (-not $_subnet_list)
        {
            Write-Error "No Subnet was found for '$_filter_value'."
            return
        }

        # Loop through each Subnet to perform the renaming.
        $_subnet_list | ForEach-Object {

            # Generate a friendly display string for the Subnet.
            $_format_subnet = $_ | Get-ResourceString -IdPropertyName 'SubnetId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            # Display What-If/Confirm prompt.
            if ($PSCmdlet.ShouldProcess($_format_subnet, "Rename Subnet"))
            {
                # Call the API to revalue the Name Tag.
                try {
                    New-EC2Tag -Resource $_.SubnetId -Tag @{Key = 'Name'; Value = $_new_name} -Verbose:$false
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