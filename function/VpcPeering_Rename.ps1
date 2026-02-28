function Rename-VpcPeering
{
    [Alias('pcx_rn')]
    [CmdletBinding(DefaultParameterSetName = 'VpcPeeringConnectionName', SupportsShouldProcess)]
    param (
        [Parameter(
            ParameterSetName = 'VpcPeeringConnectionId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName
        )]
        [ValidatePattern('^pcx-[0-9a-f]{17}$', ErrorMessage = 'Invalid VpcPeeringConnectionId.')]
        [string]
        $VpcPeeringConnectionId,

        [Parameter(ParameterSetName = 'VpcPeeringConnectionName', Mandatory, Position = 0)]
        [string]
        $VpcPeeringConnectionName,

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
        $_pcx_id   = $VpcPeeringConnectionId
        $_pcx_name = $VpcPeeringConnectionName
        $_new_name = $NewName

        # Configure the filter to query the Subnet.
        $_filter_name  = $_param_set -eq 'VpcPeeringConnectionId' ? 'vpc-peering-connection-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'VpcPeeringConnectionId' ? $_pcx_id : $_pcx_name

        # Query the list of Subnet to rename first.
        try {
            $_pcx_list = Get-EC2VpcPeeringConnection -Verbose:$false -Filter @{
                Name = $_filter_name;
                Values = $_filter_value
            }
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If no VPC matched the filter value, exit early.
        if (-not $_pcx_list)
        {
            Write-Error "No VPC Peering Connection was found for '$_filter_value'."
            return
        }

        # Loop through each VPC to perform the renaming.
        $_pcx_list | ForEach-Object {

            # Generate a friendly display string for the VPC Peering Connection.
            $_format_pcx = $_ | Get-ResourceString `
                -IdPropertyName 'VpcPeeringConnectionId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            # Display What-If/Confirm prompt.
            if ($PSCmdlet.ShouldProcess($_format_pcx, "Rename VPC Peering Connection."))
            {
                # Call the API to revalue the Name Tag.
                try {
                    New-EC2Tag -Verbose:$false `
                        -Resource $_.VpcPeeringConnectionId -Tag @{Key = 'Name'; Value = $_new_name}
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